import XCTest
@testable import AgentControllerPlatform

final class CodexWakeConfirmationTests: XCTestCase {
    private let bundleID = "com.openai.codex"
    private let targetPID: Int32 = 404

    func testRequiresTwoFreshSamplesForTheSameCodexPID() {
        var tracker = CodexWakeConfirmationTracker()

        XCTAssertFalse(
            tracker.observe(
                frontmostBundleIdentifier: bundleID,
                frontmostProcessIdentifier: targetPID,
                expectedBundleIdentifier: bundleID,
                expectedProcessIdentifier: targetPID
            )
        )
        XCTAssertTrue(
            tracker.observe(
                frontmostBundleIdentifier: bundleID,
                frontmostProcessIdentifier: targetPID,
                expectedBundleIdentifier: bundleID,
                expectedProcessIdentifier: targetPID
            )
        )
    }

    func testBundleOrPIDDriftResetsConfirmation() {
        var tracker = CodexWakeConfirmationTracker()
        _ = tracker.observe(
            frontmostBundleIdentifier: bundleID,
            frontmostProcessIdentifier: targetPID,
            expectedBundleIdentifier: bundleID,
            expectedProcessIdentifier: targetPID
        )

        XCTAssertFalse(
            tracker.observe(
                frontmostBundleIdentifier: bundleID,
                frontmostProcessIdentifier: targetPID + 1,
                expectedBundleIdentifier: bundleID,
                expectedProcessIdentifier: targetPID
            )
        )
        XCTAssertFalse(
            tracker.observe(
                frontmostBundleIdentifier: bundleID,
                frontmostProcessIdentifier: targetPID,
                expectedBundleIdentifier: bundleID,
                expectedProcessIdentifier: targetPID
            )
        )
    }

    func testWakeRequestGateRejectsSupersededAndClosedGateResults() {
        var gate = CodexWakeRequestGate()
        let first = gate.begin()
        let second = gate.begin()

        XCTAssertFalse(
            gate.accepts(
                first,
                bridgeEnabled: true,
                controllerConnected: true
            )
        )
        XCTAssertTrue(
            gate.accepts(
                second,
                bridgeEnabled: true,
                controllerConnected: true
            )
        )
        XCTAssertFalse(
            gate.accepts(
                second,
                bridgeEnabled: false,
                controllerConnected: true
            )
        )

        gate.invalidate()
        XCTAssertFalse(
            gate.accepts(
                second,
                bridgeEnabled: true,
                controllerConnected: true
            )
        )
    }
}
