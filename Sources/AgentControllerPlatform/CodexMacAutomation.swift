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
    private var selectedSidebarThreadID: UUID?

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

    public var hasSidebarTaskSelection: Bool {
        selectedSidebarThreadID != nil
    }

    /// Activate or launch Codex, then confirm that the same process owns the
    /// foreground twice.  Request acceptance alone is not a wake result.
    public func wakeCodexAndConfirm() async -> CodexWakeAutomationResult {
        let application: NSRunningApplication?
        if let running = codexApplication {
            guard running.activate() else { return .unavailable }
            application = running
        } else {
            guard let appURL = codexApplicationURL else { return .unavailable }
            application = await launchCodex(at: appURL)
        }

        guard let application,
              application.bundleIdentifier == Self.codexBundleIdentifier,
              application.processIdentifier > 0 else {
            return .unavailable
        }

        return await confirmForeground(
            processIdentifier: application.processIdentifier
        ) ? .foregroundConfirmed : .unavailable
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
            // Wake is asynchronous because success requires fresh foreground
            // observations. Call wakeCodexAndConfirm() instead.
            logger.error("wake blocked reason=async-confirmation-required")
            return false
        case .openSelected:
            // Opening a task is handled only by the asynchronous sidebar or
            // workspace adapters after they establish a unique task identity.
            // Never fall back to Return when there is no confirmed candidate.
            logger.error("open blocked reason=no-confirmed-task-candidate")
            return false
        case .submit:
            clearSidebarTaskSelection()
            // A directed Return event is only a transport attempt.  Codex
            // exposes no stable, exact AX state transition for "submitted",
            // so never inject it and then report success.
            logger.error("submit blocked reason=no-ui-confirmation-contract")
            return false
        case .openNewThread:
            clearSidebarTaskSelection()
            return inject(.n, modifiers: .maskCommand)
        case .cancel, .stopTask:
            clearSidebarTaskSelection()
            // Escape can close a transient view, dismiss an unrelated menu,
            // or be ignored.  Without an exact post-action receipt it must
            // remain unavailable rather than claiming a cancellation.
            logger.error("cancel blocked reason=no-ui-confirmation-contract")
            return false
        case .startDictation, .stopDictation:
            // Dictation must use setDictation(recording:). A posted keyboard
            // event has no delivery acknowledgement and must never be treated
            // as proof that Codex actually started or stopped recording.
            logger.error("dictation blocked reason=unconfirmed-shortcut-path")
            return false
        case let .navigate(direction):
            clearSidebarTaskSelection()
            return inject(keyCode(for: direction))
        case .selectSidebarTask:
            logger.error(
                "sidebar selection blocked reason=async-confirmation-required"
            )
            return false
        case .openModelPicker:
            clearSidebarTaskSelection()
            return inject(.m, modifiers: [.maskControl, .maskShift])
        case .workspaceCatalog, .questionAnswer,
             .openPreviousTask, .openNextTask, .selectAgentSlot,
             .command, .running, .openActionPanel, .closeActionPanel,
             .actionPanel:
            // These intents are deliberately modeled before their semantic
            // adapters are enabled. Never fall back to an arbitrary shortcut:
            // each adapter must add its own observable confirmation first.
            clearSidebarTaskSelection()
            logger.error(
                "action blocked reason=semantic-adapter-unavailable"
            )
            return false
        }
    }

    /// Direct a model shortcut only after its exact binding has been verified.
    /// No current Model/Effort/Speed AX contract is stable enough to confirm a
    /// fresh value or menu transition, so a posted event is deliberately
    /// returned as unavailable rather than as UI success.
    public func executeModelControl(
        _ action: ModelControlAction,
        bindingAvailability: CodexKeybindingAvailability
    ) -> CodexModelControlAutomationResult {
        guard bindingAvailability == .available else {
            logger.error("model control blocked reason=binding-unavailable")
            return .unavailable
        }
        guard case let .shortcut(shortcut) =
                CodexModelControlDispatchPlan.resolve(action) else {
            logger.error("model control blocked reason=ui-contract-unavailable")
            return .unavailable
        }

        let posted: Bool
        switch shortcut {
        case let .semantic(semanticAction):
            posted = inject(keyCode(for: semanticAction))
        }
        guard posted else { return .unavailable }
        return .shortcutPostedWithoutUIConfirmation
    }

    /// Move a controller-owned candidate through tasks currently visible in
    /// the Codex sidebar. This changes only exact AX focus and never opens a
    /// task. Full titles are reduced to one-way identities during discovery;
    /// logs contain only a short hash derived from the resolved thread UUID.
    public func selectSidebarTask(
        direction: SidebarTaskDirection
    ) async -> CodexSidebarAutomationResult {
        guard MacInputAuthorization.isAccessibilityTrusted else {
            return logSidebarResult(.accessibilityDenied, operation: "select")
        }
        guard let application = foregroundCodexApplication else {
            clearSidebarTaskSelection()
            return logSidebarResult(.codexNotForeground, operation: "select")
        }

        let pid = application.processIdentifier
        guard let sessionIndex = await Self.loadSessionIndex() else {
            clearSidebarTaskSelection()
            return logSidebarResult(.taskListUnavailable, operation: "select")
        }
        guard !Task.isCancelled,
              foregroundCodexApplication?.processIdentifier == pid else {
            clearSidebarTaskSelection()
            return logSidebarResult(.codexNotForeground, operation: "select")
        }
        switch sidebarSnapshot(for: pid, sessionIndex: sessionIndex) {
        case .unavailable:
            clearSidebarTaskSelection()
            return logSidebarResult(.taskListUnavailable, operation: "select")
        case .ambiguous:
            clearSidebarTaskSelection()
            return logSidebarResult(.taskListAmbiguous, operation: "select")
        case let .available(snapshot):
            guard let index = snapshot.catalog.destinationIndex(
                selectedThreadID: selectedSidebarThreadID,
                currentThreadID: snapshot.currentThreadID,
                direction: direction
            ) else {
                clearSidebarTaskSelection()
                return logSidebarResult(
                    .taskListUnavailable,
                    operation: "select"
                )
            }

            let target = snapshot.controls[index]
            guard await focusSidebarTask(
                target,
                expectedWindow: snapshot.window,
                targetPID: pid
            ) else {
                clearSidebarTaskSelection()
                let result: CodexSidebarAutomationResult =
                    foregroundCodexApplication?.processIdentifier == pid
                    ? .focusFailed : .codexNotForeground
                return logSidebarResult(result, operation: "select")
            }

            selectedSidebarThreadID = target.task.threadID
            return logSidebarResult(
                .selectionConfirmed(
                    position: index + 1,
                    total: snapshot.controls.count,
                    identityHash: target.task.diagnosticIdentity
                ),
                operation: "select",
                direction: direction
            )
        }
    }

    /// Open the previously confirmed sidebar candidate through Codex's fixed
    /// `codex://threads/<uuid>` route, then read a fresh AX toolbar state until
    /// the same uniquely-resolved identity is observed twice. Merely handing
    /// the URL to Launch Services is never returned as success.
    public func openSelectedSidebarTask() async -> CodexSidebarAutomationResult {
        guard MacInputAuthorization.isAccessibilityTrusted else {
            return logSidebarResult(.accessibilityDenied, operation: "open")
        }
        guard let selectedThreadID = selectedSidebarThreadID else {
            return logSidebarResult(.noSelection, operation: "open")
        }
        guard let application = foregroundCodexApplication else {
            clearSidebarTaskSelection()
            return logSidebarResult(.codexNotForeground, operation: "open")
        }

        let pid = application.processIdentifier
        guard let sessionIndex = await Self.loadSessionIndex() else {
            clearSidebarTaskSelection()
            return logSidebarResult(.selectionExpired, operation: "open")
        }
        guard !Task.isCancelled,
              foregroundCodexApplication?.processIdentifier == pid else {
            clearSidebarTaskSelection()
            return logSidebarResult(.codexNotForeground, operation: "open")
        }
        switch sidebarSnapshot(for: pid, sessionIndex: sessionIndex) {
        case .unavailable:
            clearSidebarTaskSelection()
            return logSidebarResult(.selectionExpired, operation: "open")
        case .ambiguous:
            clearSidebarTaskSelection()
            return logSidebarResult(.taskListAmbiguous, operation: "open")
        case let .available(snapshot):
            guard let index = snapshot.catalog.index(
                ofThreadID: selectedThreadID
            ) else {
                clearSidebarTaskSelection()
                return logSidebarResult(.selectionExpired, operation: "open")
            }
            let target = snapshot.controls[index]

            if snapshot.catalog.confirmsOpen(
                taskAt: index,
                currentThreadID: snapshot.currentThreadID
            ) {
                return logSidebarResult(
                    .openConfirmed(
                        position: index + 1,
                        total: snapshot.controls.count,
                        identityHash: target.task.diagnosticIdentity
                    ),
                    operation: "open"
                )
            }

            guard await focusSidebarTask(
                target,
                expectedWindow: snapshot.window,
                targetPID: pid
            ) else {
                clearSidebarTaskSelection()
                let result: CodexSidebarAutomationResult =
                    foregroundCodexApplication?.processIdentifier == pid
                    ? .focusFailed : .codexNotForeground
                return logSidebarResult(result, operation: "open")
            }
            guard !Task.isCancelled,
                  foregroundCodexApplication?.processIdentifier == pid else {
                clearSidebarTaskSelection()
                return logSidebarResult(
                    .codexNotForeground,
                    operation: "open"
                )
            }
            guard let deepLink = CodexThreadDeepLink.url(
                for: target.task.threadID
            ) else {
                return logSidebarResult(
                    .activationFailed,
                    operation: "open"
                )
            }
            let handlerURL = NSWorkspace.shared.urlForApplication(
                toOpen: deepLink
            )
            let handlerBundleIdentifier = handlerURL.flatMap {
                Bundle(url: $0)?.bundleIdentifier
            }
            guard CodexThreadDeepLink.acceptsHandler(
                bundleIdentifier: handlerBundleIdentifier
            ) else {
                return logSidebarResult(
                    .deepLinkHandlerUnavailable,
                    operation: "open"
                )
            }
            guard NSWorkspace.shared.open(deepLink) else {
                return logSidebarResult(
                    .activationFailed,
                    operation: "open"
                )
            }

            let confirmed = await waitForSidebarTaskOpen(
                titleIdentity: target.task.titleIdentity,
                expectedWindow: snapshot.window,
                targetPID: pid
            )
            guard confirmed else {
                if foregroundCodexApplication?.processIdentifier != pid {
                    clearSidebarTaskSelection()
                    return logSidebarResult(
                        .codexNotForeground,
                        operation: "open"
                    )
                }
                return logSidebarResult(
                    .openNotConfirmed,
                    operation: "open"
                )
            }
            return logSidebarResult(
                .openConfirmed(
                    position: index + 1,
                    total: snapshot.controls.count,
                    identityHash: target.task.diagnosticIdentity
                ),
                operation: "open"
            )
        }
    }

    /// Open a controller-owned catalog candidate. The UUID is not trusted by
    /// itself: `openSelectedSidebarTask()` immediately rebuilds the visible AX
    /// sidebar and refuses unless the same UUID has one exact, unique title
    /// identity there. The existing deep-link and two consecutive toolbar AX
    /// confirmations then remain the sole success criterion.
    public func openWorkspaceTask(
        threadID: UUID
    ) async -> CodexSidebarAutomationResult {
        clearSidebarTaskSelection()
        selectedSidebarThreadID = threadID
        defer { clearSidebarTaskSelection() }
        return await openSelectedSidebarTask()
    }

    public func clearSidebarTaskSelection() {
        selectedSidebarThreadID = nil
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

    private func launchCodex(at appURL: URL) async -> NSRunningApplication? {
        await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(
                at: appURL,
                configuration: configuration
            ) { application, _ in
                continuation.resume(returning: application)
            }
        }
    }

    private func confirmForeground(processIdentifier: pid_t) async -> Bool {
        var tracker = CodexWakeConfirmationTracker()
        for _ in 0 ..< 40 {
            if tracker.observe(
                frontmostBundleIdentifier: NSWorkspace.shared
                    .frontmostApplication?.bundleIdentifier,
                frontmostProcessIdentifier: NSWorkspace.shared
                    .frontmostApplication?.processIdentifier,
                expectedBundleIdentifier: Self.codexBundleIdentifier,
                expectedProcessIdentifier: processIdentifier
            ) {
                return true
            }
            guard !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
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

    private func sidebarSnapshot(
        for processIdentifier: pid_t,
        sessionIndex: CodexSessionIndex
    ) -> SidebarSnapshotResult {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let window =
                elementAttribute(application, kAXFocusedWindowAttribute) ??
                elementAttribute(application, kAXMainWindowAttribute),
              stringAttribute(window, kAXRoleAttribute) ==
                (kAXWindowRole as String),
              let windowFrame = frame(of: window) else {
            return .unavailable
        }

        let windowTree = traversal(of: window, limit: 8_000, maxDepth: 35)
        guard windowTree.complete,
              let sidebarEntry = uniqueSidebarEntry(
                in: windowTree.entries,
                windowFrame: windowFrame
              ),
              let sidebarFrame = frame(of: sidebarEntry.element) else {
            return .unavailable
        }

        let sidebarTree = traversal(
            of: sidebarEntry.element,
            limit: 3_000,
            maxDepth: 24
        )
        guard sidebarTree.complete else { return .unavailable }
        let navigationEntries = sidebarTree.entries.filter {
            stringAttribute($0.element, kAXRoleAttribute) ==
                (kAXGroupRole as String) &&
            stringAttribute($0.element, kAXSubroleAttribute) ==
                "AXLandmarkNavigation"
        }
        guard navigationEntries.count == 1 else {
            return navigationEntries.isEmpty ? .unavailable : .ambiguous
        }

        let navigation = navigationEntries[0].element
        let navigationTree = traversal(
            of: navigation,
            limit: 3_000,
            maxDepth: 24
        )
        guard navigationTree.complete else { return .unavailable }

        let listEntries = navigationTree.entries.filter {
            stringAttribute($0.element, kAXRoleAttribute) ==
                (kAXListRole as String) &&
            stringAttribute($0.element, kAXSubroleAttribute) ==
                "AXContentList"
        }
        let leafLists = listEntries.filter { entry in
            !listEntries.contains { other in
                !CFEqual(other.element, entry.element) &&
                    other.ancestors.contains {
                        CFEqual($0, entry.element)
                    }
            }
        }
        guard !leafLists.isEmpty else { return .unavailable }

        var discoveredControls: [DiscoveredSidebarTaskControl] = []
        for listEntry in leafLists {
            guard let listFrame = frame(of: listEntry.element) else {
                continue
            }
            for row in children(of: listEntry.element) {
                if let control = sidebarTaskControl(
                    from: row,
                    listFrame: listFrame,
                    windowFrame: windowFrame
                ) {
                    discoveredControls.append(control)
                }
            }
        }

        discoveredControls.sort {
            if $0.frame.minY == $1.frame.minY {
                return $0.frame.minX < $1.frame.minX
            }
            return $0.frame.minY < $1.frame.minY
        }
        guard !discoveredControls.isEmpty else { return .unavailable }

        let titleCounts = Dictionary(
            grouping: discoveredControls,
            by: \.titleIdentity
        ).mapValues(\.count)
        discoveredControls.removeAll {
            titleCounts[$0.titleIdentity] != 1
        }
        guard !discoveredControls.isEmpty else { return .ambiguous }

        let controls: [SidebarTaskControl] = discoveredControls.compactMap {
            control in
            guard let threadID = sessionIndex.uniqueThreadID(
                matching: control.titleIdentity
            ) else {
                return nil
            }
            return SidebarTaskControl(
                task: CodexSidebarTask(
                    threadID: threadID,
                    titleIdentity: control.titleIdentity
                ),
                element: control.element,
                frame: control.frame
            )
        }
        guard !controls.isEmpty else { return .ambiguous }

        let catalog: CodexSidebarTaskCatalog
        do {
            catalog = try CodexSidebarTaskCatalog(
                validating: controls.map(\.task)
            )
        } catch {
            return .ambiguous
        }

        let toolbarIdentities = toolbarTaskTitleIdentities(
            in: windowTree.entries,
            sidebar: sidebarEntry.element,
            sidebarFrame: sidebarFrame,
            windowFrame: windowFrame
        ).filter { catalog.index(ofTitleIdentity: $0) != nil }
        let currentThreadID: UUID?
        switch CodexToolbarIdentityResolver.resolve(toolbarIdentities) {
        case .none:
            currentThreadID = nil
        case let .unique(identity):
            guard let index = catalog.index(ofTitleIdentity: identity) else {
                return .ambiguous
            }
            currentThreadID = catalog.tasks[index].threadID
        case .ambiguous:
            return .ambiguous
        }

        return .available(
            SidebarSnapshot(
                controls: controls,
                catalog: catalog,
                currentThreadID: currentThreadID,
                window: window
            )
        )
    }

    private nonisolated static func loadSessionIndex() async
        -> CodexSessionIndex? {
        await Task.detached(priority: .userInitiated) {
            try? CodexSessionIndex(contentsOf: CodexSessionIndex.defaultURL)
        }.value
    }

    private func uniqueSidebarEntry(
        in entries: [AXTraversalEntry],
        windowFrame: CGRect
    ) -> AXTraversalEntry? {
        let candidates = entries.filter { entry in
            guard stringAttribute(entry.element, kAXRoleAttribute) ==
                    (kAXGroupRole as String),
                  stringAttribute(entry.element, kAXSubroleAttribute) ==
                    "AXLandmarkComplementary",
                  let candidateFrame = frame(of: entry.element) else {
                return false
            }
            return candidateFrame.width >= 140 &&
                candidateFrame.width <= windowFrame.width * 0.40 &&
                candidateFrame.height >= windowFrame.height * 0.50 &&
                abs(candidateFrame.minX - windowFrame.minX) <= 24 &&
                candidateFrame.intersects(windowFrame)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private func sidebarTaskControl(
        from row: AXUIElement,
        listFrame: CGRect,
        windowFrame: CGRect
    ) -> DiscoveredSidebarTaskControl? {
        guard stringAttribute(row, kAXRoleAttribute) ==
                (kAXGroupRole as String) else {
            return nil
        }
        let rowTree = traversal(of: row, limit: 160, maxDepth: 12)
        guard rowTree.complete else { return nil }

        func isFullWidthButton(_ element: AXUIElement) -> Bool {
            guard stringAttribute(element, kAXRoleAttribute) ==
                    (kAXButtonRole as String),
                  boolAttribute(element, kAXEnabledAttribute) != false,
                  let buttonFrame = frame(of: element) else {
                return false
            }
            return buttonFrame.width >= listFrame.width * 0.75 &&
                buttonFrame.width <= listFrame.width * 1.10 &&
                buttonFrame.height >= 18 &&
                buttonFrame.height <= 44 &&
                buttonFrame.intersects(windowFrame)
        }

        let buttons = rowTree.entries.filter {
            isFullWidthButton($0.element)
        }
        let outerButtons = buttons.filter { candidate in
            let hasNestedFullWidthButton = buttons.contains { other in
                !CFEqual(other.element, candidate.element) &&
                    other.ancestors.contains {
                        CFEqual($0, candidate.element)
                    }
            }
            let hasFullWidthAncestor = candidate.ancestors.contains {
                isFullWidthButton($0)
            }
            return hasNestedFullWidthButton && !hasFullWidthAncestor
        }
        guard outerButtons.count == 1,
              let controlFrame = frame(of: outerButtons[0].element) else {
            return nil
        }
        let control = outerButtons[0].element

        let titleValues = Set(
            rowTree.entries.compactMap { entry -> String? in
                guard stringAttribute(entry.element, kAXRoleAttribute) ==
                        (kAXStaticTextRole as String),
                      entry.ancestors.contains(where: {
                          CFEqual($0, control)
                      }) else {
                    return nil
                }
                return nonemptyStringAttribute(
                    entry.element,
                    kAXValueAttribute
                )
            }
        )
        guard titleValues.count == 1,
              let title = titleValues.first,
              let titleIdentity = CodexSidebarTitleIdentity(
                exactTitle: title
              ) else {
            return nil
        }

        return DiscoveredSidebarTaskControl(
            titleIdentity: titleIdentity,
            element: control,
            frame: controlFrame
        )
    }

    private func traversal(
        of root: AXUIElement,
        limit: Int,
        maxDepth: Int
    ) -> AXTraversal {
        var entries: [AXTraversalEntry] = []
        var stack: [(AXUIElement, [AXUIElement], Int)] = [(root, [], 0)]
        var complete = true

        while let (element, ancestors, depth) = stack.popLast() {
            guard entries.count < limit else {
                complete = false
                break
            }
            entries.append(
                AXTraversalEntry(
                    element: element,
                    ancestors: ancestors
                )
            )
            let childElements = children(of: element)
            if depth >= maxDepth {
                if !childElements.isEmpty { complete = false }
                continue
            }
            for child in childElements.reversed() {
                stack.append((child, ancestors + [element], depth + 1))
            }
        }
        if !stack.isEmpty { complete = false }
        return AXTraversal(entries: entries, complete: complete)
    }

    private func focusSidebarTask(
        _ control: SidebarTaskControl,
        expectedWindow: AXUIElement,
        targetPID: pid_t
    ) async -> Bool {
        guard !Task.isCancelled,
              foregroundCodexApplication?.processIdentifier == targetPID,
              AXUIElementSetAttributeValue(
                control.element,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
              ) == .success else {
            return false
        }

        try? await Task.sleep(for: .milliseconds(30))
        let application = AXUIElementCreateApplication(targetPID)
        let focusedControl = elementAttribute(
            application,
            kAXFocusedUIElementAttribute
        )
        let focusedWindow = elementAttribute(
            application,
            kAXFocusedWindowAttribute
        )
        return !Task.isCancelled &&
            foregroundCodexApplication?.processIdentifier == targetPID &&
            focusedControl.map { CFEqual($0, control.element) } == true &&
            focusedWindow.map { CFEqual($0, expectedWindow) } == true
    }

    private func postKey(
        _ keyCode: KeyCode,
        modifiers: CGEventFlags = [],
        to targetPID: pid_t
    ) -> Bool {
        guard foregroundCodexApplication?.processIdentifier == targetPID,
              let source = CGEventSource(stateID: .hidSystemState),
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
            return false
        }
        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.postToPid(targetPID)
        keyUp.postToPid(targetPID)
        return true
    }

    private func waitForSidebarTaskOpen(
        titleIdentity: CodexSidebarTitleIdentity,
        expectedWindow: AXUIElement,
        targetPID: pid_t
    ) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(4)
        var consecutiveMatches = 0
        repeat {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled,
                  foregroundCodexApplication?.processIdentifier == targetPID else {
                return false
            }
            switch exactToolbarTitleState(
                titleIdentity: titleIdentity,
                expectedWindow: expectedWindow,
                targetPID: targetPID
            ) {
            case .match:
                consecutiveMatches += 1
                if consecutiveMatches >= 2 { return true }
            case .noMatch:
                consecutiveMatches = 0
            case .ambiguous, .unavailable:
                return false
            }
        } while ContinuousClock.now < deadline
        return false
    }

    private func exactToolbarTitleState(
        titleIdentity: CodexSidebarTitleIdentity,
        expectedWindow: AXUIElement,
        targetPID: pid_t
    ) -> ExactToolbarTitleState {
        let application = AXUIElementCreateApplication(targetPID)
        guard let window =
                elementAttribute(application, kAXFocusedWindowAttribute) ??
                elementAttribute(application, kAXMainWindowAttribute),
              CFEqual(window, expectedWindow),
              let windowFrame = frame(of: window) else {
            return .unavailable
        }
        let tree = traversal(of: window, limit: 8_000, maxDepth: 35)
        guard tree.complete,
              let sidebarEntry = uniqueSidebarEntry(
                in: tree.entries,
                windowFrame: windowFrame
              ),
              let sidebarFrame = frame(of: sidebarEntry.element) else {
            return .unavailable
        }

        let matches = toolbarTaskTitleIdentities(
            in: tree.entries,
            sidebar: sidebarEntry.element,
            sidebarFrame: sidebarFrame,
            windowFrame: windowFrame
        ).filter { $0 == titleIdentity }
        switch CodexToolbarIdentityResolver.resolve(matches) {
        case .none:
            return .noMatch
        case .unique:
            return .match
        case .ambiguous:
            return .ambiguous
        }
    }

    /// Extract text only from the live structure observed for Codex's current
    /// task header: AXLandmarkMain -> AXSectionHeader -> AXStaticText. A plain
    /// top-of-window text match is not sufficient evidence.
    private func toolbarTaskTitleIdentities(
        in entries: [AXTraversalEntry],
        sidebar: AXUIElement,
        sidebarFrame: CGRect,
        windowFrame: CGRect
    ) -> [CodexSidebarTitleIdentity] {
        entries.compactMap { entry in
            guard stringAttribute(entry.element, kAXRoleAttribute) ==
                    (kAXStaticTextRole as String),
                  !entry.ancestors.contains(where: {
                      CFEqual($0, sidebar)
                  }),
                  let elementFrame = frame(of: entry.element),
                  elementFrame.minX >= sidebarFrame.maxX - 1,
                  elementFrame.midY <= windowFrame.minY + 110,
                  let value = nonemptyStringAttribute(
                    entry.element,
                    kAXValueAttribute
                  ),
                  let identity = CodexSidebarTitleIdentity(
                    exactTitle: value
                  ) else {
                return nil
            }

            let mainIndices = entry.ancestors.indices.filter { index in
                let element = entry.ancestors[index]
                return stringAttribute(element, kAXRoleAttribute) ==
                        (kAXGroupRole as String) &&
                    stringAttribute(element, kAXSubroleAttribute) ==
                        "AXLandmarkMain"
            }
            let headerIndices = entry.ancestors.indices.filter { index in
                let element = entry.ancestors[index]
                return stringAttribute(element, kAXRoleAttribute) ==
                        (kAXGroupRole as String) &&
                    stringAttribute(element, kAXSubroleAttribute) ==
                        "AXSectionHeader"
            }
            guard mainIndices.count == 1,
                  headerIndices.count == 1,
                  mainIndices[0] < headerIndices[0],
                  let mainFrame = frame(
                    of: entry.ancestors[mainIndices[0]]
                  ),
                  let headerFrame = frame(
                    of: entry.ancestors[headerIndices[0]]
                  ),
                  mainFrame.minX >= sidebarFrame.maxX - 1,
                  headerFrame.width >= windowFrame.width * 0.50,
                  headerFrame.height >= 24,
                  headerFrame.height <= 80,
                  abs(headerFrame.minY - windowFrame.minY) <= 8,
                  headerFrame.intersects(elementFrame) else {
                return nil
            }
            return identity
        }
    }

    private func nonemptyStringAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> String? {
        guard let value = stringAttribute(element, attribute)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func logSidebarResult(
        _ result: CodexSidebarAutomationResult,
        operation: String,
        direction: SidebarTaskDirection? = nil
    ) -> CodexSidebarAutomationResult {
        let identity: String
        switch result {
        case let .selectionConfirmed(_, _, hash),
             let .openConfirmed(_, _, hash):
            identity = hash
        default:
            identity = "none"
        }
        logger.info(
            "sidebar operation=\(operation, privacy: .public) direction=\(direction?.rawValue ?? "none", privacy: .public) task=\(identity, privacy: .public) result=\(result.logValue, privacy: .public)"
        )
        return result
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

    private func keyCode(for action: CodexSemanticAction) -> KeyCode {
        switch action {
        case .reasoningDown: .f13
        case .reasoningUp: .f14
        case .openModelPicker: .f15
        case .toggleFastMode: .f16
        // This executor is intentionally only used for model actions.
        case .forkThread: .f17
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

private struct AXTraversalEntry {
    let element: AXUIElement
    let ancestors: [AXUIElement]
}

private struct AXTraversal {
    let entries: [AXTraversalEntry]
    let complete: Bool
}

private struct SidebarTaskControl {
    let task: CodexSidebarTask
    let element: AXUIElement
    let frame: CGRect
}

private struct DiscoveredSidebarTaskControl {
    let titleIdentity: CodexSidebarTitleIdentity
    let element: AXUIElement
    let frame: CGRect
}

private struct SidebarSnapshot {
    let controls: [SidebarTaskControl]
    let catalog: CodexSidebarTaskCatalog
    let currentThreadID: UUID?
    let window: AXUIElement
}

private enum SidebarSnapshotResult {
    case available(SidebarSnapshot)
    case unavailable
    case ambiguous
}

private enum ExactToolbarTitleState {
    case match
    case noMatch
    case ambiguous
    case unavailable
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
    static let f13 = KeyCode(rawValue: 105)
    static let f14 = KeyCode(rawValue: 107)
    static let f15 = KeyCode(rawValue: 113)
    static let f16 = KeyCode(rawValue: 106)
    static let f17 = KeyCode(rawValue: 64)

}
