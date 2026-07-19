import XCTest
@testable import AgentControllerMac

final class ControllerHUDPresentationTests: XCTestCase {
    func testVisibleHUDContainsOnlyShippedLTAndXActions() {
        let presentation = ControllerHUDPresentation.resolve(from: runtimeState())

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.actions, [.dictation, .submit])
    }

    func testSafetyGatesHideHUD() {
        [
            runtimeState(bridgeEnabled: false),
            runtimeState(codexForeground: false),
            runtimeState(controllerConnected: false)
        ].forEach {
            XCTAssertEqual(ControllerHUDPresentation.resolve(from: $0), .hidden)
        }
    }

    func testCopyNamesOnlyCurrentActions() {
        XCTAssertEqual(
            ControllerHUDLanguage.from(localeIdentifier: "zh-Hans_CN"),
            .chinese
        )
        XCTAssertEqual(ControllerHUDCopy.title(.chinese), "手柄控制")
        XCTAssertEqual(
            ControllerHUDCopy.action(.dictation, language: .chinese),
            "按一下开始，再按一下结束"
        )
        XCTAssertEqual(
            ControllerHUDCopy.action(.submit, language: .chinese),
            "提交当前输入"
        )
        XCTAssertEqual(
            ControllerHUDCopy.action(.dictation, language: .english),
            "Press once to start, again to stop"
        )
    }

    private func runtimeState(
        bridgeEnabled: Bool = true,
        codexForeground: Bool = true,
        controllerConnected: Bool = true
    ) -> ControllerHUDRuntimeState {
        ControllerHUDRuntimeState(
            bridgeEnabled: bridgeEnabled,
            codexForeground: codexForeground,
            controllerConnected: controllerConnected
        )
    }
}
