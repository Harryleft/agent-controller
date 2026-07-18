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

    func testClosedRequestCatalogContainsExactlyTheDocumentedActions() {
        XCTAssertEqual(CodexActionRequest.allCases.count, 14)
        XCTAssertEqual(
            Set(CodexActionRequest.allCases.map { String(describing: $0) }).count,
            CodexActionRequest.allCases.count
        )
    }
}
