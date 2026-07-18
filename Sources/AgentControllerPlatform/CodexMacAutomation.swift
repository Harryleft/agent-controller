@preconcurrency import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import AgentControllerCore
import OSLog

/// 仅向 Codex 投递一小组固定快捷键的 macOS 自动化适配器。
///
/// 不提供任意键码、任意修饰键或任意目标应用的公开接口，避免平台层
/// 被误用为通用键盘注入器。
@MainActor
public final class CodexMacAutomation {
    public static let codexBundleIdentifier = "com.openai.codex"

    private let logger = Logger(
        subsystem: "com.harryleft.agent-controller.macos",
        category: "Automation"
    )

    public init() {}

    public var isCodexRunning: Bool {
        codexApplication != nil
    }

    public var isCodexForeground: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.codexBundleIdentifier
    }

    public var canPostEvents: Bool {
        MacInputAuthorization.canPostEvents
    }

    /// 显示系统权限提示，并返回完整控制权限是否已就绪。
    @discardableResult
    public func requestAuthorization() -> Bool {
        let canPostEvents =
            MacInputAuthorization.requestPostEventAccess()
        _ = MacInputAuthorization.promptForAccessibilityTrust()
        return canPostEvents &&
            MacInputAuthorization.isAccessibilityTrusted
    }

    /// 执行白名单内的动作。除 `wake` 外，投递前会重新确认 Codex 位于前台。
    @discardableResult
    public func execute(_ action: ControllerAction) -> Bool {
        switch action {
        case .wakeCodex:
            return activateOrLaunchCodex()
        case .openSelected:
            return inject(.returnKey)
        case .submit:
            // The installed Codex app defaults composerEnterBehavior to
            // `enter`; users who change that setting need a configurable
            // submit binding in a future version.
            return inject(.returnKey)
        case .openNewThread:
            return inject(.n, modifiers: .maskCommand)
        case .cancel, .stopTask:
            return inject(.escape)
        case .startDictation, .stopDictation:
            // Dictation must use setDictation(recording:). A posted keyboard
            // event has no delivery acknowledgement and must never be treated
            // as proof that Codex actually started or stopped recording.
            logger.error("dictation blocked reason=unconfirmed-shortcut-path")
            return false
        case let .navigate(direction):
            return inject(keyCode(for: direction))
        case .openModelPicker:
            return inject(.m, modifiers: [.maskControl, .maskShift])
        }
    }

    /// 切换 Codex 听写，并以当前主窗口的辅助功能状态作为成功判据。
    ///
    /// Electron 对听写按钮暴露了 AXButton，但 AXPress 在当前 Codex
    /// 版本不会触发 React 点击处理器。因此这里只用 AX 精确定位并聚焦
    /// 控件，随后向 Codex PID 定向发送 Space，再读取新 AX 树确认状态。
    public func setDictation(
        recording: Bool
    ) async -> CodexDictationAutomationResult {
        guard MacInputAuthorization.canPostEvents else {
            return logDictationResult(.postEventDenied, recording: recording)
        }
        guard MacInputAuthorization.isAccessibilityTrusted else {
            return logDictationResult(.accessibilityDenied, recording: recording)
        }
        guard let application = foregroundCodexApplication else {
            return logDictationResult(.codexNotForeground, recording: recording)
        }

        let pid = application.processIdentifier
        let before = dictationSnapshot(for: pid)
        let desiredKind: CodexDictationControlKind =
            recording ? .start : .stop

        switch (recording, before.state) {
        case (true, .recording), (false, .idle):
            return logDictationResult(.alreadySatisfied, recording: recording)
        case (true, .idle), (false, .recording):
            break
        case (_, .ambiguous), (_, .transitional), (_, .unavailable):
            return logDictationResult(.controlUnavailable, recording: recording)
        }

        guard let control = before.control(for: desiredKind) else {
            return logDictationResult(.controlUnavailable, recording: recording)
        }
        guard let targetWindow = before.window else {
            return logDictationResult(.controlUnavailable, recording: recording)
        }

        let activationResult = await activate(
            control,
            in: targetWindow,
            targetPID: pid
        )
        switch activationResult {
        case .posted:
            break
        case .codexNotForeground:
            return logDictationResult(.codexNotForeground, recording: recording)
        case .focusFailed:
            return logDictationResult(.controlUnavailable, recording: recording)
        case .eventCreationFailed:
            return logDictationResult(.eventCreationFailed, recording: recording)
        }

        let confirmed = await waitForDictationState(
            recording: recording,
            expectedWindow: targetWindow,
            targetPID: pid
        )
        return logDictationResult(
            confirmed ? .confirmed : .stateNotConfirmed,
            recording: recording
        )
    }

    private var codexApplication: NSRunningApplication? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.codexBundleIdentifier
        ).first
    }

    /// 唤醒时只激活或启动，不投递任何输入事件。
    @discardableResult
    private func activateOrLaunchCodex() -> Bool {
        if let application = codexApplication {
            return application.activate()
        }

        guard let appURL = codexApplicationURL else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
        return true
    }

    private var codexApplicationURL: URL? {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.codexBundleIdentifier
        ) ?? existingChatGPTApplicationURL
    }

    private var existingChatGPTApplicationURL: URL? {
        let url = URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path),
              Bundle(url: url)?.bundleIdentifier ==
                Self.codexBundleIdentifier else {
            return nil
        }
        return url
    }

    private func inject(
        _ keyCode: KeyCode,
        modifiers: CGEventFlags = []
    ) -> Bool {
        guard MacInputAuthorization.canPostEvents else {
            logger.error("inject blocked reason=post-event-access")
            return false
        }

        if foregroundCodexApplication == nil {
            _ = activateOrLaunchCodex()
        }
        let target = foregroundCodexApplication
        guard let target else {
            logger.error("inject blocked reason=codex-not-foreground-or-running")
            return false
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode.rawValue,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode.rawValue,
                  keyDown: false
              ) else {
            logger.error("inject blocked reason=event-creation")
            return false
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        // Target the verified Codex process instead of the global HID stream.
        // If focus changes after the foreground check, the event cannot land
        // in the newly-frontmost application.
        keyDown.postToPid(target.processIdentifier)
        keyUp.postToPid(target.processIdentifier)
        return true
    }

    private func dictationSnapshot(
        for processIdentifier: pid_t
    ) -> DictationSnapshot {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let root =
                elementAttribute(application, kAXFocusedWindowAttribute) ??
                elementAttribute(application, kAXMainWindowAttribute),
              stringAttribute(root, kAXRoleAttribute) ==
                (kAXWindowRole as String),
              let rootFrame = frame(of: root) else {
            return .unavailable
        }

        var startControls: [DictationControl] = []
        var stopControls: [DictationControl] = []
        var stack: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var visitedCount = 0

        while let current = stack.popLast(), visitedCount < 5_000 {
            visitedCount += 1
            if let candidate = dictationControl(
                from: current.element,
                constrainedTo: rootFrame
            ) {
                switch candidate.kind {
                case .start:
                    startControls.append(candidate)
                case .stop:
                    stopControls.append(candidate)
                }
            }

            guard current.depth < 30 else { continue }
            for child in children(of: current.element).reversed() {
                stack.append((child, current.depth + 1))
            }
        }

        // An incomplete traversal or multiple exact controls is not safe
        // enough for focused activation. Refuse instead of guessing.
        guard stack.isEmpty,
              startControls.count <= 1,
              stopControls.count <= 1 else {
            return DictationSnapshot(
                startControl: nil,
                stopControl: nil,
                window: root,
                forcedState: startControls.count > 1 ||
                    stopControls.count > 1
                    ? .ambiguous : .unavailable
            )
        }
        return DictationSnapshot(
            startControl: startControls.first,
            stopControl: stopControls.first,
            window: root
        )
    }

    private func dictationControl(
        from element: AXUIElement,
        constrainedTo rootFrame: CGRect?
    ) -> DictationControl? {
        guard stringAttribute(element, kAXRoleAttribute) ==
                (kAXButtonRole as String) else {
            return nil
        }
        if let enabled = boolAttribute(element, kAXEnabledAttribute),
           !enabled {
            return nil
        }

        let labels = [
            stringAttribute(element, kAXDescriptionAttribute),
            stringAttribute(element, kAXTitleAttribute),
            stringAttribute(element, kAXHelpAttribute)
        ].compactMap { $0 }
        guard let kind = labels.lazy.compactMap({
            CodexDictationControlKind.classify(
                accessibilityLabel: $0
            )
        }).first,
              let controlFrame = frame(of: element),
              controlFrame.width >= 12,
              controlFrame.height >= 12,
              controlFrame.width <= 160,
              controlFrame.height <= 160 else {
            return nil
        }

        let center = CGPoint(
            x: controlFrame.midX,
            y: controlFrame.midY
        )
        guard center.x.isFinite, center.y.isFinite,
              rootFrame?.contains(center) ?? true else {
            return nil
        }
        return DictationControl(
            kind: kind,
            element: element
        )
    }

    private func waitForDictationState(
        recording: Bool,
        expectedWindow: AXUIElement,
        targetPID: pid_t
    ) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(6)
        var consecutiveStoppedSnapshots = 0
        repeat {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled,
                  foregroundCodexApplication?.processIdentifier == targetPID else {
                return false
            }
            // Always create a new AX application/root. Reusing the same
            // element can expose Electron's pre-render state after activation.
            let snapshot = dictationSnapshot(for: targetPID)
            guard let currentWindow = snapshot.window,
                  CFEqual(currentWindow, expectedWindow) else {
                return false
            }
            let state = snapshot.state
            if recording {
                if state == .recording { return true }
            } else {
                // Stopping first removes “Stop dictation”, then Codex spends a
                // short interval transcribing before “Dictate” returns. Only
                // the explicit reappearance of the unique start control counts
                // as stopped; an empty or partially readable tree never does.
                if state == .idle {
                    consecutiveStoppedSnapshots += 1
                    if consecutiveStoppedSnapshots >= 2 { return true }
                } else {
                    consecutiveStoppedSnapshots = 0
                }
            }
        } while ContinuousClock.now < deadline
        return false
    }

    private func activate(
        _ control: DictationControl,
        in expectedWindow: AXUIElement,
        targetPID: pid_t
    ) async -> ControlActivationResult {
        guard foregroundCodexApplication?.processIdentifier == targetPID else {
            return .codexNotForeground
        }

        let application = AXUIElementCreateApplication(targetPID)
        let previouslyFocused = elementAttribute(
            application,
            kAXFocusedUIElementAttribute
        )
        guard AXUIElementSetAttributeValue(
            control.element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        ) == .success else {
            return .focusFailed
        }
        // Electron publishes the new AX focus asynchronously. Wait for one
        // short UI turn, then verify both the exact element and its window
        // before sending Space.
        try? await Task.sleep(for: .milliseconds(30))
        let focusedControl = elementAttribute(
            application,
            kAXFocusedUIElementAttribute
        )
        let focusedWindow = elementAttribute(
            application,
            kAXFocusedWindowAttribute
        )
        guard foregroundCodexApplication?.processIdentifier == targetPID,
              let focusedControl,
              CFEqual(focusedControl, control.element),
              let focusedWindow,
              CFEqual(focusedWindow, expectedWindow) else {
            restoreFocus(previouslyFocused)
            return foregroundCodexApplication?.processIdentifier == targetPID
                ? .focusFailed : .codexNotForeground
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: KeyCode.space.rawValue,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: KeyCode.space.rawValue,
                  keyDown: false
              ) else {
            restoreFocus(previouslyFocused)
            return .eventCreationFailed
        }

        // The key pair is addressed only to the verified Codex process. It
        // cannot land in another application if focus changes after this check.
        guard foregroundCodexApplication?.processIdentifier == targetPID else {
            restoreFocus(previouslyFocused)
            return .codexNotForeground
        }
        keyDown.postToPid(targetPID)
        keyUp.postToPid(targetPID)
        try? await Task.sleep(for: .milliseconds(60))
        restoreFocus(previouslyFocused)
        return .posted
    }

    private func restoreFocus(_ element: AXUIElement?) {
        guard let element else { return }
        let error = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        if error != .success {
            logger.debug(
                "dictation focus-restore result=\(error.rawValue, privacy: .public)"
            )
        }
    }

    private func logDictationResult(
        _ result: CodexDictationAutomationResult,
        recording: Bool
    ) -> CodexDictationAutomationResult {
        let target = recording ? "recording" : "idle"
        logger.info(
            "dictation target=\(target, privacy: .public) result=\(result.logValue, privacy: .public)"
        )
        return result
    }

    private func copyAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value
    }

    private func stringAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> String? {
        copyAttribute(element, attribute) as? String
    }

    private func boolAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> Bool? {
        (copyAttribute(element, attribute) as? NSNumber)?.boolValue
    }

    private func elementAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(element, kAXChildrenAttribute),
              CFGetTypeID(value) == CFArrayGetTypeID() else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(element, kAXPositionAttribute),
              let size = sizeAttribute(element, kAXSizeAttribute),
              position.x.isFinite,
              position.y.isFinite,
              size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func pointAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> CGPoint? {
        guard let rawValue = copyAttribute(element, attribute),
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeDowncast(rawValue, to: AXValue.self)
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> CGSize? {
        guard let rawValue = copyAttribute(element, attribute),
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeDowncast(rawValue, to: AXValue.self)
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private var foregroundCodexApplication: NSRunningApplication? {
        guard let application =
                NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier ==
                Self.codexBundleIdentifier else {
            return nil
        }
        return application
    }

    private func keyCode(for direction: NavigationDirection) -> KeyCode {
        switch direction {
        case .up: .upArrow
        case .down: .downArrow
        case .left: .leftArrow
        case .right: .rightArrow
        }
    }
}

private enum DictationState: Equatable {
    case idle
    case recording
    case ambiguous
    case transitional
    case unavailable
}

private struct DictationControl {
    let kind: CodexDictationControlKind
    let element: AXUIElement
}

private struct DictationSnapshot {
    let startControl: DictationControl?
    let stopControl: DictationControl?
    let window: AXUIElement?

    var state: DictationState {
        if let forcedState { return forcedState }
        if startControl != nil && stopControl != nil {
            return .ambiguous
        }
        if stopControl != nil { return .recording }
        if startControl != nil { return .idle }
        return .transitional
    }

    func control(
        for kind: CodexDictationControlKind
    ) -> DictationControl? {
        switch kind {
        case .start: startControl
        case .stop: stopControl
        }
    }

    static let unavailable = DictationSnapshot(
        startControl: nil,
        stopControl: nil,
        window: nil,
        forcedState: .unavailable
    )

    init(
        startControl: DictationControl?,
        stopControl: DictationControl?,
        window: AXUIElement?,
        forcedState: DictationState? = nil
    ) {
        self.startControl = startControl
        self.stopControl = stopControl
        self.window = window
        self.forcedState = forcedState
    }

    private let forcedState: DictationState?
}

private enum ControlActivationResult {
    case posted
    case codexNotForeground
    case focusFailed
    case eventCreationFailed
}

private struct KeyCode: RawRepresentable {
    let rawValue: CGKeyCode

    static let returnKey = KeyCode(rawValue: 36)
    static let escape = KeyCode(rawValue: 53)
    static let leftArrow = KeyCode(rawValue: 123)
    static let rightArrow = KeyCode(rawValue: 124)
    static let downArrow = KeyCode(rawValue: 125)
    static let upArrow = KeyCode(rawValue: 126)
    static let space = KeyCode(rawValue: 49)
    static let m = KeyCode(rawValue: 46)
    static let n = KeyCode(rawValue: 45)
}
