import CryptoKit
import Foundation
import AgentControllerCore

/// A resolved task observed in Codex's current, visible sidebar snapshot.
/// Full titles are intentionally not retained after discovery.
public struct CodexSidebarTask: Equatable, Sendable {
    public let threadID: UUID
    public let titleIdentity: CodexSidebarTitleIdentity

    public init(
        threadID: UUID,
        titleIdentity: CodexSidebarTitleIdentity
    ) {
        self.threadID = threadID
        self.titleIdentity = titleIdentity
    }

    public init?(
        threadID: UUID,
        exactTitle: String
    ) {
        guard let titleIdentity = CodexSidebarTitleIdentity(
            exactTitle: exactTitle
        ) else {
            return nil
        }
        self.init(threadID: threadID, titleIdentity: titleIdentity)
    }

    public var diagnosticIdentity: String {
        let digest = SHA256.hash(
            data: Data(threadID.uuidString.lowercased().utf8)
        )
        return digest.prefix(6).map {
            String(format: "%02x", $0)
        }.joined()
    }
}

public enum CodexSidebarCatalogError: Error, Equatable, Sendable {
    case duplicateThreadID
    case duplicateTitleIdentity
}

/// Pure selection rules shared by the live AX adapter and deterministic tests.
/// Visual order is supplied by the fresh AX snapshot and is never re-sorted by
/// title, project name, recency, or local Codex data.
public struct CodexSidebarTaskCatalog: Equatable, Sendable {
    public let tasks: [CodexSidebarTask]

    /// Remove every occurrence of an ambiguous title identity while preserving
    /// the AX order of all remaining tasks.
    public static func unambiguousTasks(
        from tasks: [CodexSidebarTask]
    ) -> [CodexSidebarTask] {
        let counts = Dictionary(grouping: tasks, by: \.titleIdentity)
            .mapValues(\.count)
        return tasks.filter {
            counts[$0.titleIdentity] == 1
        }
    }

    public init(validating tasks: [CodexSidebarTask]) throws {
        var seenThreadIDs = Set<UUID>()
        var seenTitleIdentities = Set<CodexSidebarTitleIdentity>()

        for task in tasks {
            guard seenThreadIDs.insert(task.threadID).inserted else {
                throw CodexSidebarCatalogError.duplicateThreadID
            }
            guard seenTitleIdentities.insert(task.titleIdentity).inserted else {
                throw CodexSidebarCatalogError.duplicateTitleIdentity
            }
        }
        self.tasks = tasks
    }

    public func destinationIndex(
        selectedThreadID: UUID?,
        currentThreadID: UUID?,
        direction: SidebarTaskDirection
    ) -> Int? {
        guard !tasks.isEmpty else { return nil }
        let anchor = selectedThreadID.flatMap(index(ofThreadID:)) ??
            currentThreadID.flatMap(index(ofThreadID:))

        guard let anchor else {
            return direction == .previous ? tasks.count - 1 : 0
        }
        switch direction {
        case .previous:
            return max(0, anchor - 1)
        case .next:
            return min(tasks.count - 1, anchor + 1)
        }
    }

    public func index(ofThreadID threadID: UUID) -> Int? {
        tasks.firstIndex { $0.threadID == threadID }
    }

    public func index(
        ofTitleIdentity titleIdentity: CodexSidebarTitleIdentity
    ) -> Int? {
        tasks.firstIndex { $0.titleIdentity == titleIdentity }
    }

    public func confirmsOpen(
        taskAt index: Int,
        currentThreadID: UUID?
    ) -> Bool {
        tasks.indices.contains(index) &&
            currentThreadID == tasks[index].threadID
    }
}

enum CodexToolbarIdentityResolution: Equatable, Sendable {
    case none
    case unique(CodexSidebarTitleIdentity)
    case ambiguous
}

/// Preserve observation multiplicity: two AX elements with the same text are
/// still ambiguous and must never be collapsed through `Set` deduplication.
enum CodexToolbarIdentityResolver {
    static func resolve(
        _ observations: [CodexSidebarTitleIdentity]
    ) -> CodexToolbarIdentityResolution {
        switch observations.count {
        case 0:
            .none
        case 1:
            .unique(observations[0])
        default:
            .ambiguous
        }
    }
}

/// Result of one sidebar selection or activation attempt. Only the two
/// confirmed cases may be presented as success; posting Space alone is never
/// enough to claim that Codex opened a task.
public enum CodexSidebarAutomationResult: Equatable, Sendable {
    case selectionConfirmed(position: Int, total: Int, identityHash: String)
    case openConfirmed(position: Int, total: Int, identityHash: String)
    case accessibilityDenied
    case postEventDenied
    case codexNotForeground
    case taskListUnavailable
    case taskListAmbiguous
    case noSelection
    case selectionExpired
    case focusFailed
    case deepLinkHandlerUnavailable
    case activationFailed
    case eventCreationFailed
    case openNotConfirmed

    public var succeeded: Bool {
        switch self {
        case .selectionConfirmed, .openConfirmed:
            true
        default:
            false
        }
    }

    public var diagnostic: String {
        switch self {
        case let .selectionConfirmed(position, total, _):
            "侧边栏候选 \(position)/\(total) 已确认"
        case let .openConfirmed(position, total, _):
            "侧边栏任务 \(position)/\(total) 已打开并确认"
        case .accessibilityDenied:
            "缺少辅助功能权限"
        case .postEventDenied:
            "缺少事件投递权限"
        case .codexNotForeground:
            "Codex 不在前台"
        case .taskListUnavailable:
            "没有可验证的可见任务"
        case .taskListAmbiguous:
            "可见任务身份不唯一"
        case .noSelection:
            "尚未选择侧边栏任务"
        case .selectionExpired:
            "侧边栏候选已失效"
        case .focusFailed:
            "无法确认侧边栏焦点"
        case .deepLinkHandlerUnavailable:
            "Codex 深链处理器不可用"
        case .activationFailed:
            "Codex 拒绝侧边栏语义激活"
        case .eventCreationFailed:
            "无法创建键盘事件"
        case .openNotConfirmed:
            "Codex 未确认任务已打开"
        }
    }

    var logValue: String {
        switch self {
        case .selectionConfirmed: "selection-confirmed"
        case .openConfirmed: "open-confirmed"
        case .accessibilityDenied: "accessibility-denied"
        case .postEventDenied: "post-event-denied"
        case .codexNotForeground: "codex-not-foreground"
        case .taskListUnavailable: "task-list-unavailable"
        case .taskListAmbiguous: "task-list-ambiguous"
        case .noSelection: "no-selection"
        case .selectionExpired: "selection-expired"
        case .focusFailed: "focus-failed"
        case .deepLinkHandlerUnavailable: "deep-link-handler-unavailable"
        case .activationFailed: "activation-failed"
        case .eventCreationFailed: "event-creation-failed"
        case .openNotConfirmed: "open-not-confirmed"
        }
    }
}
