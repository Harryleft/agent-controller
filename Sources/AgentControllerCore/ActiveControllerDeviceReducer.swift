import Foundation

/// Pure active-device ownership for GameController notifications.
///
/// A disconnect notification for a second controller must never tear down the
/// active controller session.  Conversely, an active controller disconnect is
/// a safety boundary even if GameController's controller list has not yet
/// settled by the time the notification arrives.
public enum ActiveControllerDeviceReduction<ID: Hashable & Sendable>: Equatable, Sendable {
    case unchanged
    case activate(ID)
    case activeDisconnected
    case nonActiveDisconnectIgnored
}

public struct ActiveControllerDeviceReducer<ID: Hashable & Sendable>: Sendable {
    public private(set) var activeDeviceID: ID?

    public init() {}

    /// Reconcile the active ownership with the current candidate list. This
    /// handles a missed disconnect notification without guessing a new device.
    public mutating func reconcile(
        availableDeviceIDs: [ID]
    ) -> ActiveControllerDeviceReduction<ID> {
        if let activeDeviceID {
            guard !availableDeviceIDs.contains(activeDeviceID) else {
                return .unchanged
            }
            self.activeDeviceID = nil
            return .activeDisconnected
        }

        guard let candidate = availableDeviceIDs.first else {
            return .unchanged
        }
        activeDeviceID = candidate
        return .activate(candidate)
    }

    /// Consume a concrete disconnect notification. Only the active device can
    /// transition the controller session to disconnected.
    public mutating func disconnectNotified(
        for deviceID: ID
    ) -> ActiveControllerDeviceReduction<ID> {
        guard activeDeviceID == deviceID else {
            return .nonActiveDisconnectIgnored
        }
        activeDeviceID = nil
        return .activeDisconnected
    }

    public mutating func reset() {
        activeDeviceID = nil
    }
}
