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
            ([.y], .openNewThread),
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

    func testLeftShoulderModifiedVerticalInputSelectsSidebarTasksOnEdges() {
        var engine = activeEngine()

        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder], leftStick: SIMD2(0.9, 0)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder], leftStick: SIMD2(0, 0.9)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 3),
            [.selectSidebarTask(.previous)]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder], leftStick: SIMD2(0, 0.9)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 4),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder], leftStick: SIMD2(0, 0)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 5),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder, .dpadDown]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 6),
            [.selectSidebarTask(.next)]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder, .dpadDown]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 7),
            []
        )
    }

    func testSidebarModifierMayFollowHeldDirectionAndReleaseDoesNotLeakNavigation() {
        var engine = activeEngine()

        XCTAssertEqual(
            engine.update(snapshot: snapshot(leftStick: SIMD2(0, -0.9)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 6),
            [.navigate(.down)]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder], leftStick: SIMD2(0, -0.9)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 7),
            [.selectSidebarTask(.next)]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder], leftStick: SIMD2(0, -0.9)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 8),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(leftStick: SIMD2(0, -0.9)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 9),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 10),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(leftStick: SIMD2(0, -0.9)), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 11),
            [.navigate(.down)]
        )
    }

    func testSidebarMoveWinsOverSimultaneousOpenPress() {
        var engine = activeEngine()

        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder, .a, .dpadDown]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 1),
            [.selectSidebarTask(.next)]
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 2),
            []
        )
        XCTAssertEqual(
            engine.update(snapshot: snapshot(buttons: [.leftShoulder, .a]), bridgeEnabled: true, onlyWhenCodexForeground: false, codexIsForeground: false, timestamp: 3),
            [.openSelected]
        )
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
            [.selectSidebarTask(.next)]
        )
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
        leftTrigger: Double = 0
    ) -> ControllerSnapshot {
        ControllerSnapshot(connected: true, buttons: buttons, leftStick: leftStick, leftTrigger: leftTrigger)
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
