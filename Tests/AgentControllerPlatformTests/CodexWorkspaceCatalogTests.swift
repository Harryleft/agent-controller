import Foundation
import XCTest
@testable import AgentControllerPlatform

final class CodexWorkspaceCatalogTests: XCTestCase {
    func testAgentSlotsPutPinnedBeforeRecentAndCapAtSix() {
        let records = (1...8).map { number in
            record(number, minute: number)
        }
        let catalog = CodexWorkspaceCatalog(
            sessionRecords: records,
            metadata: metadata(pinned: [uuid(2), uuid(7)])
        )

        XCTAssertEqual(
            catalog.agentSlots.map(\.threadID),
            [uuid(7), uuid(2), uuid(8), uuid(6), uuid(5), uuid(4)]
        )
    }

    func testDuplicateUUIDKeepsNewestRecordBeforeSlotAssignment() {
        let catalog = CodexWorkspaceCatalog(
            sessionRecords: [
                record(1, minute: 1),
                record(1, minute: 9),
                record(2, minute: 8)
            ],
            metadata: .unavailable
        )

        XCTAssertEqual(catalog.agentSlots.map(\.threadID), [uuid(1), uuid(2)])
        XCTAssertEqual(catalog.agentSlots.first?.updatedAt, date(9))
    }

    func testRootsExposeOnlyProvenProjectAndPinMetadata() {
        let catalog = CodexWorkspaceCatalog(
            sessionRecords: [record(1, minute: 4), record(2, minute: 8)],
            metadata: CodexWorkspaceMetadata(
                projects: .available([
                    "local-a": .init(id: "local-a", name: "Alpha")
                ]),
                pinnedThreadIDs: .available([uuid(1)]),
                pinnedProjectIDs: .available(["local-a"]),
                assignments: .available([uuid(2): "local-a"]),
                projectlessThreadIDs: .available([uuid(1)])
            )
        )

        XCTAssertEqual(catalog.roots[0].contents, .availableTasks([task(1, 4)]))
        XCTAssertEqual(
            catalog.roots[1].contents,
            .available([.init(
                project: .init(id: "local-a", name: "Alpha"),
                tasks: [task(2, 8)]
            )])
        )
        XCTAssertEqual(catalog.roots[2].contents, catalog.roots[1].contents)
        XCTAssertEqual(catalog.roots[3].contents, .availableTasks([task(1, 4)]))
    }

    func testMissingFieldsAreUnavailableRatherThanGuessed() {
        let catalog = CodexWorkspaceCatalog(
            sessionRecords: [record(1, minute: 1)],
            metadata: .unavailable
        )

        XCTAssertEqual(catalog.roots.map(\.contents), [.unavailable, .unavailable, .unavailable, .unavailable])
        XCTAssertEqual(catalog.agentSlots, [task(1, 1)])
        XCTAssertEqual(catalog.recentTasks, [task(1, 1)])
    }

    func testNavigatorMovesOnlyAppOwnedCatalogSelectionAndEntersProject() {
        let catalog = CodexWorkspaceCatalog(
            sessionRecords: [record(1, minute: 1), record(2, minute: 2)],
            metadata: CodexWorkspaceMetadata(
                projects: .available(["alpha": .init(id: "alpha", name: "Alpha")]),
                pinnedThreadIDs: .available([]),
                pinnedProjectIDs: .available([]),
                assignments: .available([uuid(2): "alpha"]),
                projectlessThreadIDs: .available([uuid(1)])
            )
        )
        var navigator = CodexWorkspaceCatalogNavigator()
        navigator.replaceCatalog(catalog)

        XCTAssertEqual(navigator.moveSelection(.next), .unavailable)
        XCTAssertEqual(navigator.cycleRoot(), .confirmed(.root(.pinnedProjects)))
        XCTAssertEqual(navigator.moveSelection(.next), .unavailable)
        XCTAssertEqual(navigator.cycleRoot(), .confirmed(.root(.projects)))
        XCTAssertEqual(navigator.moveSelection(.next), .confirmed(.project(id: "alpha")))
        XCTAssertEqual(navigator.enterProject(), .confirmed(.project(id: "alpha")))
        XCTAssertEqual(navigator.moveSelection(.next), .confirmed(.task(uuid(2))))
        XCTAssertEqual(navigator.selectedTaskID, uuid(2))
        XCTAssertEqual(navigator.leaveProject(), .confirmed(.project(id: "alpha")))
        XCTAssertNil(navigator.selectedTaskID)
    }

    func testNavigatorUsesRecentTasksAndSlotsWithoutTitles() {
        let catalog = CodexWorkspaceCatalog(
            sessionRecords: [record(1, minute: 1), record(2, minute: 2)],
            metadata: .unavailable
        )
        var navigator = CodexWorkspaceCatalogNavigator()
        navigator.replaceCatalog(catalog)

        XCTAssertEqual(navigator.moveRecentTask(.next), .confirmed(.task(uuid(2))))
        XCTAssertEqual(navigator.moveRecentTask(.previous), .confirmed(.task(uuid(1))))
        XCTAssertEqual(navigator.selectAgentSlot(.one), .confirmed(.task(uuid(2))))
        XCTAssertEqual(navigator.selectAgentSlot(.three), .unavailable)
        navigator.clearSelection()
        XCTAssertNil(navigator.selectedTaskID)
        navigator.invalidate()
        XCTAssertEqual(navigator.moveRecentTask(.next), .unavailable)
    }

    func testMetadataReaderIgnoresPromptReplyAndPaths() throws {
        let file = try temporaryFile("""
        {
          "local-projects": {
            "local-a": {
              "id": "local-a",
              "name": "Alpha",
              "rootPaths": ["/private/workspace"]
            }
          },
          "pinned-thread-ids": ["\(uuid(1).uuidString)"],
          "thread-project-assignments": {
            "\(uuid(1).uuidString)": {"projectId": "local-a", "path": "/private/workspace"}
          },
          "projectless-thread-ids": [],
          "prompt": "do not retain this",
          "response": {"body": "or this"}
        }
        """)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let metadata = try CodexWorkspaceMetadata(contentsOf: file)
        let catalog = CodexWorkspaceCatalog(
            sessionRecords: [record(1, minute: 1)],
            metadata: metadata
        )

        XCTAssertEqual(catalog.agentSlots, [task(1, 1)])
        XCTAssertEqual(catalog.roots[1].contents, .unavailable)
        XCTAssertEqual(
            catalog.roots[2].contents,
            .available([.init(
                project: .init(id: "local-a", name: "Alpha"),
                tasks: [task(1, 1)]
            )])
        )
    }

    private func metadata(pinned: [UUID]) -> CodexWorkspaceMetadata {
        CodexWorkspaceMetadata(
            projects: .available([:]),
            pinnedThreadIDs: .available(pinned),
            pinnedProjectIDs: .unavailable,
            assignments: .available([:]),
            projectlessThreadIDs: .available([])
        )
    }

    private func record(_ number: Int, minute: Int) -> CodexSessionIndexRecord {
        .init(threadID: uuid(number), updatedAt: date(minute))
    }

    private func task(_ number: Int, _ minute: Int) -> CodexWorkspaceTask {
        .init(threadID: uuid(number), updatedAt: date(minute))
    }

    private func date(_ minute: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(minute * 60))
    }

    private func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    private func temporaryFile(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("state.json")
        try Data(contents.utf8).write(to: file)
        return file
    }
}
