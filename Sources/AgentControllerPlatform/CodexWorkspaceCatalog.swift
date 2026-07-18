import Foundation

/// A privacy-minimal, read-only directory built from Codex local metadata.
///
/// It reads only session UUIDs/timestamps and the explicitly named global
/// state fields below. Task titles, prompts, replies, working directories and
/// every unknown JSON field are deliberately absent from the public model.
public struct CodexWorkspaceCatalog: Equatable, Sendable {
    public static let agentSlotLimit = 6

    public let roots: [CodexWorkspaceRootDirectory]
    public let agentSlots: [CodexWorkspaceTask]

    public init(
        sessionIndexURL: URL = CodexSessionIndex.defaultURL,
        globalStateURL: URL = Self.defaultGlobalStateURL
    ) throws {
        let sessions = try CodexSessionIndex(contentsOf: sessionIndexURL).records
        let metadata = try? CodexWorkspaceMetadata(contentsOf: globalStateURL)
        self.init(sessionRecords: sessions, metadata: metadata)
    }

    public init(
        sessionRecords: [CodexSessionIndexRecord],
        metadata: CodexWorkspaceMetadata?
    ) {
        let latestByID = Self.latestRecordsByID(sessionRecords)
        let tasks = latestByID.values.map { record in
            CodexWorkspaceTask(threadID: record.threadID, updatedAt: record.updatedAt)
        }
        let state = metadata ?? .unavailable
        self.roots = Self.makeRoots(tasks: tasks, metadata: state)
        self.agentSlots = Self.makeAgentSlots(tasks: tasks, metadata: state)
    }

    public static var defaultGlobalStateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent(".codex-global-state.json", isDirectory: false)
    }

    private static func latestRecordsByID(
        _ records: [CodexSessionIndexRecord]
    ) -> [UUID: CodexSessionIndexRecord] {
        records.reduce(into: [:]) { result, record in
            guard let existing = result[record.threadID],
                  existing.updatedAt > record.updatedAt else {
                result[record.threadID] = record
                return
            }
        }
    }

    private static func makeRoots(
        tasks: [CodexWorkspaceTask],
        metadata: CodexWorkspaceMetadata
    ) -> [CodexWorkspaceRootDirectory] {
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.threadID, $0) })
        let pinnedTaskContents: CodexWorkspaceRootContents
        if case let .available(ids) = metadata.pinnedThreadIDs {
            pinnedTaskContents = .availableTasks(sort(ids.compactMap { byID[$0] }))
        } else {
            pinnedTaskContents = .unavailable
        }

        let projectContents: CodexWorkspaceRootContents
        if metadata.hasProjectDirectoryEvidence {
            projectContents = .available(projectDirectories(
                tasks: tasks,
                metadata: metadata,
                excluding: []
            ))
        } else {
            projectContents = .unavailable
        }
        let pinnedProjects: CodexWorkspaceRootContents
        if case let .available(ids) = metadata.pinnedProjectIDs,
           case let .available(projectsByID) = metadata.projects,
           metadata.hasProjectDirectoryEvidence {
            pinnedProjects = .available(projectDirectories(
                tasks: tasks,
                metadata: metadata,
                excluding: Set(projectsByID.keys).subtracting(ids)
            ))
        } else {
            pinnedProjects = .unavailable
        }

        let projectlessContents: CodexWorkspaceRootContents
        if case let .available(ids) = metadata.projectlessThreadIDs {
            projectlessContents = .availableTasks(sort(ids.compactMap { byID[$0] }))
        } else {
            projectlessContents = .unavailable
        }

        return [
            .init(root: .pinnedTasks, contents: pinnedTaskContents),
            .init(root: .pinnedProjects, contents: pinnedProjects),
            .init(root: .projects, contents: projectContents),
            .init(root: .noProject, contents: projectlessContents)
        ]
    }

    private static func projectDirectories(
        tasks: [CodexWorkspaceTask],
        metadata: CodexWorkspaceMetadata,
        excluding excludedIDs: Set<String>
    ) -> [CodexWorkspaceProjectDirectory] {
        guard case let .available(projectsByID) = metadata.projects,
              case let .available(assignments) = metadata.assignments else {
            return []
        }
        let tasksByProject = Dictionary(grouping: tasks.compactMap { task in
            assignments[task.threadID].map { ($0, task) }
        }, by: \.0).mapValues { pairs in sort(pairs.map(\.1)) }
        return projectsByID.compactMap { id, project in
            guard !excludedIDs.contains(id) else { return nil }
            return CodexWorkspaceProjectDirectory(
                project: project,
                tasks: tasksByProject[id] ?? []
            )
        }.sorted { lhs, rhs in
            let lhsRecent = lhs.tasks.first?.updatedAt ?? .distantPast
            let rhsRecent = rhs.tasks.first?.updatedAt ?? .distantPast
            if lhsRecent != rhsRecent { return lhsRecent > rhsRecent }
            return lhs.project.id < rhs.project.id
        }
    }

    private static func makeAgentSlots(
        tasks: [CodexWorkspaceTask],
        metadata: CodexWorkspaceMetadata
    ) -> [CodexWorkspaceTask] {
        let pinnedTaskIDs: Set<UUID>
        if case let .available(ids) = metadata.pinnedThreadIDs {
            pinnedTaskIDs = Set(ids)
        } else {
            pinnedTaskIDs = []
        }
        let pinnedProjectIDs: Set<String>
        if case let .available(ids) = metadata.pinnedProjectIDs {
            pinnedProjectIDs = Set(ids)
        } else {
            pinnedProjectIDs = []
        }
        let assignments: [UUID: String]
        if case let .available(value) = metadata.assignments {
            assignments = value
        } else {
            assignments = [:]
        }

        return tasks.sorted { lhs, rhs in
            let lhsPinned = pinnedTaskIDs.contains(lhs.threadID) ||
                pinnedProjectIDs.contains(assignments[lhs.threadID] ?? "")
            let rhsPinned = pinnedTaskIDs.contains(rhs.threadID) ||
                pinnedProjectIDs.contains(assignments[rhs.threadID] ?? "")
            if lhsPinned != rhsPinned { return lhsPinned }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.threadID.uuidString.lowercased() < rhs.threadID.uuidString.lowercased()
        }.prefix(agentSlotLimit).map { $0 }
    }

    private static func sort(_ tasks: [CodexWorkspaceTask]) -> [CodexWorkspaceTask] {
        tasks.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.threadID.uuidString.lowercased() < $1.threadID.uuidString.lowercased()
        }
    }
}

public enum CodexWorkspaceRoot: CaseIterable, Equatable, Sendable {
    case pinnedTasks
    case pinnedProjects
    case projects
    case noProject
}

public struct CodexWorkspaceRootDirectory: Equatable, Sendable {
    public let root: CodexWorkspaceRoot
    public let contents: CodexWorkspaceRootContents
}

public enum CodexWorkspaceRootContents: Equatable, Sendable {
    case availableTasks([CodexWorkspaceTask])
    case available([CodexWorkspaceProjectDirectory])
    case unavailable
}

public struct CodexWorkspaceTask: Equatable, Sendable {
    public let threadID: UUID
    public let updatedAt: Date
}

public struct CodexWorkspaceProject: Equatable, Sendable {
    /// Codex's opaque local project identifier, never a filesystem path.
    public let id: String
    public let name: String
}

public struct CodexWorkspaceProjectDirectory: Equatable, Sendable {
    public let project: CodexWorkspaceProject
    public let tasks: [CodexWorkspaceTask]
}

/// Parsed, allowed fields from `.codex-global-state.json`.
public struct CodexWorkspaceMetadata: Equatable, Sendable {
    public static let maximumFileBytes = CodexSessionIndex.maximumFileBytes

    public enum Field<Value: Equatable & Sendable>: Equatable, Sendable {
        case available(Value)
        case unavailable
    }

    public let projects: Field<[String: CodexWorkspaceProject]>
    public let pinnedThreadIDs: Field<[UUID]>
    public let pinnedProjectIDs: Field<[String]>
    public let assignments: Field<[UUID: String]>
    public let projectlessThreadIDs: Field<[UUID]>

    public static let unavailable = CodexWorkspaceMetadata(
        projects: .unavailable,
        pinnedThreadIDs: .unavailable,
        pinnedProjectIDs: .unavailable,
        assignments: .unavailable,
        projectlessThreadIDs: .unavailable
    )

    public init(
        projects: Field<[String: CodexWorkspaceProject]>,
        pinnedThreadIDs: Field<[UUID]>,
        pinnedProjectIDs: Field<[String]>,
        assignments: Field<[UUID: String]>,
        projectlessThreadIDs: Field<[UUID]>
    ) {
        self.projects = projects
        self.pinnedThreadIDs = pinnedThreadIDs
        self.pinnedProjectIDs = pinnedProjectIDs
        self.assignments = assignments
        self.projectlessThreadIDs = projectlessThreadIDs
    }

    fileprivate var hasProjectDirectoryEvidence: Bool {
        if case .available = projects, case .available = assignments {
            return true
        }
        return false
    }

    public init(contentsOf url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber,
           size.intValue > Self.maximumFileBytes {
            throw CodexWorkspaceMetadataError.fileTooLarge
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumFileBytes else {
            throw CodexWorkspaceMetadataError.fileTooLarge
        }
        self = (try? JSONDecoder().decode(Decoded.self, from: data))?.metadata ?? .unavailable
    }

    private struct Decoded: Decodable {
        let metadata: CodexWorkspaceMetadata

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            metadata = CodexWorkspaceMetadata(
                projects: Self.projects(from: container),
                pinnedThreadIDs: Self.uuidArray(.pinnedThreadIDs, from: container),
                pinnedProjectIDs: Self.stringArray(.pinnedProjectIDs, from: container),
                assignments: Self.assignments(from: container),
                projectlessThreadIDs: Self.uuidArray(.projectlessThreadIDs, from: container)
            )
        }

        private enum Keys: String, CodingKey {
            case localProjects = "local-projects"
            case pinnedThreadIDs = "pinned-thread-ids"
            case pinnedProjectIDs = "pinned-project-ids"
            case threadProjectAssignments = "thread-project-assignments"
            case projectlessThreadIDs = "projectless-thread-ids"
        }

        private static func projects(
            from container: KeyedDecodingContainer<Keys>
        ) -> Field<[String: CodexWorkspaceProject]> {
            guard let raw = try? container.decode([String: Project].self, forKey: .localProjects) else {
                return .unavailable
            }
            let projects = raw.compactMapValues { project -> CodexWorkspaceProject? in
                guard !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return .init(id: project.id, name: project.name)
            }
            return .available(projects)
        }

        private static func uuidArray(
            _ key: Keys, from container: KeyedDecodingContainer<Keys>
        ) -> Field<[UUID]> {
            guard let values = try? container.decode([String].self, forKey: key) else {
                return .unavailable
            }
            return .available(values.compactMap(UUID.init(uuidString:)))
        }

        private static func stringArray(
            _ key: Keys, from container: KeyedDecodingContainer<Keys>
        ) -> Field<[String]> {
            guard let values = try? container.decode([String].self, forKey: key) else {
                return .unavailable
            }
            return .available(values)
        }

        private static func assignments(
            from container: KeyedDecodingContainer<Keys>
        ) -> Field<[UUID: String]> {
            guard let raw = try? container.decode([String: Assignment].self, forKey: .threadProjectAssignments) else {
                return .unavailable
            }
            return .available(raw.reduce(into: [:]) { result, item in
                guard let threadID = UUID(uuidString: item.key),
                      !item.value.projectID.isEmpty else { return }
                result[threadID] = item.value.projectID
            })
        }

        private struct Project: Decodable {
            let id: String
            let name: String
        }

        private struct Assignment: Decodable {
            let projectID: String

            private enum CodingKeys: String, CodingKey {
                case projectID = "projectId"
            }
        }
    }
}

public enum CodexWorkspaceMetadataError: Error, Equatable, Sendable {
    case fileTooLarge
}
