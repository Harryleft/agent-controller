import XCTest
@testable import AgentControllerPlatform

final class CodexDictationTraversalPolicyTests: XCTestCase {
    func testBudgetCoversKnownDeepCodexWindowWithoutRelaxingUniqueness() {
        // Codex 26.715.31925 exposed descendants deeper than the former
        // 30-level cap, while the full window was about 2,800 nodes.
        XCTAssertGreaterThan(CodexDictationTraversalPolicy.maximumDepth, 30)
        XCTAssertGreaterThanOrEqual(CodexDictationTraversalPolicy.nodeLimit, 2_800)
        XCTAssertTrue(
            CodexDictationTraversalPolicy.accepts(
                traversalComplete: true,
                startControlCount: 1,
                stopControlCount: 0
            )
        )
    }

    func testRejectsIncompleteOrAmbiguousDiscovery() {
        XCTAssertFalse(
            CodexDictationTraversalPolicy.accepts(
                traversalComplete: false,
                startControlCount: 1,
                stopControlCount: 0
            )
        )
        XCTAssertFalse(
            CodexDictationTraversalPolicy.accepts(
                traversalComplete: true,
                startControlCount: 2,
                stopControlCount: 0
            )
        )
        XCTAssertFalse(
            CodexDictationTraversalPolicy.accepts(
                traversalComplete: true,
                startControlCount: 0,
                stopControlCount: 2
            )
        )
    }
}
