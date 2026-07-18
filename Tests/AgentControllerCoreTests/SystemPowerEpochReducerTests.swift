import XCTest
@testable import AgentControllerCore

final class SystemPowerEpochReducerTests: XCTestCase {
    func testWakeRejectsOldGenerationAndRetainedControllerCacheUntilFreshDelivery() {
        var reducer = SystemPowerEpochReducer()
        XCTAssertEqual(reducer.generation, 0)
        XCTAssertEqual(reducer.gate, .accepting)

        reducer.willSleep()
        XCTAssertEqual(reducer.gate, .sleeping)
        XCTAssertFalse(reducer.acceptGameControllerDelivery(generation: 0))

        let generation = reducer.didWake()
        XCTAssertEqual(generation, 1)
        XCTAssertEqual(reducer.gate, .awaitingCurrentGenerationDelivery)
        XCTAssertEqual(
            reducer.admission(for: .retainedControllerCache),
            .cacheOnly
        )
        XCTAssertFalse(reducer.acceptGameControllerDelivery(generation: 0))
        XCTAssertEqual(reducer.gate, .awaitingCurrentGenerationDelivery)

        XCTAssertTrue(reducer.acceptGameControllerDelivery(generation: generation))
        XCTAssertEqual(reducer.gate, .accepting)
    }

    func testLifecycleAttachSeedsNeutralGateAtLaunchAndAfterReconnect() {
        var reducer = SystemPowerEpochReducer()
        XCTAssertEqual(
            reducer.admission(for: .lifecycleAttach),
            .forwardToNeutralGate
        )

        var engine = ControllerMappingEngine()
        let neutral = ControllerSnapshot(connected: true)
        _ = engine.update(
            snapshot: neutral,
            bridgeEnabled: true,
            onlyWhenCodexForeground: false,
            codexIsForeground: false,
            timestamp: 0
        )
        XCTAssertEqual(engine.phase, .waitingForNeutral)
        _ = engine.update(
            snapshot: neutral,
            bridgeEnabled: true,
            onlyWhenCodexForeground: false,
            codexIsForeground: false,
            timestamp: 0.1
        )
        XCTAssertEqual(engine.phase, .active)

        reducer.willSleep()
        _ = reducer.didWake()
        XCTAssertEqual(
            reducer.admission(for: .retainedControllerCache),
            .cacheOnly
        )
        XCTAssertEqual(
            reducer.admission(for: .lifecycleAttach),
            .forwardToNeutralGate,
            "An explicit reconnect is a trusted new device boundary."
        )
    }

    func testOrdinaryIdleDoesNotExpireTheCurrentGeneration() {
        var reducer = SystemPowerEpochReducer()
        let generation = reducer.generation

        // The reducer intentionally has no timer or idle transition. A quiet
        // controller remains valid until a real sleep boundary occurs.
        XCTAssertTrue(reducer.acceptGameControllerDelivery(generation: generation))
        XCTAssertTrue(reducer.acceptGameControllerDelivery(generation: generation))
        XCTAssertEqual(reducer.generation, generation)
        XCTAssertEqual(reducer.gate, .accepting)
    }
}
