import Foundation

/// 豆包输入法的右 Option 按住说话快捷键的投递结果。
///
/// 这是“已投递键盘状态”，不是“转写已经完成”。转写是否进入 Codex
/// 输入框由用户可见的输入结果验收，桥接不读取提示词正文。
public enum DoubaoVoiceShortcutAutomationResult: Equatable, Sendable {
    case held
    case released
    case alreadyHeld
    case alreadyReleased
    case accessibilityDenied
    case postEventDenied
    case codexNotForeground
    case eventCreationFailed

    public var applied: Bool {
        switch self {
        case .held, .released, .alreadyHeld, .alreadyReleased:
            true
        case .accessibilityDenied, .postEventDenied,
             .codexNotForeground, .eventCreationFailed:
            false
        }
    }

    public var diagnostic: String {
        switch self {
        case .held: "右 Option 已按住"
        case .released: "右 Option 已释放"
        case .alreadyHeld: "右 Option 已处于按住状态"
        case .alreadyReleased: "右 Option 已处于释放状态"
        case .accessibilityDenied: "缺少辅助功能权限"
        case .postEventDenied: "缺少事件投递权限"
        case .codexNotForeground: "Codex 不在前台"
        case .eventCreationFailed: "无法创建右 Option 事件"
        }
    }

    var logValue: String {
        switch self {
        case .held: "held"
        case .released: "released"
        case .alreadyHeld: "already-held"
        case .alreadyReleased: "already-released"
        case .accessibilityDenied: "accessibility-denied"
        case .postEventDenied: "post-event-denied"
        case .codexNotForeground: "codex-not-foreground"
        case .eventCreationFailed: "event-creation-failed"
        }
    }
}
