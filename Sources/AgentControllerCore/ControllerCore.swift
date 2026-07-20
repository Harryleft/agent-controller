import Foundation

/// LT/X MVP 唯一需要的手柄按键。
public enum ControllerButton: Hashable, Sendable {
    case x
}

public struct ControllerSnapshot: Equatable, Sendable {
    public var isConnected: Bool
    public var buttons: Set<ControllerButton>
    public var leftTrigger: Double

    public init(
        isConnected: Bool,
        buttons: Set<ControllerButton> = [],
        leftTrigger: Double = 0
    ) {
        self.isConnected = isConnected
        self.buttons = buttons
        self.leftTrigger = min(1, max(0, leftTrigger.isFinite ? leftTrigger : 0))
    }

    public init(
        connected: Bool,
        buttons: Set<ControllerButton> = [],
        leftTrigger: Double = 0
    ) {
        self.init(
            isConnected: connected,
            buttons: buttons,
            leftTrigger: leftTrigger
        )
    }

    public static let disconnected = ControllerSnapshot(isConnected: false)

    public func isNeutral() -> Bool {
        buttons.isEmpty && leftTrigger <= ControllerMappingEngine.triggerReleaseThreshold
    }
}

public enum ControllerSessionPhase: Equatable, Sendable {
    case locked
    case waitingForNeutral
    case active
    case paused
}

public enum ControllerAction: Equatable, Sendable {
    case startVoice
    case stopVoice
    case submit
    case stopVoiceAndSubmit
}

/// 只负责可测试的物理输入状态：连接、前台和回中是硬门禁；LT 是
/// 两次按键切换豆包语音；X 在语音中会收口语音后提交。
public struct ControllerMappingEngine: Sendable {
    public static let triggerPressThreshold = 0.35
    public static let triggerReleaseThreshold = 0.20

    public private(set) var phase: ControllerSessionPhase = .locked

    private var previous = ControllerSnapshot.disconnected
    private var previousCodexForeground = false
    private var triggerPressed = false
    private var voiceActive = false

    public init() {}

    public mutating func update(
        snapshot: ControllerSnapshot,
        bridgeEnabled: Bool,
        codexIsForeground: Bool
    ) -> [ControllerAction] {
        defer {
            previous = snapshot
            previousCodexForeground = codexIsForeground
        }

        guard bridgeEnabled, snapshot.isConnected else {
            return lockAndDrainVoice()
        }

        guard codexIsForeground else {
            let actions = voiceActive ? stopVoice() : []
            phase = .paused
            triggerPressed = false
            return actions
        }

        if phase != .active {
            guard snapshot.isNeutral() else {
                phase = .waitingForNeutral
                return []
            }
            phase = .active
            triggerPressed = false
            return []
        }

        if !triggerPressed,
           snapshot.leftTrigger >= Self.triggerPressThreshold {
            triggerPressed = true
            voiceActive.toggle()
            return [voiceActive ? .startVoice : .stopVoice]
        }
        if triggerPressed,
           snapshot.leftTrigger <= Self.triggerReleaseThreshold {
            triggerPressed = false
        }

        guard xPressed(in: snapshot) else { return [] }
        if voiceActive {
            voiceActive = false
            return [.stopVoiceAndSubmit]
        }
        return [.submit]
    }

    private func xPressed(in snapshot: ControllerSnapshot) -> Bool {
        snapshot.buttons.contains(.x) && !previous.buttons.contains(.x)
    }

    private mutating func lockAndDrainVoice() -> [ControllerAction] {
        let actions = voiceActive ? stopVoice() : []
        phase = .locked
        triggerPressed = false
        return actions
    }

    private mutating func stopVoice() -> [ControllerAction] {
        voiceActive = false
        return [.stopVoice]
    }
}
