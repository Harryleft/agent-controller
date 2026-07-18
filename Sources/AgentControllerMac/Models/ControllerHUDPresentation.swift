import Foundation

/// The HUD owns no controller or Codex state. It only renders the small,
/// privacy-preserving runtime projection passed in by the app layer.
enum ControllerHUDLayer: String, CaseIterable, Equatable, Hashable, Sendable, Identifiable {
    case base
    case leftShoulder
    case rightShoulder
    case rightTrigger
    case action

    var id: String { rawValue }
}

enum ControllerHUDStatus: Equatable, Sendable {
    case confirmed
    case unavailable
    case unknown
}

enum ControllerHUDLanguage: Equatable, Sendable {
    case chinese
    case english

    static var current: Self {
        from(localeIdentifier: Locale.current.identifier)
    }

    static func from(localeIdentifier: String) -> Self {
        Locale(identifier: localeIdentifier).language.languageCode?.identifier == "zh"
            ? .chinese
            : .english
    }
}

struct ControllerHUDRuntimeState: Equatable, Sendable {
    let bridgeEnabled: Bool
    let codexForeground: Bool
    let controllerConnected: Bool
    let activeLayer: ControllerHUDLayer
    let layerStatuses: [ControllerHUDLayer: ControllerHUDStatus]
    let slotStatuses: [ControllerHUDStatus]

    init(
        bridgeEnabled: Bool,
        codexForeground: Bool,
        controllerConnected: Bool,
        activeLayer: ControllerHUDLayer = .base,
        layerStatuses: [ControllerHUDLayer: ControllerHUDStatus] =
            Self.defaultLayerStatuses,
        slotStatuses: [ControllerHUDStatus] = []
    ) {
        self.bridgeEnabled = bridgeEnabled
        self.codexForeground = codexForeground
        self.controllerConnected = controllerConnected
        self.activeLayer = activeLayer
        self.layerStatuses = layerStatuses
        self.slotStatuses = slotStatuses
    }

    static let defaultLayerStatuses: [ControllerHUDLayer: ControllerHUDStatus] = [
        .base: .confirmed,
        .leftShoulder: .unknown,
        .rightShoulder: .unavailable,
        .rightTrigger: .unavailable,
        .action: .unavailable
    ]
}

/// Keeps the per-layer availability projection pure and privacy-safe so HUD
/// tests can prove that a missing Codex receipt is never painted as success.
enum ControllerHUDLayerStatusResolver {
    static func resolve(
        workspaceCatalogAvailable: Bool,
        actionStatus: ControllerHUDStatus,
        commandStatus: ControllerHUDStatus
    ) -> [ControllerHUDLayer: ControllerHUDStatus] {
        var statuses = ControllerHUDRuntimeState.defaultLayerStatuses
        statuses[.leftShoulder] = workspaceCatalogAvailable
            ? .confirmed
            : .unavailable
        statuses[.action] = actionStatus
        statuses[.rightShoulder] = commandStatus
        return statuses
    }
}

struct ControllerHUDPresentation: Equatable, Sendable {
    struct Layer: Equatable, Sendable, Identifiable {
        let kind: ControllerHUDLayer
        let status: ControllerHUDStatus
        let isActive: Bool

        var id: ControllerHUDLayer { kind }
    }

    struct Slot: Equatable, Sendable, Identifiable {
        let position: Int
        let status: ControllerHUDStatus

        var id: Int { position }
    }

    let isVisible: Bool
    let layers: [Layer]
    let slots: [Slot]

    static func resolve(from runtime: ControllerHUDRuntimeState) -> Self {
        guard runtime.bridgeEnabled,
              runtime.codexForeground,
              runtime.controllerConnected,
              runtime.activeLayer != .base else {
            return Self(isVisible: false, layers: [], slots: [])
        }

        let layers = ControllerHUDLayer.allCases.map { kind in
            Layer(
                kind: kind,
                status: runtime.layerStatuses[kind] ?? .unknown,
                isActive: runtime.activeLayer == kind
            )
        }
        let normalizedSlots = Array(runtime.slotStatuses.prefix(6)) +
            Array(
                repeating: .unknown,
                count: max(0, 6 - runtime.slotStatuses.count)
            )
        let slots = normalizedSlots.enumerated().map { offset, status in
            Slot(position: offset + 1, status: status)
        }
        return Self(isVisible: true, layers: layers, slots: slots)
    }
}

enum ControllerHUDCopy {
    static func title(_ language: ControllerHUDLanguage) -> String {
        language == .chinese ? "手柄 HUD" : "Controller HUD"
    }

    static func slotsTitle(_ language: ControllerHUDLanguage) -> String {
        language == .chinese ? "任务槽" : "Task slots"
    }

    static func readyTitle(_ language: ControllerHUDLanguage) -> String {
        language == .chinese ? "Codex 已就绪" : "Codex ready"
    }

    static func actionUnavailableNotice(
        _ language: ControllerHUDLanguage
    ) -> String {
        language == .chinese
            ? "Action 动作尚无已验证的精确 AX 路径"
            : "Action commands lack a verified exact AX route"
    }

    static func layer(
        _ layer: ControllerHUDLayer,
        language: ControllerHUDLanguage
    ) -> String {
        switch (layer, language) {
        case (.base, .chinese): "基础"
        case (.leftShoulder, .chinese): "LB"
        case (.rightShoulder, .chinese): "RB"
        case (.rightTrigger, .chinese): "RT"
        case (.action, .chinese): "动作"
        case (.base, .english): "Base"
        case (.leftShoulder, .english): "LB"
        case (.rightShoulder, .english): "RB"
        case (.rightTrigger, .english): "RT"
        case (.action, .english): "Action"
        }
    }

    static func status(
        _ status: ControllerHUDStatus,
        language: ControllerHUDLanguage
    ) -> String {
        switch (status, language) {
        case (.confirmed, .chinese): "已确认"
        case (.unavailable, .chinese): "不可用"
        case (.unknown, .chinese): "未知"
        case (.confirmed, .english): "Confirmed"
        case (.unavailable, .english): "Unavailable"
        case (.unknown, .english): "Unknown"
        }
    }
}
