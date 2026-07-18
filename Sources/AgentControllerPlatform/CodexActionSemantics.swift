import Foundation

/// The closed set of actions exposed by the controller's Y action panel.
/// This is intentionally not string-backed: callers cannot smuggle a command,
/// key, coordinate, or accessibility label through this policy layer.
public enum CodexActionPanelAction: CaseIterable, Equatable, Sendable {
    case newTask
    case historyBack
    case historyForward
    case toggleSidebar
    case clearComposerAfterConfirmation
    case projectContext
}

/// The closed set of actions exposed while holding RB.
public enum CodexCommandAction: CaseIterable, Equatable, Sendable {
    case approve
    case decline
    case fork
    case dispatch
}

/// The closed set of actions exposed while holding RT during a running turn.
public enum CodexRunningAction: CaseIterable, Equatable, Sendable {
    case fork
    case steer
    case queue
    case stop
}

/// The input-layer-specific request. Keeping the layer preserves the meaning
/// of duplicate physical buttons (for example, RB-X and RT-A both fork).
public enum CodexActionRequest: Equatable, Sendable {
    case actionPanel(CodexActionPanelAction)
    case command(CodexCommandAction)
    case running(CodexRunningAction)

    public static let allCases: [CodexActionRequest] =
        CodexActionPanelAction.allCases.map(Self.actionPanel) +
        CodexCommandAction.allCases.map(Self.command) +
        CodexRunningAction.allCases.map(Self.running)
}

/// Evidence which an adapter may establish without relying on labels, screen
/// coordinates, or arbitrary input. This policy does not create evidence.
public enum CodexActionEvidence: Equatable, Sendable {
    case confirmedFixedKeybinding(CodexSemanticAction)
    case confirmedExactAccessibility(CodexExactAccessibilityAction)
}

/// Exact AX contracts must be added here only after a dedicated adapter proves
/// their role, identifier, owning window, and post-action state transition.
/// There are deliberately no such contracts in the current macOS build.
public enum CodexExactAccessibilityAction: Equatable, Sendable {}

/// The only transports the policy can authorize. They contain a closed
/// semantic action, never a raw key or an AX element selected by text.
public enum CodexActionRoute: Equatable, Sendable {
    case fixedKeybinding(CodexSemanticAction)
    case exactAccessibility(CodexExactAccessibilityAction)
}

public enum CodexActionUnavailableReason: Equatable, Sendable {
    /// No safe adapter contract exists for this action in the current build.
    case noVerifiedRoute
    /// A route exists, but the required evidence was not freshly confirmed.
    case evidenceNotConfirmed
}

/// Capability states are intentionally conditional. `available` means a route
/// *may* be used only after the specified evidence is supplied; it is not a
/// claim that Codex accepted the action.
public enum CodexActionCapability: Equatable, Sendable {
    case available(route: CodexActionRoute, requiredEvidence: CodexActionEvidence)
    case unavailable(CodexActionUnavailableReason)
}

public enum CodexActionResult: Equatable, Sendable {
    case authorized(route: CodexActionRoute, evidence: CodexActionEvidence)
    case unavailable(CodexActionUnavailableReason)
}

/// Strict fail-closed routing for Codex action semantics.
///
/// It is a pure policy component: it never sends input, reads Codex state, or
/// provisions `~/.codex`. Approval and running-turn controls remain unavailable
/// until a separate adapter can establish an exact, post-action contract.
public struct CodexActionSemantics: Sendable {
    public init() {}

    public func capability(for request: CodexActionRequest) -> CodexActionCapability {
        switch request {
        case .command(.fork), .running(.fork):
            return .available(
                route: .fixedKeybinding(.forkThread),
                requiredEvidence: .confirmedFixedKeybinding(.forkThread)
            )
        case .actionPanel, .command, .running:
            return .unavailable(.noVerifiedRoute)
        }
    }

    public func resolve(
        _ request: CodexActionRequest,
        evidence: CodexActionEvidence?
    ) -> CodexActionResult {
        switch capability(for: request) {
        case let .available(route, requiredEvidence):
            guard evidence == requiredEvidence else {
                return .unavailable(.evidenceNotConfirmed)
            }
            return .authorized(route: route, evidence: requiredEvidence)
        case let .unavailable(reason):
            return .unavailable(reason)
        }
    }
}
