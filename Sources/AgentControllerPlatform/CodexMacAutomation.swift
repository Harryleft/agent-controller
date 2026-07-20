import AppKit
import CoreGraphics
import Foundation
import OSLog

/// LT/X MVP 的唯一自动化出口：右 Option 控制豆包，Return 提交 Codex。
@MainActor
public final class CodexMacAutomation {
    public static let codexBundleIdentifier = "com.openai.codex"

    private let logger = Logger(
        subsystem: "com.harryleft.agent-controller.macos",
        category: "Automation"
    )
    private var doubaoRightOptionHeld = false

    public init() {}

    public var isCodexForeground: Bool {
        foregroundCodexApplication != nil
    }

    public func setDoubaoVoiceShortcut(
        recording: Bool
    ) -> DoubaoVoiceShortcutAutomationResult {
        guard MacInputAuthorization.canPostEvents else {
            return logVoice(.postEventDenied)
        }
        guard MacInputAuthorization.isAccessibilityTrusted else {
            return logVoice(.accessibilityDenied)
        }
        if recording {
            guard foregroundCodexApplication != nil else {
                return logVoice(.codexNotForeground)
            }
            guard !doubaoRightOptionHeld else { return logVoice(.alreadyHeld) }
            guard postRightOption(isDown: true) else { return logVoice(.eventCreationFailed) }
            doubaoRightOptionHeld = true
            return logVoice(.held)
        }
        guard doubaoRightOptionHeld else { return logVoice(.alreadyReleased) }
        guard postRightOption(isDown: false) else { return logVoice(.eventCreationFailed) }
        doubaoRightOptionHeld = false
        return logVoice(.released)
    }

    public func submit() -> CodexSubmitResult {
        guard MacInputAuthorization.canPostEvents else {
            return logSubmit(.postEventDenied)
        }
        guard let application = foregroundCodexApplication else {
            return logSubmit(.codexNotForeground)
        }
        guard postReturn(to: application.processIdentifier) else {
            return logSubmit(.eventCreationFailed)
        }
        return logSubmit(.posted)
    }

    private var foregroundCodexApplication: NSRunningApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier == Self.codexBundleIdentifier else {
            return nil
        }
        return application
    }

    private func postReturn(to pid: pid_t) -> Bool {
        guard foregroundCodexApplication?.processIdentifier == pid,
              let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else {
            return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return foregroundCodexApplication?.processIdentifier == pid
    }

    private func postRightOption(isDown: Bool) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: 61, keyDown: isDown) else {
            return false
        }
        event.flags = isDown ? .maskAlternate : []
        event.post(tap: .cghidEventTap)
        return true
    }

    private func logVoice(
        _ result: DoubaoVoiceShortcutAutomationResult
    ) -> DoubaoVoiceShortcutAutomationResult {
        logger.info("doubao-voice result=\(result.logValue, privacy: .public)")
        return result
    }

    private func logSubmit(_ result: CodexSubmitResult) -> CodexSubmitResult {
        logger.info("submit result=\(result.logValue, privacy: .public)")
        return result
    }
}

public enum CodexSubmitResult: Equatable, Sendable {
    case posted
    case postEventDenied
    case codexNotForeground
    case eventCreationFailed

    public var logValue: String {
        switch self {
        case .posted: "posted"
        case .postEventDenied: "post-event-denied"
        case .codexNotForeground: "codex-not-foreground"
        case .eventCreationFailed: "event-creation-failed"
        }
    }

    public var diagnostic: String {
        switch self {
        case .posted: "提交已投递"
        case .postEventDenied: "提交失败：缺少事件投递权限"
        case .codexNotForeground: "提交失败：Codex 不在前台"
        case .eventCreationFailed: "提交失败：无法创建 Return 事件"
        }
    }
}
