import CryptoKit
import Foundation

/// A one-way identity for the exact task title exposed by Codex.
///
/// The adapter has to compare the sidebar, the local session index, and the
/// toolbar. Keeping only this digest prevents full task titles from becoming
/// controller state or telemetry.
public struct CodexSidebarTitleIdentity: Hashable, Sendable {
    fileprivate let digest: String

    public init?(exactTitle: String) {
        guard let normalized = Self.normalized(exactTitle) else {
            return nil
        }
        self.digest = Self.sha256(normalized)
    }

    fileprivate init?(sessionIndexThreadName: String) {
        self.init(exactTitle: sessionIndexThreadName)
    }

    private static func normalized(_ value: String) -> String? {
        // Codex currently exposes one complete line for the native task title.
        // Refuse multiline input instead of collapsing distinct titles onto a
        // shared first-line digest.
        guard !value.contains("\n"), !value.contains("\r") else {
            return nil
        }
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }
}

public enum CodexSessionIndexError: Error, Equatable, Sendable {
    case fileTooLarge
    case tooManyRecords
    case noValidRecords
}

/// Minimal, read-only view of `~/.codex/session_index.jsonl`.
///
/// Only UUID, title digest, and timestamp are retained. Unknown fields are
/// ignored, malformed or partially-written records are skipped, and an exact
/// title identity resolves only when it maps to one UUID globally.
public struct CodexSessionIndex: Sendable {
    public static let maximumFileBytes = 2 * 1_024 * 1_024
    public static let maximumRecords = 10_000

    private let threadIDsByTitleIdentity:
        [CodexSidebarTitleIdentity: Set<UUID>]

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("session_index.jsonl", isDirectory: false)
    }

    public init(contentsOf url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        if let size = attributes[.size] as? NSNumber,
           size.intValue > Self.maximumFileBytes {
            throw CodexSessionIndexError.fileTooLarge
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumFileBytes else {
            throw CodexSessionIndexError.fileTooLarge
        }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw CodexSessionIndexError.noValidRecords
        }

        let lines = contents.split(
            separator: "\n",
            omittingEmptySubsequences: true
        )
        guard lines.count <= Self.maximumRecords else {
            throw CodexSessionIndexError.tooManyRecords
        }

        let decoder = JSONDecoder()
        let fractionalTimestamp = ISO8601DateFormatter()
        fractionalTimestamp.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        let ordinaryTimestamp = ISO8601DateFormatter()
        ordinaryTimestamp.formatOptions = [.withInternetDateTime]

        var latestByThreadID:
            [UUID: (identity: CodexSidebarTitleIdentity, updatedAt: Date)] = [:]
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let record = try? decoder.decode(
                    SessionIndexRecord.self,
                    from: lineData
                  ),
                  let threadID = UUID(uuidString: record.id),
                  let identity = CodexSidebarTitleIdentity(
                    sessionIndexThreadName: record.threadName
                  ),
                  let updatedAt = fractionalTimestamp.date(
                    from: record.updatedAt
                  ) ?? ordinaryTimestamp.date(from: record.updatedAt) else {
                continue
            }

            if let existing = latestByThreadID[threadID],
               existing.updatedAt > updatedAt {
                continue
            }
            latestByThreadID[threadID] = (identity, updatedAt)
        }
        guard !latestByThreadID.isEmpty else {
            throw CodexSessionIndexError.noValidRecords
        }

        self.threadIDsByTitleIdentity = Dictionary(
            grouping: latestByThreadID,
            by: { $0.value.identity }
        ).mapValues { records in
            Set(records.map(\.key))
        }
    }

    public func uniqueThreadID(
        matching identity: CodexSidebarTitleIdentity
    ) -> UUID? {
        guard let matches = threadIDsByTitleIdentity[identity],
              matches.count == 1 else {
            return nil
        }
        return matches.first
    }
}

public enum CodexThreadDeepLink {
    public static let expectedHandlerBundleIdentifier = "com.openai.codex"

    public static func url(for threadID: UUID) -> URL? {
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(threadID.uuidString.lowercased())"
        return components.url
    }

    public static func acceptsHandler(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == expectedHandlerBundleIdentifier
    }
}

private struct SessionIndexRecord: Decodable {
    let id: String
    let threadName: String
    let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
        case updatedAt = "updated_at"
    }
}
