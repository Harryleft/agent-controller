import Foundation

/// Tracks whether the platform has recently delivered a controller snapshot.
///
/// The periodic AppModel timer must only *query* this value.  Updating it from
/// that timer would make a cached snapshot look live after a wireless
/// controller silently slept without a disconnect notification.
public struct ControllerObservationContinuityTracker: Sendable {
    public let timeout: TimeInterval
    private var lastConnectedObservationAt: TimeInterval?

    public init(
        timeout: TimeInterval = ControllerMappingEngine.inputContinuityTimeout
    ) {
        self.timeout = max(0, timeout.isFinite ? timeout : 0)
    }

    /// Call only from a real platform snapshot delivery.
    public mutating func observe(
        _ snapshot: ControllerSnapshot,
        at timestamp: TimeInterval
    ) {
        guard snapshot.isConnected, timestamp.isFinite else {
            lastConnectedObservationAt = nil
            return
        }
        lastConnectedObservationAt = timestamp
    }

    /// A disconnect clears continuity immediately. Reconnection becomes live
    /// only after a fresh connected snapshot has been observed.
    public mutating func disconnect() {
        lastConnectedObservationAt = nil
    }

    /// Read-only query for periodic hold/foreground processing.
    public func isContinuous(at timestamp: TimeInterval) -> Bool {
        guard timestamp.isFinite,
              let lastConnectedObservationAt,
              timestamp >= lastConnectedObservationAt else {
            return false
        }
        return timestamp - lastConnectedObservationAt <= timeout
    }
}
