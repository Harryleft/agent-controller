import Foundation

/// Codex 听写控件在当前受支持语言中的精确可访问性名称。
///
/// 这里有意不使用模糊或包含匹配，避免 Codex UI 改版后点击到无关控件。
public enum CodexDictationControlKind: Equatable, Sendable {
    case start
    case stop

    public static func classify(
        accessibilityLabel: String
    ) -> CodexDictationControlKind? {
        if startLabels.contains(accessibilityLabel) {
            return .start
        }
        if stopLabels.contains(accessibilityLabel) {
            return .stop
        }
        return nil
    }

    private static let startLabels: Set<String> = [
        "Dictate",
        "听写",
        "聽寫"
    ]

    private static let stopLabels: Set<String> = [
        "Stop dictation",
        "Stop listening",
        "Stop recording",
        "停止听写",
        "停止聽寫",
        "停止口述",
        "停止录音"
    ]
}

/// 一次 Codex 听写状态切换的、可被调用方明确解释的结果。
public enum CodexDictationAutomationResult: Equatable, Sendable {
    case confirmed
    case alreadySatisfied
    case accessibilityDenied
    case postEventDenied
    case codexNotForeground
    case controlUnavailable
    case eventCreationFailed
    case stateNotConfirmed

    /// 只有已观察到目标状态，才允许上层把桥接状态标记为成功。
    public var succeeded: Bool {
        self == .confirmed || self == .alreadySatisfied
    }

    public var diagnostic: String {
        switch self {
        case .confirmed: "状态已确认"
        case .alreadySatisfied: "目标状态已存在"
        case .accessibilityDenied: "缺少辅助功能权限"
        case .postEventDenied: "缺少事件投递权限"
        case .codexNotForeground: "Codex 不在前台"
        case .controlUnavailable: "未找到听写控件"
        case .eventCreationFailed: "无法创建键盘事件"
        case .stateNotConfirmed: "Codex 未确认状态切换"
        }
    }

    var logValue: String {
        switch self {
        case .confirmed: "confirmed"
        case .alreadySatisfied: "already-satisfied"
        case .accessibilityDenied: "accessibility-denied"
        case .postEventDenied: "post-event-denied"
        case .codexNotForeground: "codex-not-foreground"
        case .controlUnavailable: "control-unavailable"
        case .eventCreationFailed: "event-creation-failed"
        case .stateNotConfirmed: "state-not-confirmed"
        }
    }
}
