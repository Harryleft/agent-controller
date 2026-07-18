import AgentControllerCore

/// A fixed, explicitly-provisioned shortcut that can be directed to the
/// foreground Codex process. This is not evidence that Codex changed its UI.
public enum CodexModelControlShortcut: Equatable, Sendable {
    case semantic(CodexSemanticAction)
}

/// Builds only the safe subset of model-control requests. The current Codex
/// accessibility tree does not expose a stable, exact Model/Effort/Speed
/// contract, so advanced controls and the desired "Standard" state fail
/// closed instead of guessing a menu or toggling an unknown value.
public enum CodexModelControlDispatchPlan: Equatable, Sendable {
    case shortcut(CodexModelControlShortcut)
    case unavailable

    public static func resolve(
        _ action: ModelControlAction
    ) -> CodexModelControlDispatchPlan {
        switch action {
        case .adjustReasoningPower(.down):
            return .shortcut(.semantic(.reasoningDown))
        case .adjustReasoningPower(.up):
            return .shortcut(.semantic(.reasoningUp))
        case .selectSimpleSpeed(.fast):
            return .shortcut(.semantic(.toggleFastMode))
        case .openModelMenu(.simple):
            return .shortcut(.semantic(.openModelPicker))
        case .selectSimpleSpeed(.standard),
             .selectAdvancedTarget,
             .stepAdvancedTarget,
             .openModelMenu(.advanced),
             .openAgentControllerSettings:
            return .unavailable
        }
    }
}

/// The platform result intentionally has no success case: posting a shortcut
/// proves delivery only, not a Codex UI state transition. Callers must render
/// this as unavailable until a future exact, fresh AX receipt exists.
public enum CodexModelControlAutomationResult: Equatable, Sendable {
    case unavailable
    case shortcutPostedWithoutUIConfirmation

    public var diagnostic: String {
        switch self {
        case .unavailable:
            "Unavailable"
        case .shortcutPostedWithoutUIConfirmation:
            "Unavailable · 已定向投递，未确认 Codex UI"
        }
    }
}
