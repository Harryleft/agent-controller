import Foundation

/// A lifecycle-only gate around GameController input after system sleep.
///
/// GameController can retain controller objects and queued handlers across a
/// macOS sleep/wake boundary.  Neither an inventory read nor a handler that
/// was installed before wake is evidence that the controller has delivered a
/// fresh sample in the new system epoch.  This reducer has no platform I/O or
/// clock, so the boundary can be tested without putting a Mac to sleep.
public struct SystemPowerEpochReducer: Sendable {
    public enum Gate: Equatable, Sendable {
        case accepting
        case sleeping
        case awaitingCurrentGenerationDelivery
    }

    /// A controller-list read is trustworthy only when it follows a concrete
    /// attach/reconnect lifecycle boundary.  The same controller retained
    /// across didWake has no equivalent delivery evidence.
    public enum SnapshotEvidence: Equatable, Sendable {
        case lifecycleAttach
        case retainedControllerCache
    }

    public enum SnapshotAdmission: Equatable, Sendable {
        case forwardToNeutralGate
        case cacheOnly
    }

    public private(set) var generation: UInt64 = 0
    public private(set) var gate: Gate = .accepting

    public init() {}

    public mutating func willSleep() {
        gate = .sleeping
    }

    /// Starts a new epoch. A fresh GameController value-change delivery from
    /// this generation is required before the session may re-enter its
    /// separate neutral-input gate.
    @discardableResult
    public mutating func didWake() -> UInt64 {
        generation &+= 1
        gate = .awaitingCurrentGenerationDelivery
        return generation
    }

    /// Returns true exactly once the platform has a real callback associated
    /// with the current post-wake handler. Cached inventory snapshots and
    /// callbacks captured by an earlier handler are deliberately rejected.
    @discardableResult
    public mutating func acceptGameControllerDelivery(
        generation deliveryGeneration: UInt64
    ) -> Bool {
        guard deliveryGeneration == generation else { return false }
        switch gate {
        case .accepting:
            return true
        case .sleeping:
            return false
        case .awaitingCurrentGenerationDelivery:
            gate = .accepting
            return true
        }
    }

    /// A normal app-start/reconnect attach is a new lifecycle boundary and
    /// may seed the existing neutral gate synchronously. A controller object
    /// retained through wake may not: it must wait for its new handler's real
    /// value-change callback instead.
    public func admission(
        for evidence: SnapshotEvidence
    ) -> SnapshotAdmission {
        switch (gate, evidence) {
        case (.sleeping, _), (_, .retainedControllerCache):
            .cacheOnly
        case (_, .lifecycleAttach):
            .forwardToNeutralGate
        }
    }
}
