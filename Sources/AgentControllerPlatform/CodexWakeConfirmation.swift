import Foundation

/// Requires two fresh foreground samples for the same Codex process.
///
/// An activation request returning `true` only says AppKit accepted the
/// request.  The controller may say "woken" only after this tracker observes
/// the intended bundle and process ID twice in succession.
public struct CodexWakeConfirmationTracker: Sendable {
    private var consecutiveMatches = 0

    public init() {}

    public mutating func observe(
        frontmostBundleIdentifier: String?,
        frontmostProcessIdentifier: Int32?,
        expectedBundleIdentifier: String,
        expectedProcessIdentifier: Int32
    ) -> Bool {
        guard frontmostBundleIdentifier == expectedBundleIdentifier,
              frontmostProcessIdentifier == expectedProcessIdentifier else {
            consecutiveMatches = 0
            return false
        }

        consecutiveMatches += 1
        return consecutiveMatches >= 2
    }
}

public enum CodexWakeAutomationResult: Equatable, Sendable {
    case foregroundConfirmed
    case unavailable

    public var diagnostic: String {
        switch self {
        case .foregroundConfirmed:
            "置前 Codex · 已确认"
        case .unavailable:
            "置前 Codex · Unavailable（未确认前台状态）"
        }
    }
}

/// Rejects stale asynchronous wake completions after a newer request or a
/// controller safety gate closes. It carries no application or UI state.
public struct CodexWakeRequestGate: Sendable {
    private var revision = 0

    public init() {}

    public mutating func begin() -> Int {
        revision &+= 1
        return revision
    }

    public mutating func invalidate() {
        revision &+= 1
    }

    public func accepts(
        _ token: Int,
        bridgeEnabled: Bool,
        controllerConnected: Bool
    ) -> Bool {
        token == revision && bridgeEnabled && controllerConnected
    }
}
