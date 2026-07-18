import XCTest
@testable import AgentControllerCore
@testable import AgentControllerPlatform

final class CodexBaseActionPolicyTests: XCTestCase {
    func testSubmitIsReservedForItsDedicatedExactComposerAdapter() {
        XCTAssertTrue(CodexBaseActionPolicy.isAvailable(.submit))
        XCTAssertNil(CodexBaseActionPolicy.unavailableDiagnostic(for: .submit))
    }

    func testUnrelatedBaseActionsDoNotInheritSubmitUnavailability() {
        XCTAssertTrue(CodexBaseActionPolicy.isAvailable(.wakeCodex))
        XCTAssertNil(
            CodexBaseActionPolicy.unavailableDiagnostic(for: .wakeCodex)
        )
    }

    func testOpenRequiresAConfirmedTaskCandidate() {
        XCTAssertFalse(CodexBaseActionPolicy.isAvailable(.openSelected))
        XCTAssertEqual(
            CodexBaseActionPolicy.unavailableDiagnostic(for: .openSelected),
            "Unavailable · 没有已确认的任务候选"
        )
    }

    func testCancelAndStopAreUnavailableWithoutExactPostActionState() {
        XCTAssertFalse(CodexBaseActionPolicy.isAvailable(.cancel))
        XCTAssertFalse(CodexBaseActionPolicy.isAvailable(.stopTask))
        XCTAssertEqual(
            CodexBaseActionPolicy.unavailableDiagnostic(for: .cancel),
            "Unavailable · 缺少取消后的精确 UI 回执"
        )
        XCTAssertEqual(
            CodexBaseActionPolicy.unavailableDiagnostic(for: .stopTask),
            "Unavailable · 缺少停止后的精确 UI 回执"
        )
    }

    func testLegacyShortcutFallbacksStayDisabled() {
        let actions: [ControllerAction] = [
            .openNewThread,
            .navigate(.up),
            .openModelPicker
        ]
        for action in actions {
            XCTAssertFalse(CodexBaseActionPolicy.isAvailable(action))
            XCTAssertEqual(
                CodexBaseActionPolicy.unavailableDiagnostic(for: action),
                "Unavailable · 遗留快捷键路径已停用"
            )
        }
    }
}
