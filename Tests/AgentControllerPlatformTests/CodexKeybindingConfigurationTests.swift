import Foundation
import XCTest
@testable import AgentControllerPlatform

final class CodexKeybindingConfigurationTests: XCTestCase {
    func testInstallMergesFixedBindingsAndPreservesExistingValues() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keybindings.json")
        let original: [Any] = [
            ["command": "custom.command", "key": "F20"],
            ["metadata": ["keep": true]],
            ["nonBinding", 7]
        ]
        try write(original, to: file)

        let service = CodexKeybindingConfigurationService(fileURL: file)
        XCTAssertEqual(
            service.install().outcome,
            .updated(backupCreated: true, conflicts: [])
        )

        let merged = try read(file)
        XCTAssertEqual(Array(merged.prefix(3)).count, 3)
        XCTAssertTrue(contains(original[0], in: merged))
        XCTAssertTrue(contains(original[1], in: merged))
        XCTAssertTrue(contains(original[2], in: merged))
        for action in CodexSemanticAction.allCases {
            XCTAssertTrue(
                merged.contains { item in
                    let object = item as? [String: Any]
                    return object?["command"] as? String == action.command &&
                        object?["key"] as? String == action.key
                },
                "missing \(action)"
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.backupURL.path))
        XCTAssertEqual(try read(service.backupURL).count, original.count)
    }

    func testInstallIsIdempotentAndNeverOverwritesInitialBackup() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keybindings.json")
        let original: [Any] = [["command": "custom.command", "key": "F20"]]
        try write(original, to: file)

        let service = CodexKeybindingConfigurationService(fileURL: file)
        XCTAssertEqual(
            service.install().outcome,
            .updated(backupCreated: true, conflicts: [])
        )
        let backupBefore = try Data(contentsOf: service.backupURL)
        XCTAssertEqual(service.install().outcome, .unchanged(conflicts: []))
        XCTAssertEqual(try Data(contentsOf: service.backupURL), backupBefore)
    }

    func testKeyConflictFailsClosedWithoutBackupOrWrite() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keybindings.json")
        try write([["command": "user.command", "key": "F13"]], to: file)
        let before = try Data(contentsOf: file)

        let service = CodexKeybindingConfigurationService(fileURL: file)
        XCTAssertEqual(
            service.install().outcome,
            .updated(
                backupCreated: true,
                conflicts: [.keyAlreadyAssigned(action: .reasoningDown)]
            )
        )
        let updated = try read(file)
        XCTAssertTrue(updated.contains { item in
            (item as? [String: Any])?["command"] as? String == "user.command"
        })
        XCTAssertFalse(updated.contains { item in
            (item as? [String: Any])?["command"] as? String ==
                CodexSemanticAction.reasoningDown.command
        })
        for action in CodexSemanticAction.allCases where action != .reasoningDown {
            XCTAssertTrue(updated.contains { item in
                let binding = item as? [String: Any]
                return binding?["command"] as? String == action.command &&
                    binding?["key"] as? String == action.key
            })
        }
        XCTAssertNotEqual(try Data(contentsOf: file), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.backupURL.path))
    }

    func testCommandConflictAndDuplicateManagedBindingFailClosed() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keybindings.json")
        try write([
            ["command": CodexSemanticAction.reasoningDown.command, "key": "F19"],
            ["command": CodexSemanticAction.reasoningUp.command, "key": "F14"],
            ["command": CodexSemanticAction.reasoningUp.command, "key": "F14"]
        ], to: file)

        let service = CodexKeybindingConfigurationService(fileURL: file)
        XCTAssertEqual(
            service.install().outcome,
            .updated(
                backupCreated: true,
                conflicts: [
                    .commandAlreadyAssigned(action: .reasoningDown),
                    .duplicateManagedBinding(action: .reasoningUp)
                ]
            )
        )
    }

    func testInvalidJSONOrMalformedBindingNeverWrites() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keybindings.json")
        try Data("{not json".utf8).write(to: file)
        let invalidBefore = try Data(contentsOf: file)
        let service = CodexKeybindingConfigurationService(fileURL: file)
        XCTAssertEqual(service.install().outcome, .invalidJSON)
        XCTAssertEqual(try Data(contentsOf: file), invalidBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.backupURL.path))

        try write([["command": 3, "key": "F13"]], to: file)
        let malformedBefore = try Data(contentsOf: file)
        XCTAssertEqual(service.install().outcome, .invalidJSON)
        XCTAssertEqual(try Data(contentsOf: file), malformedBefore)
    }

    func testRestoreUsesUntouchedFirstBackupAndRejectsMissingBackup() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keybindings.json")
        try write([["command": "custom.command", "key": "F20"]], to: file)
        let service = CodexKeybindingConfigurationService(fileURL: file)
        XCTAssertEqual(
            service.install().outcome,
            .updated(backupCreated: true, conflicts: [])
        )
        let backup = try Data(contentsOf: service.backupURL)

        try write([["command": "changed.command", "key": "F21"]], to: file)
        XCTAssertEqual(service.restoreInitialBackup().outcome, .restored)
        XCTAssertEqual(try Data(contentsOf: file), backup)
        XCTAssertEqual(try Data(contentsOf: service.backupURL), backup)

        let missing = CodexKeybindingConfigurationService(
            fileURL: directory.appendingPathComponent("missing.json")
        )
        XCTAssertEqual(missing.restoreInitialBackup().outcome, .backupUnavailable)
    }

    func testSemanticCapabilitiesAreExplicitAboutEvidenceBoundary() {
        let capabilities = Dictionary(
            uniqueKeysWithValues: CodexSemanticCapabilities.current.map {
                ($0.surface, $0.evidence)
            }
        )
        XCTAssertEqual(capabilities.count, CodexSemanticSurface.allCases.count)
        XCTAssertEqual(capabilities[.approval], .unavailable)
        XCTAssertEqual(capabilities[.model], .configuredShortcutWithoutUIReceipt)
        XCTAssertEqual(capabilities[.composer], .exactAccessibilityState)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func write(_ object: [Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url)
    }

    private func read(_ url: URL) throws -> [Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
    }

    private func contains(_ expected: Any, in values: [Any]) -> Bool {
        values.contains { candidate in
            guard JSONSerialization.isValidJSONObject([expected]),
                  JSONSerialization.isValidJSONObject([candidate]),
                  let lhs = try? JSONSerialization.data(withJSONObject: [expected], options: [.sortedKeys]),
                  let rhs = try? JSONSerialization.data(withJSONObject: [candidate], options: [.sortedKeys]) else {
                return false
            }
            return lhs == rhs
        }
    }
}
