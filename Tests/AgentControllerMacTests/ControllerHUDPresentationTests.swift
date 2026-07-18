import XCTest
@testable import AgentControllerMac

final class ControllerHUDPresentationTests: XCTestCase {
    func testVisibleOnlyWhenEveryRuntimeGateAllowsIt() {
        let visible = ControllerHUDPresentation.resolve(
            from: runtimeState(activeLayer: .leftShoulder)
        )
        XCTAssertTrue(visible.isVisible)

        [
            runtimeState(bridgeEnabled: false, activeLayer: .leftShoulder),
            runtimeState(codexForeground: false, activeLayer: .leftShoulder),
            runtimeState(controllerConnected: false, activeLayer: .leftShoulder),
            runtimeState(activeLayer: .base)
        ].forEach { state in
            let presentation = ControllerHUDPresentation.resolve(from: state)
            XCTAssertFalse(presentation.isVisible)
            XCTAssertTrue(presentation.layers.isEmpty)
            XCTAssertTrue(presentation.slots.isEmpty)
        }
    }

    func testPresentationAlwaysContainsFiveLayersAndSixPrivacySafeSlots() {
        let presentation = ControllerHUDPresentation.resolve(
            from: runtimeState(
                activeLayer: .leftShoulder,
                slotStatuses: [.confirmed, .unavailable]
            )
        )

        XCTAssertEqual(presentation.layers.count, 5)
        XCTAssertEqual(
            presentation.layers.first(where: { $0.kind == .leftShoulder })?.isActive,
            true
        )
        XCTAssertEqual(presentation.slots.count, 6)
        XCTAssertEqual(presentation.slots.map(\.position), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(
            presentation.slots.map(\.status),
            [.confirmed, .unavailable, .unknown, .unknown, .unknown, .unknown]
        )
    }

    func testChineseAndEnglishCopyIncludesAllStatusStates() {
        XCTAssertEqual(
            ControllerHUDLanguage.from(localeIdentifier: "zh-Hans_CN"),
            .chinese
        )
        XCTAssertEqual(
            ControllerHUDCopy.title(.chinese),
            "手柄 HUD"
        )
        XCTAssertEqual(
            ControllerHUDCopy.status(.confirmed, language: .chinese),
            "已确认"
        )
        XCTAssertEqual(
            ControllerHUDCopy.status(.unavailable, language: .english),
            "Unavailable"
        )
        XCTAssertEqual(
            ControllerHUDCopy.status(.unknown, language: .english),
            "Unknown"
        )
    }

    private func runtimeState(
        bridgeEnabled: Bool = true,
        codexForeground: Bool = true,
        controllerConnected: Bool = true,
        activeLayer: ControllerHUDLayer = .base,
        slotStatuses: [ControllerHUDStatus] = []
    ) -> ControllerHUDRuntimeState {
        ControllerHUDRuntimeState(
            bridgeEnabled: bridgeEnabled,
            codexForeground: codexForeground,
            controllerConnected: controllerConnected,
            activeLayer: activeLayer,
            slotStatuses: slotStatuses
        )
    }
}
