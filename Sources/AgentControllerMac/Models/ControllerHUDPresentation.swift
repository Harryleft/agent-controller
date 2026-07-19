import Foundation

/// Internal availability state retained for AppModel's experimental catalog.
/// The simplified HUD intentionally does not render these values.
enum ControllerHUDStatus: Equatable, Sendable {
    case confirmed
    case local
    case unavailable
    case unknown
}

enum ControllerHUDAction: String, CaseIterable, Equatable, Sendable, Identifiable {
    case dictation
    case submit

    var id: String { rawValue }
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
}

struct ControllerHUDPresentation: Equatable, Sendable {
    let isVisible: Bool
    let actions: [ControllerHUDAction]

    static let hidden = Self(isVisible: false, actions: [])

    static func resolve(from runtime: ControllerHUDRuntimeState) -> Self {
        guard runtime.bridgeEnabled,
              runtime.codexForeground,
              runtime.controllerConnected else {
            return .hidden
        }
        return Self(isVisible: true, actions: ControllerHUDAction.allCases)
    }
}

enum ControllerHUDCopy {
    static func title(_ language: ControllerHUDLanguage) -> String {
        language == .chinese ? "手柄控制" : "Controller"
    }

    static func key(
        _ action: ControllerHUDAction,
        language: ControllerHUDLanguage
    ) -> String {
        switch action {
        case .dictation: "LT"
        case .submit: "X"
        }
    }

    static func action(
        _ action: ControllerHUDAction,
        language: ControllerHUDLanguage
    ) -> String {
        switch (action, language) {
        case (.dictation, .chinese): "按一下开始，再按一下结束"
        case (.submit, .chinese): "提交当前输入"
        case (.dictation, .english): "Press once to start, again to stop"
        case (.submit, .english): "Submit current input"
        }
    }
}
