import XCTest
@testable import AgentControllerPlatform

final class CodexActionSemanticsTests: XCTestCase {
    private let semantics = CodexActionSemantics()

    func testForkUsesOnlyTheFixedConfirmedSemanticKeybinding() {
        for request in [
            CodexActionRequest.command(.fork),
            CodexActionRequest.running(.fork)
        ] {
            XCTAssertEqual(
                semantics.capability(for: request),
                .available(
                    route: .fixedKeybinding(.forkThread),
                    requiredEvidence: .confirmedFixedKeybinding(.forkThread)
                )
            )
            XCTAssertEqual(
                semantics.resolve(
                    request,
                    evidence: .confirmedFixedKeybinding(.forkThread)
                ),
                .authorized(
                    route: .fixedKeybinding(.forkThread),
                    evidence: .confirmedFixedKeybinding(.forkThread)
                )
            )
        }
    }

    func testForkFailsClosedWhenEvidenceIsAbsentOrForAnotherSemanticAction() {
        XCTAssertEqual(
            semantics.resolve(.command(.fork), evidence: nil),
            .unavailable(.evidenceNotConfirmed)
        )
        XCTAssertEqual(
            semantics.resolve(
                .running(.fork),
                evidence: .confirmedFixedKeybinding(.toggleFastMode)
            ),
            .unavailable(.evidenceNotConfirmed)
        )
    }

    func testApprovalAndRunningControlsRemainUnavailableEvenWithEvidence() {
        let unavailable: [CodexActionRequest] = [
            .command(.approve), .command(.decline), .command(.dispatch),
            .running(.steer), .running(.queue), .running(.stop)
        ]

        for request in unavailable {
            XCTAssertEqual(
                semantics.capability(for: request),
                .unavailable(.noVerifiedRoute),
                "\(request) unexpectedly has a route"
            )
            XCTAssertEqual(
                semantics.resolve(
                    request,
                    evidence: .confirmedFixedKeybinding(.forkThread)
                ),
                .unavailable(.noVerifiedRoute),
                "\(request) must not degrade to a shortcut"
            )
        }
    }

    func testEveryYActionRemainsUnavailableWithoutAnExactVerifiedContract() {
        for action in CodexActionPanelAction.allCases {
            let request = CodexActionRequest.actionPanel(action)
            XCTAssertEqual(
                semantics.resolve(
                    request,
                    evidence: .confirmedFixedKeybinding(.forkThread)
                ),
                .unavailable(.noVerifiedRoute),
                "\(action) must not fall back to an arbitrary shortcut"
            )
        }
    }

    func testYActionsRejectInjectedShortcutEvidence() {
        // This represents a fake adapter claiming that it posted a shortcut.
        // Posting is not an AX state transition and must never authorize a Y
        // panel action.
        let fakeShortcutEvidence = CodexActionEvidence
            .confirmedFixedKeybinding(.forkThread)

        for action in CodexActionPanelAction.allCases {
            XCTAssertEqual(
                semantics.resolve(
                    .actionPanel(action),
                    evidence: fakeShortcutEvidence
                ),
                .unavailable(.noVerifiedRoute)
            )
        }
    }

    func testFakeAXComposerSnapshotsConfirmOnlyNonemptyToEmpty() {
        let verifier = CodexComposerClearVerifier()
        let nonEmpty = FakeComposerAX(
            matchingControls: 1,
            isEmpty: false
        ).presence
        let empty = FakeComposerAX(
            matchingControls: 1,
            isEmpty: true
        ).presence

        XCTAssertTrue(
            verifier.confirmsCleared(before: nonEmpty, after: empty)
        )
        XCTAssertFalse(
            verifier.confirmsCleared(before: empty, after: empty)
        )
        XCTAssertFalse(
            verifier.confirmsCleared(
                before: nonEmpty,
                after: FakeComposerAX(
                    matchingControls: 2,
                    isEmpty: true
                ).presence
            )
        )
        XCTAssertFalse(
            verifier.confirmsCleared(
                before: .unavailable,
                after: empty
            )
        )
    }

    func testClosedRequestCatalogContainsExactlyTheDocumentedActions() {
        XCTAssertEqual(CodexActionRequest.allCases.count, 15)
        XCTAssertEqual(
            Set(CodexActionRequest.allCases.map { String(describing: $0) }).count,
            CodexActionRequest.allCases.count
        )
    }

    func testFixedKeybindingDeliveryIsNeverDescribedAsCodexSuccess() {
        XCTAssertEqual(
            CodexFixedKeybindingAutomationResult.unavailable.diagnostic,
            "Unavailable"
        )
        XCTAssertEqual(
            CodexFixedKeybindingAutomationResult
                .shortcutPostedWithoutUIConfirmation.diagnostic,
            "Unavailable · 已定向投递，未确认 Codex UI"
        )
    }
}

private struct FakeComposerAX {
    let matchingControls: Int
    let isEmpty: Bool?

    /// The fake contains only presence metadata: unit tests cannot accidentally
    /// normalize, compare, or persist a composer body.
    var presence: CodexComposerPresence {
        guard matchingControls == 1, let isEmpty else { return .ambiguous }
        return isEmpty ? .empty : .nonEmpty
    }
}
