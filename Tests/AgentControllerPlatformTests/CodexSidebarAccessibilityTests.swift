import XCTest
@testable import AgentControllerPlatform
import AgentControllerCore

final class CodexSidebarAccessibilityTests: XCTestCase {
    func testCatalogPreservesAXOrderAndMovesWithoutOpening() throws {
        let tasks = try [task(1, "A"), task(2, "B"), task(3, "C")]
        let catalog = try CodexSidebarTaskCatalog(validating: tasks)

        XCTAssertEqual(catalog.tasks.map(\.threadID), tasks.map(\.threadID))
        XCTAssertEqual(
            catalog.destinationIndex(
                selectedThreadID: nil,
                currentThreadID: tasks[1].threadID,
                direction: .previous
            ),
            0
        )
        XCTAssertEqual(
            catalog.destinationIndex(
                selectedThreadID: tasks[0].threadID,
                currentThreadID: tasks[1].threadID,
                direction: .next
            ),
            1
        )
    }

    func testMovementClampsAtBoundariesAndStartsFromVisibleEnds() throws {
        let tasks = try [task(1, "A"), task(2, "B")]
        let catalog = try CodexSidebarTaskCatalog(validating: tasks)

        XCTAssertEqual(
            catalog.destinationIndex(
                selectedThreadID: tasks[0].threadID,
                currentThreadID: nil,
                direction: .previous
            ),
            0
        )
        XCTAssertEqual(
            catalog.destinationIndex(
                selectedThreadID: tasks[1].threadID,
                currentThreadID: nil,
                direction: .next
            ),
            1
        )
        XCTAssertEqual(
            catalog.destinationIndex(
                selectedThreadID: nil,
                currentThreadID: nil,
                direction: .previous
            ),
            1
        )
        XCTAssertEqual(
            catalog.destinationIndex(
                selectedThreadID: nil,
                currentThreadID: nil,
                direction: .next
            ),
            0
        )
    }

    func testRefreshKeepsSelectionByThreadIDNotOldIndex() throws {
        let a = try task(1, "A")
        let b = try task(2, "B")
        let c = try task(3, "C")
        let refreshed = try CodexSidebarTaskCatalog(validating: [c, a, b])

        XCTAssertEqual(
            refreshed.destinationIndex(
                selectedThreadID: b.threadID,
                currentThreadID: a.threadID,
                direction: .previous
            ),
            1
        )
    }

    func testDuplicateThreadIDOrTitleIdentityFailsClosed() throws {
        let a = try task(1, "A")
        XCTAssertThrowsError(
            try CodexSidebarTaskCatalog(validating: [a, a])
        ) { error in
            XCTAssertEqual(
                error as? CodexSidebarCatalogError,
                .duplicateThreadID
            )
        }

        XCTAssertThrowsError(
            try CodexSidebarTaskCatalog(validating: [
                try task(1, "same"),
                try task(2, "same")
            ])
        ) { error in
            XCTAssertEqual(
                error as? CodexSidebarCatalogError,
                .duplicateTitleIdentity
            )
        }
        XCTAssertNil(
            CodexSidebarTask(threadID: uuid(3), exactTitle: "  ")
        )
    }

    func testDiscoveryDropsEveryAmbiguousTitleWithoutReordering() throws {
        let tasks = try [
            task(1, "A"),
            task(2, "same"),
            task(3, "B"),
            task(4, "same"),
            task(5, "C")
        ]

        XCTAssertEqual(
            CodexSidebarTaskCatalog.unambiguousTasks(from: tasks)
                .map(\.threadID),
            [tasks[0], tasks[2], tasks[4]].map(\.threadID)
        )
    }

    func testOpenConfirmationRequiresResolvedThreadIdentity() throws {
        let target = try task(1, "Target")
        let catalog = try CodexSidebarTaskCatalog(validating: [target])

        XCTAssertTrue(
            catalog.confirmsOpen(
                taskAt: 0,
                currentThreadID: target.threadID
            )
        )
        XCTAssertFalse(
            catalog.confirmsOpen(
                taskAt: 0,
                currentThreadID: uuid(2)
            )
        )
        XCTAssertFalse(catalog.confirmsOpen(taskAt: 0, currentThreadID: nil))
    }

    func testDiagnosticIdentityDoesNotExposeThreadIDOrTitle() throws {
        let task = try task(1, "private task title")

        XCTAssertEqual(task.diagnosticIdentity.count, 12)
        XCTAssertFalse(task.diagnosticIdentity.contains("private"))
        XCTAssertFalse(
            task.diagnosticIdentity.contains(
                task.threadID.uuidString.lowercased()
            )
        )
    }

    func testToolbarIdentityDoesNotCollapseDuplicateAXElements() throws {
        let identity = try XCTUnwrap(
            CodexSidebarTitleIdentity(exactTitle: "Target")
        )

        XCTAssertEqual(
            CodexToolbarIdentityResolver.resolve([]),
            .none
        )
        XCTAssertEqual(
            CodexToolbarIdentityResolver.resolve([identity]),
            .unique(identity)
        )
        XCTAssertEqual(
            CodexToolbarIdentityResolver.resolve([identity, identity]),
            .ambiguous
        )
    }

    private func task(
        _ number: Int,
        _ title: String
    ) throws -> CodexSidebarTask {
        try XCTUnwrap(
            CodexSidebarTask(
                threadID: uuid(number),
                exactTitle: title
            )
        )
    }

    private func uuid(_ number: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                number
            )
        )!
    }
}
