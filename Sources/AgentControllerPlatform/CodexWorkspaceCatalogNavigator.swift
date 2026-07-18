import AgentControllerCore
import Foundation

/// Pure controller-side navigation for `CodexWorkspaceCatalog`.
///
/// The navigator never touches accessibility, deep links, or task titles. A
/// selected UUID is merely a local candidate; the automation adapter must
/// still freshly resolve that UUID from the visible Codex AX sidebar before it
/// is allowed to open anything.
public struct CodexWorkspaceCatalogNavigator: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        case confirmed(Selection)
        case unavailable
    }

    public enum Selection: Equatable, Sendable {
        case root(CodexWorkspaceRoot)
        case project(id: String)
        case task(UUID)
    }

    private var catalog: CodexWorkspaceCatalog?
    private var rootOffset = 0
    private var enteredProjectID: String?
    private var focused: Selection?

    public init() {}

    public var selectedTaskID: UUID? {
        guard case let .task(id) = focused else { return nil }
        return id
    }

    public var selection: Selection? { focused }

    public mutating func replaceCatalog(_ catalog: CodexWorkspaceCatalog) {
        self.catalog = catalog
        rootOffset = min(rootOffset, max(0, catalog.roots.count - 1))
        if let enteredProjectID, project(withID: enteredProjectID) == nil {
            self.enteredProjectID = nil
        }
        if let selectedTaskID, !containsTask(selectedTaskID) {
            focused = nil
        }
    }

    public mutating func clearSelection() {
        enteredProjectID = nil
        focused = nil
    }

    /// Drop a failed or unreadable catalog rather than allowing a previous
    /// in-memory snapshot to service a new controller input.
    public mutating func invalidate() {
        catalog = nil
        rootOffset = 0
        clearSelection()
    }

    public mutating func cycleRoot() -> Result {
        guard let catalog, !catalog.roots.isEmpty else { return .unavailable }
        rootOffset = (rootOffset + 1) % catalog.roots.count
        enteredProjectID = nil
        focused = .root(catalog.roots[rootOffset].root)
        return .confirmed(focused!)
    }

    public mutating func moveSelection(_ direction: SidebarTaskDirection) -> Result {
        guard let entries = currentEntries, !entries.isEmpty else {
            return .unavailable
        }
        let offset: Int
        if let focused, let current = entries.firstIndex(of: focused) {
            switch direction {
            case .previous: offset = (current - 1 + entries.count) % entries.count
            case .next: offset = (current + 1) % entries.count
            }
        } else {
            offset = direction == .previous ? entries.count - 1 : 0
        }
        focused = entries[offset]
        return .confirmed(entries[offset])
    }

    public mutating func enterProject() -> Result {
        guard enteredProjectID == nil,
              case let .project(id) = focused,
              let project = project(withID: id),
              !project.tasks.isEmpty else {
            return .unavailable
        }
        enteredProjectID = id
        focused = nil
        return .confirmed(.project(id: id))
    }

    public mutating func leaveProject() -> Result {
        guard let enteredProjectID else { return .unavailable }
        self.enteredProjectID = nil
        focused = .project(id: enteredProjectID)
        return .confirmed(focused!)
    }

    public mutating func moveRecentTask(_ direction: SidebarTaskDirection) -> Result {
        guard let catalog, !catalog.recentTasks.isEmpty else { return .unavailable }
        let tasks = catalog.recentTasks.map { Selection.task($0.threadID) }
        let offset: Int
        if let focused, let current = tasks.firstIndex(of: focused) {
            switch direction {
            case .previous: offset = (current + 1) % tasks.count
            case .next: offset = (current - 1 + tasks.count) % tasks.count
            }
        } else {
            offset = direction == .previous ? tasks.count - 1 : 0
        }
        focused = tasks[offset]
        return .confirmed(tasks[offset])
    }

    public mutating func selectAgentSlot(_ slot: AgentSlot) -> Result {
        guard let catalog else { return .unavailable }
        let index = slot.rawValue - 1
        guard catalog.agentSlots.indices.contains(index) else { return .unavailable }
        let selection = Selection.task(catalog.agentSlots[index].threadID)
        focused = selection
        return .confirmed(selection)
    }

    private var currentRoot: CodexWorkspaceRootDirectory? {
        guard let catalog, catalog.roots.indices.contains(rootOffset) else { return nil }
        return catalog.roots[rootOffset]
    }

    private var currentEntries: [Selection]? {
        if let enteredProjectID {
            return project(withID: enteredProjectID)?.tasks.map {
                .task($0.threadID)
            }
        }
        guard let currentRoot else { return nil }
        switch currentRoot.contents {
        case let .availableTasks(tasks):
            return tasks.map { .task($0.threadID) }
        case let .available(projects):
            return projects.map { .project(id: $0.project.id) }
        case .unavailable:
            return nil
        }
    }

    private func project(withID id: String) -> CodexWorkspaceProjectDirectory? {
        guard let catalog else { return nil }
        return catalog.roots.compactMap { root -> [CodexWorkspaceProjectDirectory]? in
            guard case let .available(projects) = root.contents else { return nil }
            return projects
        }.flatMap { $0 }.first { $0.project.id == id }
    }

    private func containsTask(_ id: UUID) -> Bool {
        catalog?.recentTasks.contains(where: { $0.threadID == id }) == true
    }
}
