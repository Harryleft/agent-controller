import Foundation
import XCTest
@testable import AgentControllerPlatform

final class CodexSessionIndexTests: XCTestCase {
    func testUniqueExactTitleResolvesValidatedUUID() throws {
        let targetID = uuid(1)
        let file = try temporaryFile(
            record(id: targetID, title: "Target") + "\n"
        )
        defer {
            try? FileManager.default.removeItem(
                at: file.deletingLastPathComponent()
            )
        }

        let index = try CodexSessionIndex(contentsOf: file)
        XCTAssertEqual(
            index.uniqueThreadID(matching: try identity("Target")),
            targetID
        )
        XCTAssertNil(
            index.uniqueThreadID(matching: try identity("target"))
        )
    }

    func testDuplicateTitleAcrossDistinctThreadsIsAmbiguous() throws {
        let file = try temporaryFile([
            record(id: uuid(1), title: "Same"),
            record(id: uuid(2), title: "Same")
        ].joined(separator: "\n"))
        defer {
            try? FileManager.default.removeItem(
                at: file.deletingLastPathComponent()
            )
        }

        let index = try CodexSessionIndex(contentsOf: file)
        XCTAssertNil(index.uniqueThreadID(matching: try identity("Same")))
    }

    func testDuplicateThreadIDKeepsLatestValidRecord() throws {
        let targetID = uuid(1)
        let file = try temporaryFile([
            record(
                id: targetID,
                title: "Old",
                updatedAt: "2026-07-18T10:00:00Z"
            ),
            record(
                id: targetID,
                title: "New",
                updatedAt: "2026-07-18T11:00:00Z"
            )
        ].joined(separator: "\n"))
        defer {
            try? FileManager.default.removeItem(
                at: file.deletingLastPathComponent()
            )
        }

        let index = try CodexSessionIndex(contentsOf: file)
        XCTAssertNil(index.uniqueThreadID(matching: try identity("Old")))
        XCTAssertEqual(
            index.uniqueThreadID(matching: try identity("New")),
            targetID
        )
    }

    func testMalformedBadUUIDBadDateAndEmptyTitleAreIgnored() throws {
        let targetID = uuid(4)
        let file = try temporaryFile([
            "{partially-written",
            record(idString: "not-a-uuid", title: "Bad UUID"),
            record(
                id: uuid(2),
                title: "Bad date",
                updatedAt: "not-a-date"
            ),
            record(id: uuid(3), title: "  "),
            record(id: targetID, title: "Valid")
        ].joined(separator: "\n"))
        defer {
            try? FileManager.default.removeItem(
                at: file.deletingLastPathComponent()
            )
        }

        let index = try CodexSessionIndex(contentsOf: file)
        XCTAssertEqual(
            index.uniqueThreadID(matching: try identity("Valid")),
            targetID
        )
    }

    func testNoValidRecordsFailsClosed() throws {
        let file = try temporaryFile("{invalid")
        defer {
            try? FileManager.default.removeItem(
                at: file.deletingLastPathComponent()
            )
        }

        XCTAssertThrowsError(try CodexSessionIndex(contentsOf: file)) {
            XCTAssertEqual(
                $0 as? CodexSessionIndexError,
                .noValidRecords
            )
        }
    }

    func testOversizedIndexFailsBeforeParsing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session_index.jsonl")
        try Data(
            repeating: 0x20,
            count: CodexSessionIndex.maximumFileBytes + 1
        ).write(to: file)

        XCTAssertThrowsError(try CodexSessionIndex(contentsOf: file)) {
            XCTAssertEqual($0 as? CodexSessionIndexError, .fileTooLarge)
        }
    }

    func testTitleIdentityRejectsMultilineInsteadOfCollapsingFirstLine() throws {
        XCTAssertEqual(
            try identity("  Exact title  "),
            try identity("Exact title")
        )
        XCTAssertNil(
            CodexSidebarTitleIdentity(
                exactTitle: "Exact title\nother private continuation"
            )
        )
        XCTAssertNotEqual(
            try identity("Exact title"),
            try identity("exact title")
        )
    }

    func testDeepLinkCanOnlyContainValidatedUUID() throws {
        let targetID = uuid(42)
        let url = try XCTUnwrap(CodexThreadDeepLink.url(for: targetID))

        XCTAssertEqual(
            url.absoluteString,
            "codex://threads/00000000-0000-0000-0000-000000000042"
        )
        XCTAssertEqual(url.scheme, "codex")
        XCTAssertEqual(url.host, "threads")
        XCTAssertTrue(
            CodexThreadDeepLink.acceptsHandler(
                bundleIdentifier: "com.openai.codex"
            )
        )
        XCTAssertFalse(
            CodexThreadDeepLink.acceptsHandler(
                bundleIdentifier: "com.example.hijacker"
            )
        )
        XCTAssertFalse(
            CodexThreadDeepLink.acceptsHandler(bundleIdentifier: nil)
        )
    }

    private func temporaryFile(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("session_index.jsonl")
        try Data(contents.utf8).write(to: file)
        return file
    }

    private func record(
        id: UUID,
        title: String,
        updatedAt: String = "2026-07-18T10:00:00Z"
    ) -> String {
        record(
            idString: id.uuidString.lowercased(),
            title: title,
            updatedAt: updatedAt
        )
    }

    private func record(
        idString: String,
        title: String,
        updatedAt: String = "2026-07-18T10:00:00Z"
    ) -> String {
        let object: [String: String] = [
            "id": idString,
            "thread_name": title,
            "updated_at": updatedAt
        ]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }

    private func identity(
        _ title: String
    ) throws -> CodexSidebarTitleIdentity {
        try XCTUnwrap(CodexSidebarTitleIdentity(exactTitle: title))
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
