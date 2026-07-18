import AppKit
import Foundation

/// Injectable boundary observer. Tests provide a manual observer instead of
/// asking macOS to sleep; production listens to NSWorkspace notifications.
@MainActor
public protocol SystemPowerObserver: AnyObject {
    func start(
        onWillSleep: @escaping @MainActor @Sendable () -> Void,
        onDidWake: @escaping @MainActor @Sendable () -> Void
    )
    func stop()
}

@MainActor
public final class NSWorkspaceSystemPowerObserver: SystemPowerObserver {
    private var tokens: [NSObjectProtocol] = []

    public init() {}

    public func start(
        onWillSleep: @escaping @MainActor @Sendable () -> Void,
        onDidWake: @escaping @MainActor @Sendable () -> Void
    ) {
        guard tokens.isEmpty else { return }

        let center = NSWorkspace.shared.notificationCenter
        tokens = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { onWillSleep() }
            },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { onDidWake() }
            }
        ]
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.forEach(center.removeObserver)
        tokens.removeAll()
    }
}
