import XCTest
@testable import AgentControllerCore
@testable import AgentControllerPlatform

final class CodexBaseActionPolicyTests: XCTestCase {
    func testSubmitIsUnavailableWithoutAFreshUIReceipt() {
        XCTAssertFalse(CodexBaseActionPolicy.isAvailable(.submit))
        XCTAssertEqual(
            CodexBaseActionPolicy.unavailableDiagnostic(for: .submit),
            "Unavailable · 缺少提交后的精确 UI 回执"
        )
    }

    func testUnrelatedBaseActionsDoNotInheritSubmitUnavailability() {
        XCTAssertTrue(CodexBaseActionPolicy.isAvailable(.wakeCodex))
        XCTAssertNil(
            CodexBaseActionPolicy.unavailableDiagnostic(for: .wakeCodex)
        )
    }
}
