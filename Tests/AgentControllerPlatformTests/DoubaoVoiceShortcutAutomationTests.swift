import XCTest
@testable import AgentControllerPlatform

final class DoubaoVoiceShortcutAutomationTests: XCTestCase {
    func testOnlyAppliedStatesAreReportedAsApplied() {
        [
            DoubaoVoiceShortcutAutomationResult.held,
            .released,
            .alreadyHeld,
            .alreadyReleased
        ].forEach {
            XCTAssertTrue($0.applied)
        }

        [
            DoubaoVoiceShortcutAutomationResult.accessibilityDenied,
            .postEventDenied,
            .codexNotForeground,
            .eventCreationFailed
        ].forEach {
            XCTAssertFalse($0.applied)
        }
    }
}
