import XCTest
@testable import AgentControllerPlatform

@MainActor
final class GameControllerSystemPowerTests: XCTestCase {
    func testInjectedObserverPublishesSleepAndWakeEpochBoundaries() {
        let observer = ManualSystemPowerObserver()
        let service = GameControllerService(systemPowerObserver: observer)
        var boundaries: [SystemPowerBoundary] = []
        service.onSystemPowerBoundary = { boundaries.append($0) }
        service.start()
        defer { service.stop() }

        observer.fireWillSleep()
        observer.fireDidWake()

        XCTAssertEqual(
            boundaries,
            [.willSleep(generation: 0), .didWake(generation: 1)]
        )
        XCTAssertEqual(service.inputGeneration, 1)
    }
}

@MainActor
private final class ManualSystemPowerObserver: SystemPowerObserver {
    private var onWillSleep: (@MainActor @Sendable () -> Void)?
    private var onDidWake: (@MainActor @Sendable () -> Void)?

    func start(
        onWillSleep: @escaping @MainActor @Sendable () -> Void,
        onDidWake: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onWillSleep = onWillSleep
        self.onDidWake = onDidWake
    }

    func stop() {
        onWillSleep = nil
        onDidWake = nil
    }

    func fireWillSleep() {
        onWillSleep?()
    }

    func fireDidWake() {
        onDidWake?()
    }
}
