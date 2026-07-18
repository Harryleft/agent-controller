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
}
