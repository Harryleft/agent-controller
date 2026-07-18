import Foundation

/// The user-facing level of model controls. Persistence is deliberately kept
/// outside this domain: the UI can choose any storage implementation without
/// making this state machine depend on AppModel or UserDefaults.
public enum ModelControlMode: String, CaseIterable, Equatable, Sendable {
    case simple
    case advanced
}

/// Small persistence seam used by the settings screen and the model-control
/// domain. Implementations own their own synchronization and storage policy.
public protocol ModelControlModeStoring: AnyObject {
    var modelControlMode: ModelControlMode { get set }
}

public enum ModelControlTarget: String, CaseIterable, Equatable, Sendable {
    case model
    case effort
    case speed
}

public enum ModelControlDirection: Equatable, Sendable {
    case up
    case down
    case left
    case right
}

public enum ReasoningPowerDirection: Equatable, Sendable {
    case down
    case up
}

/// Semantic output only. Platform code must inspect the live Codex menu before
/// applying a step; no model, effort, speed, Max, or Ultra catalogue exists
/// here, so unavailable account capabilities can never be invented.
public enum ModelControlAction: Equatable, Sendable {
    case adjustReasoningPower(ReasoningPowerDirection)
    case selectSimpleSpeed(ModelControlSimpleSpeed)
    case selectAdvancedTarget(ModelControlTarget)
    case stepAdvancedTarget(ModelControlTarget, ModelControlDirection)
    case openModelMenu(ModelControlMode)
    case openAgentControllerSettings
}

public enum ModelControlSimpleSpeed: Equatable, Sendable {
    case standard
    case fast
}

/// Raw right-stick/R3 input isolated from the platform GameController API.
public struct ModelControlInput: Equatable, Sendable {
    public var rightX: Double
    public var rightY: Double
    public var rightStickPressed: Bool

    public init(rightX: Double = 0, rightY: Double = 0, rightStickPressed: Bool = false) {
        self.rightX = Self.normalized(rightX)
        self.rightY = Self.normalized(rightY)
        self.rightStickPressed = rightStickPressed
    }

    public static let neutral = ModelControlInput()

    private static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(-1, value))
    }
}

/// Keeps right-stick/R3 ownership below every exclusive controller layer.
/// App-level model shortcuts must not bypass the core mapper's LT/RT/Y/LB/RB
/// arbitration merely because they use a separate state machine.
public enum ModelControlArbitration: Sendable {
    public static func allowsInput(
        snapshot: ControllerSnapshot,
        layer: ControllerInputLayer,
        controllerActions: [ControllerAction]
    ) -> Bool {
        guard layer == .base,
              snapshot.leftTrigger < ControllerMappingEngine.dictationStartThreshold,
              snapshot.rightTrigger < ControllerMappingEngine.runningStartThreshold,
              !snapshot.buttons.contains(.leftShoulder),
              !snapshot.buttons.contains(.rightShoulder),
              !controllerActions.contains(.startDictation),
              !controllerActions.contains(.stopDictation) else {
            return false
        }
        return true
    }
}

/// Deterministic model-control state machine. Call `update` from the input
/// polling loop with a monotonic clock; it owns edge detection, held-direction
/// repeat, and R3 tap/hold disambiguation, but performs no platform I/O.
public struct ModelControlStateMachine {
    public static let directionThreshold = 0.24
    public static let initialRepeatDelay: TimeInterval = 0.35
    public static let accelerationDuration: TimeInterval = 2
    public static let initialRepeatInterval: TimeInterval = 0.24
    public static let minimumRepeatInterval: TimeInterval = 0.07
    public static let settingsHoldDuration: TimeInterval = 0.5

    private let modeStore: any ModelControlModeStoring
    private var heldDirection: ModelControlDirection?
    private var directionBeganAt: TimeInterval?
    private var nextRepeatAt: TimeInterval?
    private var selectedAdvancedTarget: ModelControlTarget = .model
    private var r3PressedAt: TimeInterval?
    private var r3HoldEmitted = false

    public init(modeStore: any ModelControlModeStoring) {
        self.modeStore = modeStore
    }

    public var mode: ModelControlMode { modeStore.modelControlMode }
    public var advancedTarget: ModelControlTarget { selectedAdvancedTarget }

    /// Settings owns mode selection; this method persists through the injected
    /// abstraction rather than knowing anything about the application's store.
    public func setMode(_ mode: ModelControlMode) {
        modeStore.modelControlMode = mode
    }

    /// Drop every in-flight right-stick/R3 gesture without emitting an action.
    /// The app calls this whenever any controller-to-Codex safety gate closes,
    /// so a release or delayed polling sample cannot synthesize a tap, hold,
    /// or repeat after foreground/session recovery.
    public mutating func reset() {
        heldDirection = nil
        directionBeganAt = nil
        nextRepeatAt = nil
        r3PressedAt = nil
        r3HoldEmitted = false
    }

    public mutating func update(
        _ input: ModelControlInput,
        timestamp: TimeInterval
    ) -> [ModelControlAction] {
        var actions = updateR3(input.rightStickPressed, timestamp: timestamp)
        actions.append(contentsOf: updateDirection(direction(for: input), timestamp: timestamp))
        return actions
    }

    private mutating func updateR3(_ isPressed: Bool, timestamp: TimeInterval) -> [ModelControlAction] {
        if isPressed {
            if r3PressedAt == nil {
                r3PressedAt = timestamp
                r3HoldEmitted = false
                return []
            }
            guard !r3HoldEmitted,
                  let pressedAt = r3PressedAt,
                  timestamp - pressedAt >= Self.settingsHoldDuration else {
                return []
            }
            r3HoldEmitted = true
            return [.openAgentControllerSettings]
        }

        guard r3PressedAt != nil else { return [] }
        defer {
            r3PressedAt = nil
            r3HoldEmitted = false
        }
        return r3HoldEmitted ? [] : [.openModelMenu(mode)]
    }

    private mutating func updateDirection(
        _ direction: ModelControlDirection?,
        timestamp: TimeInterval
    ) -> [ModelControlAction] {
        guard let direction else {
            // Releasing a stick intentionally drops all repeat bookkeeping, so
            // a later press is always a fresh edge and cannot leak queued work.
            heldDirection = nil
            directionBeganAt = nil
            nextRepeatAt = nil
            return []
        }

        guard direction == heldDirection else {
            heldDirection = direction
            directionBeganAt = timestamp
            nextRepeatAt = timestamp + Self.initialRepeatDelay
            return [action(for: direction)]
        }

        guard let dueAt = nextRepeatAt, timestamp >= dueAt else { return [] }
        let beganAt = directionBeganAt ?? timestamp
        nextRepeatAt = timestamp + repeatInterval(elapsed: max(0, timestamp - beganAt))
        return [action(for: direction)]
    }

    private mutating func action(for direction: ModelControlDirection) -> ModelControlAction {
        switch mode {
        case .simple:
            switch direction {
            case .left: return .adjustReasoningPower(.down)
            case .right: return .adjustReasoningPower(.up)
            case .up: return .selectSimpleSpeed(.standard)
            case .down: return .selectSimpleSpeed(.fast)
            }
        case .advanced:
            switch direction {
            case .left:
                selectedAdvancedTarget = previousTarget(after: selectedAdvancedTarget)
                return .selectAdvancedTarget(selectedAdvancedTarget)
            case .right:
                selectedAdvancedTarget = nextTarget(after: selectedAdvancedTarget)
                return .selectAdvancedTarget(selectedAdvancedTarget)
            case .up, .down:
                return .stepAdvancedTarget(selectedAdvancedTarget, direction)
            }
        }
    }

    private func repeatInterval(elapsed: TimeInterval) -> TimeInterval {
        let progress = min(1, elapsed / Self.accelerationDuration)
        return Self.initialRepeatInterval +
            (Self.minimumRepeatInterval - Self.initialRepeatInterval) * progress
    }

    private func direction(for input: ModelControlInput) -> ModelControlDirection? {
        let x = input.rightX
        let y = input.rightY
        guard max(abs(x), abs(y)) >= Self.directionThreshold else { return nil }
        if abs(y) >= abs(x) { return y >= 0 ? .up : .down }
        return x >= 0 ? .right : .left
    }

    private func nextTarget(after target: ModelControlTarget) -> ModelControlTarget {
        switch target {
        case .model: return .effort
        case .effort: return .speed
        case .speed: return .model
        }
    }

    private func previousTarget(after target: ModelControlTarget) -> ModelControlTarget {
        switch target {
        case .model: return .speed
        case .effort: return .model
        case .speed: return .effort
        }
    }
}
