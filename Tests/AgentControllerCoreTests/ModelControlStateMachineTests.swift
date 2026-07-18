import XCTest
@testable import AgentControllerCore

final class ModelControlStateMachineTests: XCTestCase {
    func testSimpleModeMapsEveryDirectionWithoutCataloguingCapabilities() {
        let store = ModeStore(.simple)
        var machine = ModelControlStateMachine(modeStore: store)

        XCTAssertEqual(machine.update(.init(rightX: -1), timestamp: 0), [.adjustReasoningPower(.down)])
        XCTAssertEqual(machine.update(.neutral, timestamp: 0.1), [])
        XCTAssertEqual(machine.update(.init(rightX: 1), timestamp: 0.2), [.adjustReasoningPower(.up)])
        XCTAssertEqual(machine.update(.neutral, timestamp: 0.3), [])
        XCTAssertEqual(machine.update(.init(rightY: 1), timestamp: 0.4), [.selectSimpleSpeed(.standard)])
        XCTAssertEqual(machine.update(.neutral, timestamp: 0.5), [])
        XCTAssertEqual(machine.update(.init(rightY: -1), timestamp: 0.6), [.selectSimpleSpeed(.fast)])
    }

    func testAdvancedModeCyclesTargetsThenStepsTheSelectedTarget() {
        let store = ModeStore(.advanced)
        var machine = ModelControlStateMachine(modeStore: store)

        XCTAssertEqual(machine.advancedTarget, .model)
        XCTAssertEqual(machine.update(.init(rightX: 1), timestamp: 0), [.selectAdvancedTarget(.effort)])
        XCTAssertEqual(machine.update(.neutral, timestamp: 0.1), [])
        XCTAssertEqual(machine.update(.init(rightX: 1), timestamp: 0.2), [.selectAdvancedTarget(.speed)])
        XCTAssertEqual(machine.update(.neutral, timestamp: 0.3), [])
        XCTAssertEqual(machine.update(.init(rightY: 1), timestamp: 0.4), [.stepAdvancedTarget(.speed, .up)])
        XCTAssertEqual(machine.update(.neutral, timestamp: 0.5), [])
        XCTAssertEqual(machine.update(.init(rightX: -1), timestamp: 0.6), [.selectAdvancedTarget(.effort)])
        XCTAssertEqual(machine.update(.neutral, timestamp: 0.7), [])
        XCTAssertEqual(machine.update(.init(rightY: -1), timestamp: 0.8), [.stepAdvancedTarget(.effort, .down)])
    }

    func testModeUsesInjectedStoreAndNeverDependsOnAppModel() {
        let store = ModeStore(.simple)
        var machine = ModelControlStateMachine(modeStore: store)
        machine.setMode(.advanced)

        XCTAssertEqual(store.modelControlMode, .advanced)
        XCTAssertEqual(machine.update(.init(rightX: 1), timestamp: 0), [.selectAdvancedTarget(.effort)])
    }

    func testDirectionHasEdgeRepeatAndSmoothlyAcceleratesOverTwoSeconds() {
        let store = ModeStore(.simple)
        var machine = ModelControlStateMachine(modeStore: store)
        let right = ModelControlInput(rightX: 1)

        XCTAssertEqual(machine.update(right, timestamp: 0), [.adjustReasoningPower(.up)])
        XCTAssertEqual(machine.update(right, timestamp: 0.34), [])
        XCTAssertEqual(machine.update(right, timestamp: 0.35), [.adjustReasoningPower(.up)])
        // At 0.35 seconds the interval is still close to the slow initial
        // cadence (about 0.21 s); by two seconds it bottoms out at 0.07 s.
        XCTAssertEqual(machine.update(right, timestamp: 0.58), [.adjustReasoningPower(.up)])
        XCTAssertEqual(machine.update(right, timestamp: 0.59), [])
        XCTAssertEqual(machine.update(right, timestamp: 1.5), [.adjustReasoningPower(.up)])
        XCTAssertEqual(machine.update(right, timestamp: 1.7), [.adjustReasoningPower(.up)])
        XCTAssertEqual(machine.update(right, timestamp: 2.0), [.adjustReasoningPower(.up)])
        XCTAssertEqual(machine.update(right, timestamp: 2.071), [.adjustReasoningPower(.up)])
    }

    func testDirectionReleaseFlushesRepeatSoNextPressIsANewEdge() {
        let store = ModeStore(.simple)
        var machine = ModelControlStateMachine(modeStore: store)
        let right = ModelControlInput(rightX: 1)

        XCTAssertEqual(machine.update(right, timestamp: 0), [.adjustReasoningPower(.up)])
        XCTAssertEqual(machine.update(.neutral, timestamp: 0.1), [])
        XCTAssertEqual(machine.update(right, timestamp: 10), [.adjustReasoningPower(.up)])
        XCTAssertEqual(machine.update(right, timestamp: 10.1), [])
    }

    func testR3TapOpensCurrentModeMenuWhileHoldOnlyOpensSettings() {
        let store = ModeStore(.advanced)
        var machine = ModelControlStateMachine(modeStore: store)

        XCTAssertEqual(machine.update(.init(rightStickPressed: true), timestamp: 0), [])
        XCTAssertEqual(machine.update(.neutral, timestamp: 0.2), [.openModelMenu(.advanced)])

        XCTAssertEqual(machine.update(.init(rightStickPressed: true), timestamp: 1), [])
        XCTAssertEqual(machine.update(.init(rightStickPressed: true), timestamp: 1.49), [])
        XCTAssertEqual(machine.update(.init(rightStickPressed: true), timestamp: 1.5), [.openAgentControllerSettings])
        XCTAssertEqual(machine.update(.neutral, timestamp: 1.6), [])
    }

    func testDiagonalUsesDominantAxisAndChangingDirectionIsAnImmediateNewEdge() {
        let store = ModeStore(.simple)
        var machine = ModelControlStateMachine(modeStore: store)

        XCTAssertEqual(machine.update(.init(rightX: 0.9, rightY: 0.4), timestamp: 0), [.adjustReasoningPower(.up)])
        XCTAssertEqual(machine.update(.init(rightY: 0.9), timestamp: 0.1), [.selectSimpleSpeed(.standard)])
    }
}

private final class ModeStore: ModelControlModeStoring {
    var modelControlMode: ModelControlMode

    init(_ modelControlMode: ModelControlMode) {
        self.modelControlMode = modelControlMode
    }
}
