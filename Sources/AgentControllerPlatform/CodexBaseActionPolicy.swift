import AgentControllerCore

/// Base-layer actions whose old transport was only a directed keyboard event.
///
/// A successfully constructed or posted event says nothing about whether Codex
/// submitted a composer or cancelled a UI state.  These actions stay closed
/// until a dedicated adapter can prove an exact, fresh UI transition without
/// reading composer contents or relying on coordinates.
public enum CodexBaseActionPolicy: Sendable {
    public static func isAvailable(_ action: ControllerAction) -> Bool {
        switch action {
        case .openSelected, .submit, .cancel, .stopTask:
            false
        default:
            true
        }
    }

    public static func unavailableDiagnostic(
        for action: ControllerAction
    ) -> String? {
        switch action {
        case .openSelected:
            "Unavailable · 没有已确认的任务候选"
        case .submit:
            "Unavailable · 缺少提交后的精确 UI 回执"
        case .cancel:
            "Unavailable · 缺少取消后的精确 UI 回执"
        case .stopTask:
            "Unavailable · 缺少停止后的精确 UI 回执"
        default:
            nil
        }
    }
}
