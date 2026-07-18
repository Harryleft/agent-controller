import Foundation
import AgentControllerCore

/// Content-free AX facts for the one composer that may be used by Base X.
///
/// This deliberately has no AXValue, label, placeholder, prompt, or reply.
/// A caller may construct it only from the element role, focus/editability,
/// owning-window identity, and AXNumberOfCharacters.
public struct CodexComposerAXElementSnapshot: Equatable, Sendable {
    public let role: String
    public let isFocused: Bool
    public let isEditable: Bool
    /// Opaque identity supplied by a fake AX adapter. It carries no text.
    public let elementIdentity: String
    public let windowIdentity: String
    public let numberOfCharacters: Int?

    public init(
        role: String,
        isFocused: Bool,
        isEditable: Bool,
        elementIdentity: String,
        windowIdentity: String,
        numberOfCharacters: Int?
    ) {
        self.role = role
        self.isFocused = isFocused
        self.isEditable = isEditable
        self.elementIdentity = elementIdentity
        self.windowIdentity = windowIdentity
        self.numberOfCharacters = numberOfCharacters
    }
}

/// A fakeable, content-free observation of the current Codex AX state.
public struct CodexComposerAXSnapshot: Equatable, Sendable {
    public let processIdentifier: Int32
    public let isForegroundCodex: Bool
    public let focusedWindowIdentity: String?
    public let mainWindowIdentity: String?
    public let elements: [CodexComposerAXElementSnapshot]

    public init(
        processIdentifier: Int32,
        isForegroundCodex: Bool,
        focusedWindowIdentity: String?,
        mainWindowIdentity: String?,
        elements: [CodexComposerAXElementSnapshot]
    ) {
        self.processIdentifier = processIdentifier
        self.isForegroundCodex = isForegroundCodex
        self.focusedWindowIdentity = focusedWindowIdentity
        self.mainWindowIdentity = mainWindowIdentity
        self.elements = elements
    }
}

/// The only stable, content-free receipt that Base X may carry across the
/// keyboard event boundary. It is not evidence that a Codex turn completed.
public struct CodexComposerSubmitReceipt: Equatable, Sendable {
    public let processIdentifier: Int32
    public let windowIdentity: String
    public let composerElementIdentity: String

    public init(
        processIdentifier: Int32,
        windowIdentity: String,
        composerElementIdentity: String
    ) {
        self.processIdentifier = processIdentifier
        self.windowIdentity = windowIdentity
        self.composerElementIdentity = composerElementIdentity
    }
}

/// Pure fail-closed policy for Base X. It admits exactly one focused,
/// editable AXTextArea in the focused-or-main Codex window, and never receives
/// composer text.
public struct CodexComposerSubmitVerifier: Sendable {
    public init() {}

    public func begin(
        from snapshot: CodexComposerAXSnapshot
    ) -> CodexComposerSubmitReceipt? {
        guard snapshot.isForegroundCodex,
              snapshot.processIdentifier > 0,
              let windowIdentity = selectedWindowIdentity(in: snapshot),
              let composer = uniqueComposer(
                in: snapshot,
                expectedWindowIdentity: windowIdentity
              ),
              composer.numberOfCharacters ?? 0 > 0 else {
            return nil
        }
        return CodexComposerSubmitReceipt(
            processIdentifier: snapshot.processIdentifier,
            windowIdentity: windowIdentity,
            composerElementIdentity: composer.elementIdentity
        )
    }

    public func confirmsComposerCleared(
        _ receipt: CodexComposerSubmitReceipt,
        after snapshot: CodexComposerAXSnapshot
    ) -> Bool {
        guard snapshot.isForegroundCodex,
              snapshot.processIdentifier == receipt.processIdentifier,
              selectedWindowIdentity(in: snapshot) == receipt.windowIdentity,
              let composer = uniqueComposer(
                in: snapshot,
                expectedWindowIdentity: receipt.windowIdentity
              ),
              composer.elementIdentity == receipt.composerElementIdentity,
              composer.numberOfCharacters == 0 else {
            return false
        }
        return true
    }

    /// Re-checks the receipt immediately before the fixed key is posted. A
    /// newly-rendered Electron text area is not interchangeable with the
    /// original element, even if its PID/window/count look equivalent.
    public func confirmsSameNonEmptyComposer(
        _ receipt: CodexComposerSubmitReceipt,
        beforeDispatch snapshot: CodexComposerAXSnapshot
    ) -> Bool {
        guard snapshot.isForegroundCodex,
              snapshot.processIdentifier == receipt.processIdentifier,
              selectedWindowIdentity(in: snapshot) == receipt.windowIdentity,
              let composer = uniqueComposer(
                in: snapshot,
                expectedWindowIdentity: receipt.windowIdentity
              ),
              composer.elementIdentity == receipt.composerElementIdentity,
              composer.numberOfCharacters ?? 0 > 0 else {
            return false
        }
        return true
    }

    private func selectedWindowIdentity(
        in snapshot: CodexComposerAXSnapshot
    ) -> String? {
        // A disagreement is a window drift, not a harmless fallback.
        switch (snapshot.focusedWindowIdentity, snapshot.mainWindowIdentity) {
        case let (.some(focused), .some(main)) where focused == main:
            focused
        case let (.some(focused), .none):
            focused
        case let (.none, .some(main)):
            main
        default:
            nil
        }
    }

    private func uniqueComposer(
        in snapshot: CodexComposerAXSnapshot,
        expectedWindowIdentity: String
    ) -> CodexComposerAXElementSnapshot? {
        let matches = snapshot.elements.filter {
            $0.role == "AXTextArea" &&
                $0.isFocused &&
                $0.isEditable &&
                $0.windowIdentity == expectedWindowIdentity &&
                $0.numberOfCharacters != nil
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

/// Pure cancellation policy for an in-flight Base X confirmation. The input
/// gate owns cancellation, so stale tasks cannot later publish a receipt.
public enum CodexComposerSubmitRequestGate: Sendable {
    /// A mixed action batch is ambiguous. X is admitted only when no other
    /// controller intent was produced by that same snapshot.
    public static func admitsSubmit(in controllerActions: [ControllerAction]) -> Bool {
        !controllerActions.contains { $0 != .submit }
    }

    public static func cancelsPendingSubmit(
        bridgeEnabled: Bool,
        controllerConnected: Bool,
        sessionPhase: ControllerSessionPhase,
        codexForeground: Bool,
        inputLayer: ControllerInputLayer,
        controllerActions: [ControllerAction]
    ) -> Bool {
        !bridgeEnabled ||
            !controllerConnected ||
            sessionPhase != .active ||
            !codexForeground ||
            inputLayer != .base ||
            !admitsSubmit(in: controllerActions)
    }
}

/// The pre-existing session cleanup boundary is intentionally narrower than
/// the submit-cancellation boundary. Entering an Agent/Command/Action layer
/// cancels a pending X receipt, but must not clear that layer's local state.
public enum CodexControllerSessionGate: Sendable {
    public static func requiresGlobalCleanup(
        bridgeEnabled: Bool,
        controllerConnected: Bool,
        sessionPhase: ControllerSessionPhase,
        codexForeground: Bool
    ) -> Bool {
        !bridgeEnabled ||
            !controllerConnected ||
            sessionPhase != .active ||
            !codexForeground
    }
}

/// The success name intentionally stops at the verified observable fact.
/// It must never be rendered as a completed Codex turn.
public enum CodexComposerSubmitAutomationResult: Equatable, Sendable {
    case composerClearedConfirmed
    case unavailable

    public var diagnostic: String {
        switch self {
        case .composerClearedConfirmed:
            "Composer 已清空（已确认）"
        case .unavailable:
            "提交 · Unavailable"
        }
    }
}
