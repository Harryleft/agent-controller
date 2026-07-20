import XCTest
@testable import AgentControllerCore

final class ControllerCoreTests: XCTestCase {
    func testRequiresNeutralAfterConnection() {
        var engine = ControllerMappingEngine()
        XCTAssertEqual(
            engine.update(
                snapshot: snapshot(leftTrigger: 1),
                bridgeEnabled: true,
                codexIsForeground: true
            ),
            []
        )
        XCTAssertEqual(engine.phase, .waitingForNeutral)
        XCTAssertEqual(
            engine.update(
                snapshot: snapshot(),
                bridgeEnabled: true,
                codexIsForeground: true
            ),
            []
        )
        XCTAssertEqual(engine.phase, .active)
    }

    func testLTStartsAndSecondPressStopsVoice() {
        var engine = activeEngine()
        XCTAssertEqual(actions(&engine, leftTrigger: 0.5), [.startVoice])
        XCTAssertEqual(actions(&engine, leftTrigger: 0), [])
        XCTAssertEqual(actions(&engine, leftTrigger: 0.5), [.stopVoice])
    }

    func testXSubmitsWhenVoiceIsIdle() {
        var engine = activeEngine()
        XCTAssertEqual(actions(&engine, buttons: [.x]), [.submit])
        XCTAssertEqual(actions(&engine), [])
    }

    func testXStopsVoiceThenSubmitsWhenVoiceIsActive() {
        var engine = activeEngine()
        XCTAssertEqual(actions(&engine, leftTrigger: 0.5), [.startVoice])
        XCTAssertEqual(actions(&engine, leftTrigger: 0), [])
        XCTAssertEqual(actions(&engine, buttons: [.x]), [.stopVoiceAndSubmit])
        XCTAssertEqual(actions(&engine), [])
        XCTAssertEqual(actions(&engine, buttons: [.x]), [.submit])
    }

    func testDisconnectAndForegroundLossStopVoiceOnce() {
        var engine = activeEngine()
        XCTAssertEqual(actions(&engine, leftTrigger: 0.5), [.startVoice])
        XCTAssertEqual(
            engine.update(
                snapshot: .disconnected,
                bridgeEnabled: true,
                codexIsForeground: true
            ),
            [.stopVoice]
        )
        XCTAssertEqual(
            engine.update(
                snapshot: .disconnected,
                bridgeEnabled: true,
                codexIsForeground: true
            ),
            []
        )
    }

    private func activeEngine() -> ControllerMappingEngine {
        var engine = ControllerMappingEngine()
        _ = engine.update(snapshot: snapshot(), bridgeEnabled: true, codexIsForeground: true)
        return engine
    }

    private func actions(
        _ engine: inout ControllerMappingEngine,
        buttons: Set<ControllerButton> = [],
        leftTrigger: Double = 0
    ) -> [ControllerAction] {
        engine.update(
            snapshot: snapshot(buttons: buttons, leftTrigger: leftTrigger),
            bridgeEnabled: true,
            codexIsForeground: true
        )
    }

    private func snapshot(
        buttons: Set<ControllerButton> = [],
        leftTrigger: Double = 0
    ) -> ControllerSnapshot {
        ControllerSnapshot(connected: true, buttons: buttons, leftTrigger: leftTrigger)
    }
}
