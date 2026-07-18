import XCTest
@testable import AgentControllerPlatform

final class CodexDictationAccessibilityTests: XCTestCase {
    func testClassifiesExactStartLabelsAcrossSupportedLocales() {
        XCTAssertEqual(CodexDictationControlKind.classify(accessibilityLabel: "听写"), .start)
        XCTAssertEqual(CodexDictationControlKind.classify(accessibilityLabel: "聽寫"), .start)
        XCTAssertEqual(CodexDictationControlKind.classify(accessibilityLabel: "Dictate"), .start)
    }

    func testClassifiesExactStopLabelsAcrossSupportedLocales() {
        XCTAssertEqual(CodexDictationControlKind.classify(accessibilityLabel: "停止听写"), .stop)
        XCTAssertEqual(CodexDictationControlKind.classify(accessibilityLabel: "停止聽寫"), .stop)
        XCTAssertEqual(CodexDictationControlKind.classify(accessibilityLabel: "停止口述"), .stop)
        XCTAssertEqual(CodexDictationControlKind.classify(accessibilityLabel: "Stop dictation"), .stop)
        XCTAssertEqual(CodexDictationControlKind.classify(accessibilityLabel: "Stop recording"), .stop)
        XCTAssertEqual(CodexDictationControlKind.classify(accessibilityLabel: "Stop listening"), .stop)
        XCTAssertEqual(CodexDictationControlKind.classify(accessibilityLabel: "停止录音"), .stop)
    }

    func testRejectsSimilarAndArbitraryLabels() {
        ["开始听写", "听写一下", "Dictation", "Stop Dictation", "停止听写 ", "\n听写", "语音输入", ""].forEach {
            XCTAssertNil(
                CodexDictationControlKind.classify(
                    accessibilityLabel: $0
                ),
                "unexpected match for \($0)"
            )
        }
    }

    func testOnlyConfirmedResultsReportSuccess() {
        XCTAssertTrue(CodexDictationAutomationResult.confirmed.succeeded)
        XCTAssertTrue(CodexDictationAutomationResult.alreadySatisfied.succeeded)

        [
            CodexDictationAutomationResult.accessibilityDenied,
            .postEventDenied,
            .codexNotForeground,
            .controlUnavailable,
            .eventCreationFailed,
            .stateNotConfirmed
        ].forEach {
            XCTAssertFalse($0.succeeded, "unexpected success for \($0)")
        }
    }
}
