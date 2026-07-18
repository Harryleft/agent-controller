import XCTest
@testable import AgentControllerPlatform

final class LiveCodexDictationTests: XCTestCase {
    @MainActor
    func testCurrentCodexDictationRoundTrip() async throws {
        guard ProcessInfo.processInfo.environment[
            "RUN_LIVE_CODEX_DICTATION_TEST"
        ] == "1" else {
            throw XCTSkip("live Codex test is opt-in")
        }

        let automation = CodexMacAutomation()
        XCTAssertTrue(automation.isCodexForeground)
        let started = await automation.setDictation(recording: true)
        XCTAssertTrue(started.succeeded, "start: \(started.diagnostic)")
        try await Task.sleep(for: .milliseconds(250))
        let stopped = await automation.setDictation(recording: false)
        XCTAssertTrue(stopped.succeeded, "stop: \(stopped.diagnostic)")
    }
}
