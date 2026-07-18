import XCTest
@testable import AgentControllerCore

final class ControllerMappingEngineTests: XCTestCase {
    func testBridgeOffSwallowsEvenWakeAndRequiresNeutralAfterReenable() {
        var engine = ControllerMappingEngine()
        let menu = snapshot(buttons: [.menu])

        XCTAssertEqual(
            engine.update(snapshot: menu, bridgeEnabled: false, onlyWhenCodexForeground: true, codexIsForeground: false, timestamp: 0),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: menu, bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: true, timestamp: 1),
            []
        )
        XCTAssertEqual(engine.phase, .waitingForNeutral)
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: true, timestamp: 2), [])
        XCTAssertEqual(
            engine.update(snapshot: menu, bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: true, timestamp: 3),
            [.wakeCodex]
        )
    }

    func testBridgeReenableOnSameConnectionRequiresNeutralThenResumes() {
        var engine = activeEngine()
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.a]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2), [.openSelected])
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: false, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 3), [])
        XCTAssertEqual(engine.phase, .locked)
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.x]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 4), [])
        XCTAssertEqual(engine.phase, .waitingForNeutral)
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 5), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.x]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 6), [.submit])
    }

    func testMenuMayWakeWhileCodexIsNotForeground() {
        var engine = ControllerMappingEngine()
        _ = engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: true, timestamp: 0)
        _ = engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: true, timestamp: 1)
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.menu]), bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: false, timestamp: 2),
            [.wakeCodex]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.x]), bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: false, timestamp: 3),
            []
        )
    }

    func testConnectionAndForegroundRecoveryBothRequireNeutral() {
        var engine = ControllerMappingEngine()
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.a]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 0), [])
        XCTAssertEqual(engine.phase, .waitingForNeutral)
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.a]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.a]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 3), [.openSelected])

        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: false, timestamp: 4), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.x]), bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: false, timestamp: 5), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.x]), bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: true, timestamp: 6), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: true, timestamp: 7), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.x]), bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: true, timestamp: 8), [.submit])
    }

    func testFaceAndNavigationMappingUsesEdges() {
        var engine = activeEngine()
        let cases: [(Set<ControllerButton>, ControllerAction)] = [
            ([.a], .openSelected),
            ([.x], .submit),
            ([.rightThumbstick], .openModelPicker),
            ([.dpadUp], .navigate(.up)),
            ([.dpadRight], .navigate(.right)),
            ([.dpadDown], .navigate(.down)),
            ([.dpadLeft], .navigate(.left))
        ]

        var time: TimeInterval = 10
        for (buttons, action) in cases {
            XCTAssertEqual(engine.update(snapshot: snapshot(buttons: buttons), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: time), [action])
            time += 1
            XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: time), [])
            time += 1
        }

        XCTAssertEqual(engine.update(snapshot: snapshot(leftStick: SIMD2(0.9, 0)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: time), [.navigate(.right)])
        XCTAssertEqual(engine.update(snapshot: snapshot(leftStick: SIMD2(0.9, 0)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: time + 1), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: time + 2), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(leftStick: SIMD2(0, 0.9)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: time + 3), [.navigate(.up)])
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: time + 4), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(leftStick: SIMD2(0.15, 0)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: time + 5, deadZone: 0.12), [.navigate(.right)])
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: time + 6), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(leftStick: SIMD2(0.15, 0)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: time + 7, deadZone: 0.40), [])
    }

    func testLeftShoulderTapAndHeldAgentLayerAreDistinct() {
        var engine = activeEngine()

        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1.1),
            [.openPreviousTask]
        )

        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2.2),
            []
        )
        XCTAssertEqual(engine.inputLayer, .agent)
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder, .dpadUp]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2.3),
            [.selectAgentSlot(.one)]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder, .dpadUp]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2.4),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2.5),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2.6),
            []
        )
    }

    func testRightShoulderCommandLayerAndApproveRequireHold() {
        var engine = activeEngine()

        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.rightShoulder]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.rightShoulder]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1.2),
            []
        )
        XCTAssertEqual(engine.inputLayer, .command)
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.rightShoulder, .y]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1.3),
            [.command(.toggleFast)]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.rightShoulder]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1.4),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.rightShoulder, .a]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.rightShoulder, .a]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2.5),
            [.command(.approve)]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.rightShoulder, .a]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 3),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 3.1),
            []
        )
    }

    func testCommandPushToTalkStopsWhenViewOrShoulderIsReleased() {
        var engine = activeEngine()

        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.rightShoulder]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.rightShoulder]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1.2),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.rightShoulder, .options]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1.3),
            [.command(.startPushToTalk)]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.rightShoulder]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1.4),
            [.command(.stopPushToTalk)]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.rightShoulder, .options]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1.5),
            [.command(.startPushToTalk)]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.options]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1.6),
            [.command(.stopPushToTalk)]
        )
    }

    func testRunningLayerHasThresholdAndStopRequiresHold() {
        var engine = activeEngine()

        XCTAssertEqual(
            engine.update(snapshot: snapshot(rightTrigger: 0.54), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(rightTrigger: 0.55), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2),
            []
        )
        XCTAssertEqual(engine.inputLayer, .running)
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.x], rightTrigger: 0.60), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 3),
            [.running(.steer)]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(rightTrigger: 0.60), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 4),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.b], rightTrigger: 0.60), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 5),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.b], rightTrigger: 0.60), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 8),
            [.running(.stop)]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(rightTrigger: 0.35), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 9),
            []
        )
    }

    func testActionPanelCapturesBaseAndRequiresClearConfirmation() {
        var engine = activeEngine()
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.y]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1), [.openActionPanel])
        XCTAssertEqual(engine.inputLayer, .actionPanel)
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.dpadUp]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 3), [.actionPanel(.newTask)])
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 4), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.a]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 5), [.actionPanel(.requestClearComposerConfirmation)])
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 6), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.a]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 7), [.actionPanel(.clearComposer)])
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 8), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.y]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 9), [.closeActionPanel])
    }

    func testLeftStickVerticalIsSuppressedWhileLeftTriggerOwnsInput() {
        var engine = activeEngine()

        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder], leftStick: SIMD2(0, 0.9), leftTrigger: 0.50), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1),
            [.startDictation]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder], leftStick: SIMD2(0, -0.9), leftTrigger: 0.50), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder], leftStick: SIMD2(0, -0.9), leftTrigger: 0), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 3),
            [.stopDictation]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder], leftStick: SIMD2(0, -0.9)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 4),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 5),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder], leftStick: SIMD2(0, -0.9)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 6),
            []
        )
    }

    func testIdleAndReconnectWithHeldButtonNeverCreateSyntheticPress() {
        var engine = activeEngine()
        let heldA = snapshot(buttons: [.a])

        XCTAssertEqual(engine.update(snapshot: heldA, bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1), [.openSelected])
        XCTAssertEqual(engine.update(snapshot: heldA, bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 600), [])
        XCTAssertEqual(engine.update(snapshot: .disconnected, bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 601), [])
        XCTAssertEqual(engine.phase, .locked)

        XCTAssertEqual(engine.update(snapshot: heldA, bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 602), [])
        XCTAssertEqual(engine.phase, .waitingForNeutral)
        XCTAssertEqual(engine.update(snapshot: heldA, bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 603), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 604), [])
        XCTAssertEqual(engine.phase, .active)
        XCTAssertEqual(engine.update(snapshot: heldA, bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 605), [.openSelected])
    }

    func testBShortPressCancelsAndThreeSecondHoldStopsOnce() {
        var engine = activeEngine()
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.b]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1.5), [.cancel])

        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.b]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.b]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 5), [.stopTask])
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.b]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 6), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 6.1), [])
    }

    func testLeftTriggerUsesHysteresisForPushToTalk() {
        var engine = activeEngine()
        XCTAssertEqual(engine.update(snapshot: snapshot(leftTrigger: 0.34), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(leftTrigger: 0.35), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2), [.startDictation])
        XCTAssertEqual(engine.update(snapshot: snapshot(leftTrigger: 0.25), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 3), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(leftTrigger: 0.20), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 4), [.stopDictation])
    }

    func testDictationSuppressesBaseActionsUntilTriggerRelease() {
        var engine = activeEngine()
        XCTAssertEqual(engine.update(snapshot: snapshot(leftTrigger: 0.50), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1), [.startDictation])
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.x], leftTrigger: 0.50), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2), [])
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.x], leftTrigger: 0), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 3), [.stopDictation])
    }

    func testDisconnectAndBridgeShutdownDrainActiveDictationOnce() {
        var engine = activeEngine()
        XCTAssertEqual(engine.update(snapshot: snapshot(leftTrigger: 0.40), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: true, timestamp: 1), [.startDictation])
        XCTAssertEqual(engine.update(snapshot: .disconnected, bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: true, timestamp: 2), [.stopDictation])
        XCTAssertEqual(engine.update(snapshot: .disconnected, bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: true, timestamp: 3), [])

        engine = activeEngine()
        XCTAssertEqual(engine.update(snapshot: snapshot(leftTrigger: 0.40), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: true, timestamp: 4), [.startDictation])
        XCTAssertEqual(engine.update(snapshot: snapshot(leftTrigger: 0.40), bridgeEnabled: false, onlyWhenCodexForeground: false, codexIsForeground: true, timestamp: 5), [.stopDictation])
        XCTAssertEqual(engine.update(snapshot: snapshot(leftTrigger: 0.40), bridgeEnabled: false, onlyWhenCodexForeground: false, codexIsForeground: true, timestamp: 6), [])
    }

    func testForegroundLossDrainsDictationAndPreservesMenuWake() {
        var engine = activeEngine(foreground: true)
        XCTAssertEqual(engine.update(snapshot: snapshot(leftTrigger: 0.50), bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: true, timestamp: 2), [.startDictation])
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.menu], leftTrigger: 0.50), bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: false, timestamp: 3),
            [.stopDictation, .wakeCodex]
        )
        XCTAssertEqual(engine.update(snapshot: snapshot(buttons: [.menu], leftTrigger: 0.50), bridgeEnabled: true, onlyWhenCodexForeground: true, codexIsForeground: false, timestamp: 4), [])
    }

    private func activeEngine(foreground: Bool = false) -> ControllerMappingEngine {
        var engine = ControllerMappingEngine()
        _ = engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: foreground, codexIsForeground: foreground, timestamp: 0)
        _ = engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: foreground, codexIsForeground: foreground, timestamp: 1)
        return engine
    }

    private func snapshot(
        buttons: Set<ControllerButton> = [],
        leftStick: SIMD2<Double> = .zero,
        leftTrigger: Double = 0,
        rightTrigger: Double = 0
    ) -> ControllerSnapshot {
        ControllerSnapshot(
            connected: true,
            buttons: buttons,
            leftStick: leftStick,
            leftTrigger: leftTrigger,
            rightTrigger: rightTrigger
        )
    }
}

final class ControllerDeviceDescriptorTests: XCTestCase {
    func testXboxClassificationUsesProfileVendorAndCategory() {
        XCTAssertEqual(ControllerDeviceDescriptor(profileIsXbox: true).category, .xbox)
        XCTAssertEqual(ControllerDeviceDescriptor(vendorName: "Microsoft Corporation", profileIsXbox: false).category, .xbox)
        XCTAssertEqual(ControllerDeviceDescriptor(productCategory: "Xbox Gamepad", profileIsXbox: false).classification, .xbox)
    }

    func testStandardAndUnsupportedClassification() {
        XCTAssertEqual(ControllerDeviceDescriptor(vendorName: "Sony", productCategory: "DualSense", profileIsXbox: false).category, .standard)
        XCTAssertEqual(ControllerDeviceDescriptor(vendorName: "Unknown", profileIsXbox: false, hasExtendedGamepad: false).category, .unsupported)
    }
}

final class ControllerSnapshotTests: XCTestCase {
    func testNeutralIncludesButtonsSticksAndTriggers() {
        XCTAssertTrue(ControllerSnapshot(connected: true).isNeutral())
        XCTAssertFalse(ControllerSnapshot(connected: true, buttons: [.a]).isNeutral())
        XCTAssertFalse(ControllerSnapshot(connected: true, leftStick: SIMD2(0.13, 0)).isNeutral())
        XCTAssertFalse(ControllerSnapshot(connected: true, leftTrigger: 0.13).isNeutral())
    }
}
