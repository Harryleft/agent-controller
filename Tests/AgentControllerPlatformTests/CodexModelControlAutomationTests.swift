import XCTest
@testable import AgentControllerCore
@testable import AgentControllerPlatform

final class CodexModelControlAutomationTests: XCTestCase {
    func testSimpleActionsUseOnlyTheirFixedSemanticBindings() {
        XCTAssertEqual(
            CodexModelControlDispatchPlan.resolve(
                .adjustReasoningPower(.down)),
            .shortcut(.semantic(.reasoningDown))
        )
        XCTAssertEqual(
            CodexModelControlDispatchPlan.resolve(
                .adjustReasoningPower(.up)),
            .shortcut(.semantic(.reasoningUp))
        )
        XCTAssertEqual(
            CodexModelControlDispatchPlan.resolve(
                .selectSimpleSpeed(.fast)),
            .shortcut(.semantic(.toggleFastMode))
        )
        XCTAssertEqual(
            CodexModelControlDispatchPlan.resolve(.openModelMenu(.simple)),
            .shortcut(.semantic(.openModelPicker))
        )
    }

    func testUnknownSpeedAndAllAdvancedControlsFailClosed() {
        XCTAssertEqual(
            CodexModelControlDispatchPlan.resolve(
                .selectSimpleSpeed(.standard)),
            .unavailable
        )
        XCTAssertEqual(
            CodexModelControlDispatchPlan.resolve(
                .openModelMenu(.advanced)),
            .unavailable
        )
        XCTAssertEqual(
            CodexModelControlDispatchPlan.resolve(
                .selectAdvancedTarget(.effort)),
            .unavailable
        )
        XCTAssertEqual(
            CodexModelControlDispatchPlan.resolve(
                .stepAdvancedTarget(.speed, .down)),
            .unavailable
        )
    }

    func testPostedShortcutDiagnosticNeverClaimsUIConfirmation() {
        XCTAssertEqual(
            CodexModelControlAutomationResult
                .shortcutPostedWithoutUIConfirmation.diagnostic,
            "Unavailable · 已定向投递，未确认 Codex UI"
        )
    }
}
