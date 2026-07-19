import XCTest
@testable import AgentControllerPlatform

final class LiveDoubaoVoiceShortcutTests: XCTestCase {
    @MainActor
    func testCurrentDoubaoVoiceShortcutRoundTrip() throws {
        guard ProcessInfo.processInfo.environment[
            "RUN_LIVE_DOUBAO_VOICE_TEST"
        ] == "1" else {
            throw XCTSkip("live Doubao voice shortcut test is opt-in")
        }

        let automation = CodexMacAutomation()
        XCTAssertTrue(automation.isCodexForeground)
        let started = automation.setDoubaoVoiceShortcut(recording: true)
        XCTAssertTrue(started.applied, "start: \(started.diagnostic)")
        let stopped = automation.setDoubaoVoiceShortcut(recording: false)
        XCTAssertTrue(stopped.applied, "stop: \(stopped.diagnostic)")
    }
}
