import Foundation

/// Fixed semantic commands that may be provisioned into Codex's local
/// `keybindings.json`. The service never sends arbitrary commands or accepts
/// user-provided key strings.
public enum CodexSemanticAction: String, CaseIterable, Equatable, Sendable {
    case reasoningDown
    case reasoningUp
    case openModelPicker
    case toggleFastMode
    case forkThread

    public var command: String {
        switch self {
        case .reasoningDown: "composer.decreaseReasoningEffort"
        case .reasoningUp: "composer.increaseReasoningEffort"
        case .openModelPicker: "composer.openModelPicker"
        case .toggleFastMode: "composer.toggleFastMode"
        case .forkThread: "forkThread"
        }
    }

    public var key: String {
        switch self {
        case .reasoningDown: "F13"
        case .reasoningUp: "F14"
        case .openModelPicker: "F15"
        case .toggleFastMode: "F16"
        case .forkThread: "F17"
        }
    }
}

/// The evidence boundary for the six semantic surfaces requested by the
/// controller. This is descriptive only; callers must still invoke a
/// concrete, verified adapter before reporting success.
public enum CodexSemanticEvidence: String, Equatable, Sendable {
    case exactAccessibilityState
    case exactAccessibilityFocus
    case targetedShortcutWithoutUIReceipt
    case configuredShortcutWithoutUIReceipt
    case unavailable
}

public enum CodexSemanticSurface: String, CaseIterable, Equatable, Sendable {
    case workspace
    case sidebar
    case composer
    case approval
    case turn
    case model
}

public struct CodexSemanticCapability: Equatable, Sendable {
    public let surface: CodexSemanticSurface
    public let evidence: CodexSemanticEvidence

    public init(surface: CodexSemanticSurface, evidence: CodexSemanticEvidence) {
        self.surface = surface
        self.evidence = evidence
    }
}

/// A deliberately conservative snapshot of what the macOS adapter can prove.
/// In particular, approval and turn control have no safe AX contract yet.
public enum CodexSemanticCapabilities {
    public static let current: [CodexSemanticCapability] = [
        .init(surface: .workspace, evidence: .exactAccessibilityFocus),
        .init(surface: .sidebar, evidence: .exactAccessibilityFocus),
        .init(surface: .composer, evidence: .exactAccessibilityState),
        .init(surface: .approval, evidence: .unavailable),
        .init(surface: .turn, evidence: .targetedShortcutWithoutUIReceipt),
        .init(surface: .model, evidence: .configuredShortcutWithoutUIReceipt)
    ]
}

public enum CodexKeybindingConflict: Equatable, Sendable {
    case keyAlreadyAssigned(action: CodexSemanticAction)
    case commandAlreadyAssigned(action: CodexSemanticAction)
    case duplicateManagedBinding(action: CodexSemanticAction)
}

public enum CodexKeybindingConfigurationOutcome: Equatable, Sendable {
    case updated(backupCreated: Bool)
    case unchanged
    case restored
    case conflict([CodexKeybindingConflict])
    case invalidJSON
    case backupUnavailable
    case ioFailure
}

public struct CodexKeybindingConfigurationResult: Equatable, Sendable {
    public let outcome: CodexKeybindingConfigurationOutcome

    public init(outcome: CodexKeybindingConfigurationOutcome) {
        self.outcome = outcome
    }
}

/// Safe, explicit provisioning for five fixed Codex semantic bindings.
///
/// The first successful update preserves the original file as a never-
/// overwritten backup. All subsequent updates and restores replace only via a
/// temporary file created in the destination directory.
public struct CodexKeybindingConfigurationService: Sendable {
    public static let filename = "keybindings.json"
    public static let backupSuffix = ".agent-controller.backup"

    public let fileURL: URL

    public init(fileURL: URL = Self.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    public var backupURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(
            fileURL.lastPathComponent + Self.backupSuffix,
            isDirectory: false
        )
    }

    @discardableResult
    public func install() -> CodexKeybindingConfigurationResult {
        do {
            let existing = try readArray(at: fileURL)
            let conflicts = conflicts(in: existing)
            guard conflicts.isEmpty else {
                return .init(outcome: .conflict(conflicts))
            }

            let missing = CodexSemanticAction.allCases.filter { action in
                !containsExactBinding(action, in: existing)
            }
            guard !missing.isEmpty else {
                return .init(outcome: .unchanged)
            }

            var merged = existing
            for action in missing {
                merged.append([
                    "command": action.command,
                    "key": action.key
                ])
            }

            let data = try jsonData(for: merged)
            let backupCreated = try createInitialBackupIfNeeded()
            try replaceAtomically(data: data, at: fileURL)
            return .init(outcome: .updated(backupCreated: backupCreated))
        } catch let error as KeybindingReadError {
            switch error {
            case .invalidJSON:
                return .init(outcome: .invalidJSON)
            case .ioFailure:
                return .init(outcome: .ioFailure)
            }
        } catch {
            return .init(outcome: .ioFailure)
        }
    }

    @discardableResult
    public func restoreInitialBackup() -> CodexKeybindingConfigurationResult {
        do {
            guard FileManager.default.fileExists(atPath: backupURL.path) else {
                return .init(outcome: .backupUnavailable)
            }
            let data = try Data(contentsOf: backupURL)
            _ = try parseArray(data: data)
            try replaceAtomically(data: data, at: fileURL)
            return .init(outcome: .restored)
        } catch let error as KeybindingReadError {
            switch error {
            case .invalidJSON:
                return .init(outcome: .invalidJSON)
            case .ioFailure:
                return .init(outcome: .ioFailure)
            }
        } catch {
            return .init(outcome: .ioFailure)
        }
    }

    private enum KeybindingReadError: Error {
        case invalidJSON
        case ioFailure
    }

    private enum ParsedBinding {
        case unrelated
        case binding(command: String, key: String?)
        case malformed
    }

    private func readArray(at url: URL) throws -> [Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        do {
            return try parseArray(data: Data(contentsOf: url))
        } catch let error as KeybindingReadError {
            throw error
        } catch {
            throw KeybindingReadError.ioFailure
        }
    }

    private func parseArray(data: Data) throws -> [Any] {
        do {
            let root = try JSONSerialization.jsonObject(with: data)
            guard let array = root as? [Any] else {
                throw KeybindingReadError.invalidJSON
            }
            guard !array.contains(where: { value in
                if case .malformed = parsedBinding(value) {
                    return true
                }
                return false
            }) else {
                throw KeybindingReadError.invalidJSON
            }
            return array
        } catch let error as KeybindingReadError {
            throw error
        } catch {
            throw KeybindingReadError.invalidJSON
        }
    }

    private func parsedBinding(_ value: Any) -> ParsedBinding {
        guard let object = value as? [String: Any] else { return .unrelated }
        let hasCommand = object.keys.contains("command")
        let hasKey = object.keys.contains("key")
        guard hasCommand || hasKey else { return .unrelated }
        guard hasCommand,
              hasKey,
              let rawCommand = object["command"] as? String else {
            return .malformed
        }
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return .malformed }

        if object["key"] is NSNull {
            return .binding(command: command, key: nil)
        }
        guard let rawKey = object["key"] as? String else {
            return .malformed
        }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .malformed }
        return .binding(command: command, key: key)
    }

    private func conflicts(in entries: [Any]) -> [CodexKeybindingConflict] {
        let bindings = entries.compactMap { value -> (String, String?)? in
            guard case let .binding(command, key) = parsedBinding(value) else {
                return nil
            }
            return (command, key)
        }

        var result: [CodexKeybindingConflict] = []
        for action in CodexSemanticAction.allCases {
            let commandEntries = bindings.filter { $0.0 == action.command }
            let exactEntries = commandEntries.filter {
                $0.1?.caseInsensitiveCompare(action.key) == .orderedSame
            }
            if commandEntries.count > 1 || exactEntries.count > 1 {
                result.append(.duplicateManagedBinding(action: action))
                continue
            }
            if let existing = commandEntries.first,
               existing.1?.caseInsensitiveCompare(action.key) != .orderedSame {
                result.append(.commandAlreadyAssigned(action: action))
                continue
            }
            if bindings.contains(where: {
                $0.0 != action.command &&
                $0.1?.caseInsensitiveCompare(action.key) == .orderedSame
            }) {
                result.append(.keyAlreadyAssigned(action: action))
            }
        }
        return result
    }

    private func containsExactBinding(
        _ action: CodexSemanticAction,
        in entries: [Any]
    ) -> Bool {
        entries.contains { value in
            guard case let .binding(command, key) = parsedBinding(value) else {
                return false
            }
            return command == action.command &&
                key?.caseInsensitiveCompare(action.key) == .orderedSame
        }
    }

    private func jsonData(for array: [Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(array) else {
            throw KeybindingReadError.invalidJSON
        }
        do {
            return try JSONSerialization.data(
                withJSONObject: array,
                options: [.prettyPrinted, .sortedKeys]
            )
        } catch {
            throw KeybindingReadError.invalidJSON
        }
    }

    private func createInitialBackupIfNeeded() throws -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return false
        }
        guard !FileManager.default.fileExists(atPath: backupURL.path) else {
            return false
        }
        do {
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
            return true
        } catch {
            throw KeybindingReadError.ioFailure
        }
    }

    private func replaceAtomically(data: Data, at target: URL) throws {
        let manager = FileManager.default
        let directory = target.deletingLastPathComponent()
        do {
            try manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let temporary = directory.appendingPathComponent(
                ".\(target.lastPathComponent).agent-controller-\(UUID().uuidString).tmp"
            )
            defer { try? manager.removeItem(at: temporary) }
            try data.write(to: temporary)
            if manager.fileExists(atPath: target.path) {
                _ = try manager.replaceItemAt(
                    target,
                    withItemAt: temporary,
                    backupItemName: nil,
                    options: .usingNewMetadataOnly
                )
            } else {
                try manager.moveItem(at: temporary, to: target)
            }
        } catch let error as KeybindingReadError {
            throw error
        } catch {
            throw KeybindingReadError.ioFailure
        }
    }
}
