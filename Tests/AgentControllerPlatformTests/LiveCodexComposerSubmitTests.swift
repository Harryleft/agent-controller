import XCTest
@testable import AgentControllerPlatform

final class LiveCodexComposerSubmitTests: XCTestCase {
    /// This test intentionally submits the current composer. It is opt-in so
    /// regular tests never inspect or operate the user's live Codex surface.
    @MainActor
    func testCurrentCodexComposerClearsAfterFixedSubmit() async throws {
        guard ProcessInfo.processInfo.environment[
            "RUN_LIVE_CODEX_COMPOSER_SUBMIT_TEST"
        ] == "1" else {
            throw XCTSkip("live Codex composer submit test is opt-in")
        }

        let automation = CodexMacAutomation()
        let isForeground = automation.isCodexForeground
        XCTAssertTrue(isForeground)
        let result = await automation.submitComposer()
        XCTAssertEqual(result, .composerClearedConfirmed)
    }
}
