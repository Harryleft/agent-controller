import Foundation

/// Physical controls normalized by the platform layer. Face-button names use
/// the Xbox layout; profiles may present different labels without changing the
/// semantic mapping.
public enum ControllerButton: String, CaseIterable, Hashable, Sendable {
    case a, b, x, y
    case menu, options, home, share
    case leftShoulder, rightShoulder
    case leftThumbstick, rightThumbstick
    case leftTrigger, rightTrigger
    case dpadUp, dpadDown, dpadLeft, dpadRight
}

/// A complete, side-effect-free controller reading.
public struct ControllerSnapshot: Equatable, Sendable {
    public var isConnected: Bool
    public var buttons: Set<ControllerButton>
    public var leftX: Double
    public var leftY: Double
    public var rightX: Double
    public var rightY: Double
    public var leftTrigger: Double
    public var rightTrigger: Double

    public init(
        isConnected: Bool,
        buttons: Set<ControllerButton> = [],
        leftX: Double = 0,
        leftY: Double = 0,
        rightX: Double = 0,
        rightY: Double = 0,
        leftTrigger: Double = 0,
        rightTrigger: Double = 0
    ) {
        self.isConnected = isConnected
        self.buttons = buttons
        self.leftX = Self.normalizedAxis(leftX)
        self.leftY = Self.normalizedAxis(leftY)
        self.rightX = Self.normalizedAxis(rightX)
        self.rightY = Self.normalizedAxis(rightY)
        self.leftTrigger = Self.normalizedTrigger(leftTrigger)
        self.rightTrigger = Self.normalizedTrigger(rightTrigger)
    }

    public init(
        connected: Bool,
        buttons: Set<ControllerButton> = [],
        leftStick: SIMD2<Double> = .zero,
        rightStick: SIMD2<Double> = .zero,
        leftTrigger: Double = 0,
        rightTrigger: Double = 0
    ) {
        self.init(
            isConnected: connected,
            buttons: buttons,
            leftX: leftStick.x,
            leftY: leftStick.y,
            rightX: rightStick.x,
            rightY: rightStick.y,
            leftTrigger: leftTrigger,
            rightTrigger: rightTrigger
        )
    }

    public static let disconnected = ControllerSnapshot(isConnected: false)

    public var connected: Bool { isConnected }
    public var leftStick: SIMD2<Double> { SIMD2(leftX, leftY) }
    public var rightStick: SIMD2<Double> { SIMD2(rightX, rightY) }

    /// A neutral snapshot has no pressed buttons, triggers, or stick movement.
    public func isNeutral(deadZone: Double = 0.12) -> Bool {
        let threshold = max(0, deadZone)
        return buttons.isEmpty &&
            abs(leftX) <= threshold && abs(leftY) <= threshold &&
            abs(rightX) <= threshold && abs(rightY) <= threshold &&
            leftTrigger <= threshold && rightTrigger <= threshold
    }

    private static func normalizedAxis(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(-1, value))
    }

    private static func normalizedTrigger(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

public enum NavigationDirection: String, CaseIterable, Equatable, Sendable {
    case up, down, left, right
}

/// Direction within Codex's visible sidebar task list. This intentionally
/// differs from editor navigation: selecting a candidate must not open it.
public enum SidebarTaskDirection: String, CaseIterable, Equatable, Sendable {
    case previous, next
}

public enum ControllerAction: Equatable, Sendable {
    case wakeCodex
    case openSelected
    case submit
    case openNewThread
    case cancel
    case stopTask
    case startDictation
    case stopDictation
    case navigate(NavigationDirection)
    case selectSidebarTask(SidebarTaskDirection)
    case openModelPicker
}

/// Session states deliberately distinguish a disabled session from a paused
/// one. Every safety boundary requires a fresh neutral reading before inputs
/// are accepted again, preventing a held control from leaking across it.
public enum ControllerSessionPhase: Equatable, Sendable {
    case locked
    case waitingForNeutral
    case active
    case paused
}

public struct ControllerSession: Sendable {
    public private(set) var phase: ControllerSessionPhase = .locked

    public init() {}

    public var isArmed: Bool { phase != .locked }
    public var isActive: Bool { phase == .active }

    public mutating func lock() {
        phase = .locked
    }

    public mutating func arm() {
        phase = .waitingForNeutral
    }

    public mutating func pause() {
        guard phase != .locked else { return }
        phase = .paused
    }

    public mutating func requireNeutral() {
        guard phase != .locked else { return }
        phase = .waitingForNeutral
    }

    @discardableResult
    public mutating func activateIfNeutral(_ isNeutral: Bool) -> Bool {
        guard phase == .waitingForNeutral, isNeutral else { return false }
        phase = .active
        return true
    }
}

public enum ControllerDeviceCategory: String, Equatable, Sendable {
    case xbox
    case standard
    case unsupported
}

/// Device metadata supplied by GameController. Classification is conservative:
/// only extended gamepads are controllable; Xbox is identified by its actual
/// profile first, then by trustworthy vendor/category metadata.
public struct ControllerDeviceDescriptor: Equatable, Sendable {
    public let vendorName: String?
    public let productCategory: String?
    public let profileIsXbox: Bool
    public let hasExtendedGamepad: Bool

    public init(
        vendorName: String? = nil,
        productCategory: String? = nil,
        profileIsXbox: Bool = false,
        hasExtendedGamepad: Bool = true
    ) {
        self.vendorName = Self.cleaned(vendorName)
        self.productCategory = Self.cleaned(productCategory)
        self.profileIsXbox = profileIsXbox
        self.hasExtendedGamepad = hasExtendedGamepad
    }

    public var category: ControllerDeviceCategory {
        guard hasExtendedGamepad else { return .unsupported }
        if profileIsXbox || Self.identifiesXbox(vendorName) || Self.identifiesXbox(productCategory) {
            return .xbox
        }
        return .standard
    }

    public var classification: ControllerDeviceCategory { category }
    public var isSupported: Bool { category != .unsupported }

    private static func cleaned(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func identifiesXbox(_ text: String?) -> Bool {
        guard let text = text?.lowercased() else { return false }
        return text.contains("xbox") || text.contains("microsoft")
    }
}

/// Converts snapshots to high-level actions without doing platform I/O.
/// `update` is intentionally the only time source: callers supply a monotonic
/// timestamp, making hold behavior deterministic and testable.
public struct ControllerMappingEngine: Sendable {
    public static let neutralDeadZone = 0.12
    public static let navigationThreshold = 0.24
    public static let dictationStartThreshold = 0.35
    public static let dictationStopThreshold = 0.20
    public static let stopHoldDuration: TimeInterval = 3

    public private(set) var session = ControllerSession()

    private var previous = ControllerSnapshot.disconnected
    private var previousForeground = false
    private var previousForegroundRequirement = false
    private var previousStickDirection: NavigationDirection?
    private var previousSidebarModifierActive = false
    private var suppressNavigationUntilDirectionalRelease = false
    private var dictationActive = false
    private var cancelStartedAt: TimeInterval?
    private var stopWasEmitted = false

    public init() {}

    public var phase: ControllerSessionPhase { session.phase }

    public mutating func update(
        snapshot: ControllerSnapshot,
        bridgeEnabled: Bool,
        onlyWhenCodexForeground: Bool,
        codexIsForeground: Bool,
        timestamp: TimeInterval,
        deadZone: Double = 0.24
    ) -> [ControllerAction] {
        let now = timestamp.isFinite ? timestamp : 0
        let configuredDeadZone = min(0.95, max(0, deadZone.isFinite ? deadZone : 0.24))
        let neutralDeadZone = min(0.30, max(0.12, configuredDeadZone * 0.5))

        guard bridgeEnabled else {
            let cleanup = drainSafetyActions()
            session.lock()
            clearTransientState()
            remember(snapshot, foreground: codexIsForeground, required: onlyWhenCodexForeground)
            return cleanup
        }

        guard snapshot.isConnected else {
            let cleanup = drainSafetyActions()
            session.lock()
            clearTransientState()
            remember(snapshot, foreground: codexIsForeground, required: onlyWhenCodexForeground)
            return cleanup
        }

        let foregroundAllowed = !onlyWhenCodexForeground || codexIsForeground
        let connectedNow = !previous.isConnected
        let foregroundPolicyChanged = previousForegroundRequirement != onlyWhenCodexForeground
        let foregroundChanged = onlyWhenCodexForeground && previousForeground != codexIsForeground
        let menuPressed = pressed(.menu, in: snapshot)
        let needsRearm = !session.isArmed

        if connectedNow || foregroundPolicyChanged || foregroundChanged || needsRearm {
            let cleanup = foregroundChanged && !foregroundAllowed
                ? drainSafetyActions()
                : []
            clearTransientState()
            if foregroundAllowed {
                session.arm()
            } else if session.isArmed {
                session.pause()
            } else {
                session.arm()
                session.pause()
            }
            remember(snapshot, foreground: codexIsForeground, required: onlyWhenCodexForeground)
            if !connectedNow && foregroundChanged && !foregroundAllowed && menuPressed {
                return cleanup + [.wakeCodex]
            }
            return cleanup
        }

        guard foregroundAllowed else {
            let actions: [ControllerAction] = pressed(.menu, in: snapshot) ? [.wakeCodex] : []
            remember(snapshot, foreground: codexIsForeground, required: onlyWhenCodexForeground)
            return actions
        }

        if session.phase == .paused {
            session.requireNeutral()
        }

        guard session.phase == .active else {
            _ = session.activateIfNeutral(snapshot.isNeutral(deadZone: neutralDeadZone))
            remember(snapshot, foreground: codexIsForeground, required: onlyWhenCodexForeground)
            return []
        }

        var actions: [ControllerAction] = []
        if pressed(.menu, in: snapshot) { actions.append(.wakeCodex) }

        let triggerAction = processDictation(snapshot)
        if let triggerAction { actions.append(triggerAction) }

        // Push-to-talk owns the input surface until the trigger crosses its
        // release threshold. This prevents a held LT from leaking face-button
        // or navigation actions into Codex while dictation is active.
        if triggerAction == nil && !dictationActive {
            processCancel(snapshot, now: now, actions: &actions)

            let navigation = navigationAction(
                snapshot,
                deadZone: configuredDeadZone
            )
            let movesSidebar: Bool
            if case .selectSidebarTask = navigation {
                movesSidebar = true
            } else {
                movesSidebar = false
            }

            // A never opens an older candidate in the same sample that moves
            // the sidebar selection. The user must release and press A again
            // after the asynchronous focus confirmation finishes.
            if pressed(.a, in: snapshot), !movesSidebar {
                actions.append(.openSelected)
            }
            if pressed(.x, in: snapshot) { actions.append(.submit) }
            if pressed(.y, in: snapshot) { actions.append(.openNewThread) }
            if pressed(.rightThumbstick, in: snapshot) { actions.append(.openModelPicker) }
            if let navigation {
                actions.append(navigation)
            }
        } else {
            absorbNavigationDuringDictation(
                snapshot,
                deadZone: configuredDeadZone
            )
        }

        remember(snapshot, foreground: codexIsForeground, required: onlyWhenCodexForeground)
        return actions
    }

    public mutating func update(
        snapshot: ControllerSnapshot,
        bridgeEnabled: Bool,
        onlyWhenCodexForeground: Bool,
        codexIsForeground: Bool,
        timestamp: Date,
        deadZone: Double = 0.24
    ) -> [ControllerAction] {
        update(
            snapshot: snapshot,
            bridgeEnabled: bridgeEnabled,
            onlyWhenCodexForeground: onlyWhenCodexForeground,
            codexIsForeground: codexIsForeground,
            timestamp: timestamp.timeIntervalSinceReferenceDate,
            deadZone: deadZone
        )
    }

    private mutating func processDictation(_ snapshot: ControllerSnapshot) -> ControllerAction? {
        if !dictationActive && snapshot.leftTrigger >= Self.dictationStartThreshold {
            dictationActive = true
            return .startDictation
        }
        if dictationActive && snapshot.leftTrigger <= Self.dictationStopThreshold {
            dictationActive = false
            return .stopDictation
        }
        return nil
    }

    private mutating func processCancel(
        _ snapshot: ControllerSnapshot,
        now: TimeInterval,
        actions: inout [ControllerAction]
    ) {
        if pressed(.b, in: snapshot) {
            cancelStartedAt = now
            stopWasEmitted = false
            return
        }

        guard previous.buttons.contains(.b), let startedAt = cancelStartedAt else { return }
        if snapshot.buttons.contains(.b) {
            if !stopWasEmitted && now - startedAt >= Self.stopHoldDuration {
                actions.append(.stopTask)
                stopWasEmitted = true
            }
            return
        }

        let reachedStop = stopWasEmitted || now - startedAt >= Self.stopHoldDuration
        if reachedStop {
            if !stopWasEmitted { actions.append(.stopTask) }
        } else {
            actions.append(.cancel)
        }
        cancelStartedAt = nil
        stopWasEmitted = false
    }

    private mutating func navigationAction(
        _ snapshot: ControllerSnapshot,
        deadZone: Double
    ) -> ControllerAction? {
        let dpad = dpadDirection(snapshot)
        let stick = stickDirection(snapshot, deadZone: deadZone)
        let sidebarModifierActive = snapshot.buttons.contains(.leftShoulder)
        let dpadIsNew = dpad != nil && dpad != dpadDirection(previous)
        let stickIsNew = stick != nil && stick != previousStickDirection
        defer {
            previousStickDirection = stick
            previousSidebarModifierActive = sidebarModifierActive
        }

        if suppressNavigationUntilDirectionalRelease {
            guard dpad == nil, stick == nil else { return nil }
            suppressNavigationUntilDirectionalRelease = false
            return nil
        }

        // LB creates a separate sidebar-selection layer. It intentionally
        // consumes every directional input, including left/right, so a held
        // modifier cannot leak ordinary arrow navigation into Codex.
        if sidebarModifierActive {
            if let dpad, (dpadIsNew || !previousSidebarModifierActive),
               let action = sidebarTaskAction(for: dpad) {
                return action
            }
            if let stick, (stickIsNew || !previousSidebarModifierActive),
               let action = sidebarTaskAction(for: stick) {
                return action
            }
            return nil
        }

        // Releasing LB while a direction remains held must not reinterpret the
        // same physical gesture as ordinary navigation. Require a directional
        // neutral reading before ordinary navigation resumes.
        if previousSidebarModifierActive {
            suppressNavigationUntilDirectionalRelease = dpad != nil || stick != nil
            return nil
        }

        if let dpad, dpadIsNew { return .navigate(dpad) }
        guard let stick, stickIsNew else { return nil }

        return .navigate(stick)
    }

    private mutating func absorbNavigationDuringDictation(
        _ snapshot: ControllerSnapshot,
        deadZone: Double
    ) {
        let dpad = dpadDirection(snapshot)
        let stick = stickDirection(snapshot, deadZone: deadZone)
        previousStickDirection = stick
        previousSidebarModifierActive = snapshot.buttons.contains(
            .leftShoulder
        )
        if dpad != nil || stick != nil {
            suppressNavigationUntilDirectionalRelease = true
        }
    }

    private func sidebarTaskAction(for direction: NavigationDirection) -> ControllerAction? {
        switch direction {
        case .up:
            return .selectSidebarTask(.previous)
        case .down:
            return .selectSidebarTask(.next)
        case .left, .right:
            return nil
        }
    }

    private func dpadDirection(_ snapshot: ControllerSnapshot) -> NavigationDirection? {
        if snapshot.buttons.contains(.dpadUp) { return .up }
        if snapshot.buttons.contains(.dpadDown) { return .down }
        if snapshot.buttons.contains(.dpadLeft) { return .left }
        if snapshot.buttons.contains(.dpadRight) { return .right }
        return nil
    }

    private func stickDirection(
        _ snapshot: ControllerSnapshot,
        deadZone: Double
    ) -> NavigationDirection? {
        let x = snapshot.leftX
        let y = snapshot.leftY
        let threshold = min(0.98, max(0.12, deadZone))
        guard max(abs(x), abs(y)) >= threshold else { return nil }
        if abs(y) >= abs(x) { return y >= 0 ? .up : .down }
        return x >= 0 ? .right : .left
    }

    private func pressed(_ button: ControllerButton, in snapshot: ControllerSnapshot) -> Bool {
        snapshot.buttons.contains(button) && !previous.buttons.contains(button)
    }

    private mutating func remember(
        _ snapshot: ControllerSnapshot,
        foreground: Bool,
        required: Bool
    ) {
        previous = snapshot
        previousForeground = foreground
        previousForegroundRequirement = required
    }

    private mutating func clearTransientState() {
        previousStickDirection = nil
        previousSidebarModifierActive = false
        suppressNavigationUntilDirectionalRelease = false
        dictationActive = false
        cancelStartedAt = nil
        stopWasEmitted = false
    }

    private mutating func drainSafetyActions() -> [ControllerAction] {
        dictationActive ? [.stopDictation] : []
    }
}
