import XCTest
@testable import AgentControllerPlatform
import AgentControllerCore

final class LiveCodexSidebarTests: XCTestCase {
    @MainActor
    func testCurrentCodexSidebarFocusRoundTrip() async throws {
        guard ProcessInfo.processInfo.environment[
            "RUN_LIVE_CODEX_SIDEBAR_TEST"
        ] == "1" else {
            throw XCTSkip("live Codex sidebar test is opt-in")
        }

        let automation = CodexMacAutomation()
        XCTAssertTrue(automation.isCodexForeground)
        let next = await automation.selectSidebarTask(direction: .next)
        XCTAssertTrue(next.succeeded, "next: \(next.diagnostic)")
        let previous = await automation.selectSidebarTask(direction: .previous)
        XCTAssertTrue(previous.succeeded, "previous: \(previous.diagnostic)")
        automation.clearSidebarTaskSelection()
    }

    @MainActor
    func testCurrentCodexSidebarOpenAndConfirm() async throws {
        guard ProcessInfo.processInfo.environment[
            "RUN_LIVE_CODEX_SIDEBAR_OPEN_TEST"
        ] == "1" else {
            throw XCTSkip("live Codex sidebar open test is opt-in")
        }

        let automation = CodexMacAutomation()
        XCTAssertTrue(automation.isCodexForeground)
        let selection = await automation.selectSidebarTask(direction: .next)
        XCTAssertTrue(
            selection.succeeded,
            "selection: \(selection.diagnostic)"
        )
        let first = try selectionDetails(selection)
        XCTAssertGreaterThanOrEqual(
            first.total,
            2,
            "live open test requires two uniquely resolved visible tasks"
        )
        let opened = await automation.openSelectedSidebarTask()
        XCTAssertTrue(opened.succeeded, "open: \(opened.diagnostic)")

        let secondDirection: SidebarTaskDirection =
            first.position == 1 ? .next : .previous
        let secondSelection = await automation.selectSidebarTask(
            direction: secondDirection
        )
        XCTAssertTrue(
            secondSelection.succeeded,
            "second selection: \(secondSelection.diagnostic)"
        )
        let second = try selectionDetails(secondSelection)
        XCTAssertNotEqual(
            first.identityHash,
            second.identityHash,
            "the second open must target a different visible task"
        )
        let secondOpened = await automation.openSelectedSidebarTask()
        XCTAssertTrue(
            secondOpened.succeeded,
            "second open: \(secondOpened.diagnostic)"
        )
    }

    private func selectionDetails(
        _ result: CodexSidebarAutomationResult
    ) throws -> (position: Int, total: Int, identityHash: String) {
        guard case let .selectionConfirmed(position, total, hash) = result else {
            XCTFail("sidebar selection was not confirmed")
            throw LiveSidebarTestError.selectionNotConfirmed
        }
        return (position, total, hash)
    }
}

private enum LiveSidebarTestError: Error {
    case selectionNotConfirmed
}
