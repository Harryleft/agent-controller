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

/// Intent for the controller-owned workspace directory. These are local
/// selection operations only; none of them instruct Codex to open a task.
public enum WorkspaceCatalogIntent: Equatable, Sendable {
    case moveSelection(SidebarTaskDirection)
    case enterProject
    case leaveProject
    case cycleRoot
}

/// Base D-pad up/down have an intentionally separate semantic from the left
/// stick. The platform currently has no confirmed Q&A executor, so this
/// intent must remain unavailable rather than falling through to arrow keys.
public enum QuestionAnswerNavigationIntent: Equatable, Sendable {
    case previous
    case next
    case top
    case bottom
}

/// Input layers are mutually exclusive. They are exposed for deterministic
/// tests and for the HUD, but never grant platform automation on their own.
public enum ControllerInputLayer: String, Equatable, Sendable {
    case base
    case agent
    case command
    case running
    case actionPanel
}

public enum AgentSlot: Int, CaseIterable, Equatable, Sendable {
    case one = 1, two, three, four, five, six
}

public enum CommandIntent: String, Equatable, Sendable {
    case toggleFast
    case approve
    case decline
    case fork
    case dispatch
    case startPushToTalk
    case stopPushToTalk
}

public enum RunningIntent: String, Equatable, Sendable {
    case steer
    case queue
    case stop
    case fork
}

public enum ActionPanelIntent: String, Equatable, Sendable {
    case newTask
    case historyForward
    case toggleSidebar
    case historyBack
    case requestClearComposerConfirmation
    case clearComposer
    case projectContext
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
    case workspaceCatalog(WorkspaceCatalogIntent)
    case questionAnswer(QuestionAnswerNavigationIntent)
    case selectSidebarTask(SidebarTaskDirection)
    case openModelPicker
    case openPreviousTask
    case openNextTask
    case selectAgentSlot(AgentSlot)
    case command(CommandIntent)
    case running(RunningIntent)
    case openActionPanel
    case closeActionPanel
    case actionPanel(ActionPanelIntent)

    public var inputLayer: ControllerInputLayer {
        switch self {
        case .selectAgentSlot:
            return .agent
        case .command:
            return .command
        case .running:
            return .running
        case .openActionPanel, .closeActionPanel, .actionPanel:
            return .actionPanel
        default:
            return .base
        }
    }
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
    public static let runningStartThreshold = 0.55
    public static let runningStopThreshold = 0.35
    public static let shoulderTapDuration: TimeInterval = 0.18
    public static let stopHoldDuration: TimeInterval = 3
    public static let approveHoldDuration: TimeInterval = 0.5
    public static let clearComposerConfirmationDuration: TimeInterval = 2.5
    public static let questionAnswerTopHoldDuration: TimeInterval = 4
    public static let questionAnswerBottomHoldDuration: TimeInterval = 3
    /// A wireless controller can sleep without macOS immediately delivering
    /// a disconnect notification. After this much GameController silence,
    /// cached input must pass the neutral gate again before it can act.
    ///
    /// This is a continuity limit, not a claim that the device disconnected:
    /// the first post-silence press is intentionally sacrificed to prevent a
    /// stale held state from becoming an action.
    public static let inputContinuityTimeout: TimeInterval = 60

    public private(set) var session = ControllerSession()

    private var previous = ControllerSnapshot.disconnected
    private var previousForeground = false
    private var previousForegroundRequirement = false
    private var previousStickDirection: NavigationDirection?
    private var suppressNavigationUntilDirectionalRelease = false
    private var dictationActive = false
    private var commandPushToTalkActive = false
    private var runningLayerActive = false
    private var leftShoulderPressedAt: TimeInterval?
    private var rightShoulderPressedAt: TimeInterval?
    private var leftShoulderLayerActive = false
    private var rightShoulderLayerActive = false
    private var suppressShouldersUntilRelease = false
    private var commandApprovalPressedAt: TimeInterval?
    private var commandApprovalEmitted = false
    private var actionPanelActive = false
    private var clearComposerRequestedAt: TimeInterval?
    private var cancelStartedAt: TimeInterval?
    private var stopWasEmitted = false
    private var questionAnswerDirection: NavigationDirection?
    private var questionAnswerPressedAt: TimeInterval?
    private var questionAnswerHoldEmitted = false

    public init() {}

    public var phase: ControllerSessionPhase { session.phase }
    public var inputLayer: ControllerInputLayer {
        if runningLayerActive { return .running }
        if actionPanelActive { return .actionPanel }
        if leftShoulderLayerActive { return .agent }
        if rightShoulderLayerActive { return .command }
        return .base
    }

    public mutating func update(
        snapshot: ControllerSnapshot,
        bridgeEnabled: Bool,
        onlyWhenCodexForeground: Bool,
        codexIsForeground: Bool,
        timestamp: TimeInterval,
        inputContinuityEstablished: Bool = true,
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

        // AppModel periodically reprocesses the last snapshot for holds and
        // foreground changes. A stale cached snapshot is never live input.
        // Drain bridge-owned dictation once, then require a fresh neutral
        // sample before accepting any post-silence physical edge.
        guard inputContinuityEstablished else {
            let cleanup = drainSafetyActions()
            session.arm()
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
        let triggerAction = processDictation(snapshot)
        if let triggerAction {
            actions.append(triggerAction)
            if triggerAction == .startDictation {
                clearLayerState()
            }
        }

        // LT is exclusive: while recording (and on its start/stop samples),
        // no held shoulder, face button, or directional input can cross into
        // another layer when the trigger is released.
        if triggerAction != nil || dictationActive {
            absorbInputDuringDictation(snapshot, deadZone: configuredDeadZone)
        } else if runningLayerActive ||
            snapshot.rightTrigger >= Self.runningStartThreshold
        {
            clearQuestionAnswerHold()
            actions.append(contentsOf: routeRunningLayer(snapshot, now: now))
        } else if actionPanelActive {
            actions.append(contentsOf: routeActionPanel(snapshot, now: now))
            absorbNavigationDuringDictation(snapshot, deadZone: configuredDeadZone)
        } else if let shoulderActions = routeShoulderLayers(snapshot, now: now) {
            actions.append(contentsOf: shoulderActions)
            absorbNavigationDuringDictation(snapshot, deadZone: configuredDeadZone)
        } else {
            routeBaseLayer(
                snapshot,
                now: now,
                deadZone: configuredDeadZone,
                actions: &actions
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
        inputContinuityEstablished: Bool = true,
        deadZone: Double = 0.24
    ) -> [ControllerAction] {
        update(
            snapshot: snapshot,
            bridgeEnabled: bridgeEnabled,
            onlyWhenCodexForeground: onlyWhenCodexForeground,
            codexIsForeground: codexIsForeground,
            timestamp: timestamp.timeIntervalSinceReferenceDate,
            inputContinuityEstablished: inputContinuityEstablished,
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

    private mutating func routeBaseLayer(
        _ snapshot: ControllerSnapshot,
        now: TimeInterval,
        deadZone: Double,
        actions: inout [ControllerAction]
    ) {
        if pressed(.menu, in: snapshot) { actions.append(.wakeCodex) }
        processCancel(snapshot, now: now, actions: &actions)

        if pressed(.a, in: snapshot) { actions.append(.openSelected) }
        if pressed(.x, in: snapshot) { actions.append(.submit) }
        if pressed(.y, in: snapshot) {
            actionPanelActive = true
            clearComposerRequestedAt = nil
            actions.append(.openActionPanel)
            return
        }
        if pressed(.leftThumbstick, in: snapshot) {
            actions.append(.workspaceCatalog(.cycleRoot))
        }
        // R3 and the right stick are owned by ModelControlStateMachine in the
        // app layer. Keeping R3 out of this older general-action mapper avoids
        // a second, incompatible shortcut path racing the model controls.
        if let navigation = navigationAction(
            snapshot,
            now: now,
            deadZone: deadZone
        ) {
            actions.append(navigation)
        }
    }

    private mutating func routeRunningLayer(
        _ snapshot: ControllerSnapshot,
        now: TimeInterval
    ) -> [ControllerAction] {
        if !runningLayerActive {
            guard snapshot.rightTrigger >= Self.runningStartThreshold else {
                return []
            }
            runningLayerActive = true
            cancelStartedAt = nil
            stopWasEmitted = false
            // Entering a high-risk layer consumes the current sample so a
            // face button that was already held cannot become a command.
            return []
        }

        guard snapshot.rightTrigger > Self.runningStopThreshold else {
            runningLayerActive = false
            cancelStartedAt = nil
            stopWasEmitted = false
            return []
        }

        var actions: [ControllerAction] = []
        if pressed(.x, in: snapshot) { actions.append(.running(.steer)) }
        if pressed(.y, in: snapshot) { actions.append(.running(.queue)) }
        if pressed(.a, in: snapshot) { actions.append(.running(.fork)) }
        processRunningStop(snapshot, now: now, actions: &actions)
        return actions
    }

    private mutating func processRunningStop(
        _ snapshot: ControllerSnapshot,
        now: TimeInterval,
        actions: inout [ControllerAction]
    ) {
        if pressed(.b, in: snapshot) {
            cancelStartedAt = now
            stopWasEmitted = false
            return
        }

        guard previous.buttons.contains(.b), let startedAt = cancelStartedAt else {
            return
        }
        if snapshot.buttons.contains(.b) {
            if !stopWasEmitted && now - startedAt >= Self.stopHoldDuration {
                actions.append(.running(.stop))
                stopWasEmitted = true
            }
            return
        }

        cancelStartedAt = nil
        stopWasEmitted = false
    }

    /// Returns nil only when no shoulder is in a pending, held, or release
    /// state. An empty action list deliberately captures an unfinished chord.
    private mutating func routeShoulderLayers(
        _ snapshot: ControllerSnapshot,
        now: TimeInterval
    ) -> [ControllerAction]? {
        let leftHeld = snapshot.buttons.contains(.leftShoulder)
        let rightHeld = snapshot.buttons.contains(.rightShoulder)

        if suppressShouldersUntilRelease {
            if !leftHeld && !rightHeld {
                suppressShouldersUntilRelease = false
            }
            return []
        }

        // LB+RB has no defined semantic layer. Reject the ambiguous chord and
        // require both shoulders to be released; never silently prefer Agent
        // or Command. If RB View owned dictation, release that ownership once.
        if leftHeld && rightHeld {
            let cleanup: [ControllerAction] = commandPushToTalkActive
                ? [.command(.stopPushToTalk)] : []
            commandPushToTalkActive = false
            leftShoulderPressedAt = nil
            rightShoulderPressedAt = nil
            leftShoulderLayerActive = false
            rightShoulderLayerActive = false
            commandApprovalPressedAt = nil
            commandApprovalEmitted = false
            suppressShouldersUntilRelease = true
            return cleanup
        }

        if pressed(.leftShoulder, in: snapshot) {
            leftShoulderPressedAt = now
            leftShoulderLayerActive = false
        }
        if pressed(.rightShoulder, in: snapshot) {
            rightShoulderPressedAt = now
            rightShoulderLayerActive = false
        }

        if leftHeld {
            guard let startedAt = leftShoulderPressedAt else { return [] }
            if !leftShoulderLayerActive,
               now - startedAt >= Self.shoulderTapDuration {
                leftShoulderLayerActive = true
            }
            guard leftShoulderLayerActive else { return [] }
            return routeAgentLayer(snapshot)
        }

        if previous.buttons.contains(.leftShoulder), let startedAt = leftShoulderPressedAt {
            let wasLayer = leftShoulderLayerActive
            leftShoulderPressedAt = nil
            leftShoulderLayerActive = false
            if !wasLayer && now - startedAt <= Self.shoulderTapDuration {
                return [.openPreviousTask]
            }
            return []
        }

        if rightHeld {
            guard let startedAt = rightShoulderPressedAt else { return [] }
            if !rightShoulderLayerActive,
               now - startedAt >= Self.shoulderTapDuration {
                rightShoulderLayerActive = true
            }
            guard rightShoulderLayerActive else { return [] }
            return routeCommandLayer(snapshot, now: now)
        }

        if previous.buttons.contains(.rightShoulder), let startedAt = rightShoulderPressedAt {
            let wasLayer = rightShoulderLayerActive
            rightShoulderPressedAt = nil
            rightShoulderLayerActive = false
            commandApprovalPressedAt = nil
            commandApprovalEmitted = false
            if commandPushToTalkActive {
                commandPushToTalkActive = false
                return [.command(.stopPushToTalk)]
            }
            if !wasLayer && now - startedAt <= Self.shoulderTapDuration {
                return [.openNextTask]
            }
            return []
        }

        return nil
    }

    private func routeAgentLayer(_ snapshot: ControllerSnapshot) -> [ControllerAction] {
        let slots: [(ControllerButton, AgentSlot)] = [
            (.dpadUp, .one), (.dpadRight, .two), (.dpadDown, .three),
            (.dpadLeft, .four), (.options, .five), (.menu, .six)
        ]
        guard let (_, slot) = slots.first(where: { pressed($0.0, in: snapshot) }) else {
            return []
        }
        return [.selectAgentSlot(slot)]
    }

    private mutating func routeCommandLayer(
        _ snapshot: ControllerSnapshot,
        now: TimeInterval
    ) -> [ControllerAction] {
        var actions: [ControllerAction] = []
        if pressed(.y, in: snapshot) { actions.append(.command(.toggleFast)) }
        if pressed(.b, in: snapshot) { actions.append(.command(.decline)) }
        if pressed(.x, in: snapshot) { actions.append(.command(.fork)) }
        if pressed(.menu, in: snapshot) { actions.append(.command(.dispatch)) }

        if pressed(.options, in: snapshot), !commandPushToTalkActive {
            commandPushToTalkActive = true
            actions.append(.command(.startPushToTalk))
        } else if commandPushToTalkActive && !snapshot.buttons.contains(.options) {
            commandPushToTalkActive = false
            actions.append(.command(.stopPushToTalk))
        }

        if pressed(.a, in: snapshot) {
            commandApprovalPressedAt = now
            commandApprovalEmitted = false
        } else if snapshot.buttons.contains(.a),
                  let startedAt = commandApprovalPressedAt,
                  !commandApprovalEmitted,
                  now - startedAt >= Self.approveHoldDuration {
            commandApprovalEmitted = true
            actions.append(.command(.approve))
        } else if !snapshot.buttons.contains(.a) {
            commandApprovalPressedAt = nil
            commandApprovalEmitted = false
        }
        return actions
    }

    private mutating func routeActionPanel(
        _ snapshot: ControllerSnapshot,
        now: TimeInterval
    ) -> [ControllerAction] {
        if pressed(.y, in: snapshot) || pressed(.b, in: snapshot) {
            actionPanelActive = false
            clearComposerRequestedAt = nil
            return [.closeActionPanel]
        }
        if pressed(.dpadUp, in: snapshot) { return [.actionPanel(.newTask)] }
        if pressed(.dpadRight, in: snapshot) { return [.actionPanel(.historyForward)] }
        if pressed(.dpadDown, in: snapshot) { return [.actionPanel(.toggleSidebar)] }
        if pressed(.dpadLeft, in: snapshot) { return [.actionPanel(.historyBack)] }
        if pressed(.x, in: snapshot) { return [.actionPanel(.projectContext)] }

        if pressed(.a, in: snapshot) {
            if let requestedAt = clearComposerRequestedAt,
               now - requestedAt <= Self.clearComposerConfirmationDuration {
                clearComposerRequestedAt = nil
                return [.actionPanel(.clearComposer)]
            }
            clearComposerRequestedAt = now
            return [.actionPanel(.requestClearComposerConfirmation)]
        }
        if let requestedAt = clearComposerRequestedAt,
           now - requestedAt > Self.clearComposerConfirmationDuration {
            clearComposerRequestedAt = nil
        }
        return []
    }

    private mutating func navigationAction(
        _ snapshot: ControllerSnapshot,
        now: TimeInterval,
        deadZone: Double
    ) -> ControllerAction? {
        let dpad = dpadDirection(snapshot)
        let stick = stickDirection(snapshot, deadZone: deadZone)
        let dpadIsNew = dpad != nil && dpad != dpadDirection(previous)
        let stickIsNew = stick != nil && stick != previousStickDirection
        defer { previousStickDirection = stick }

        if suppressNavigationUntilDirectionalRelease {
            guard dpad == nil, stick == nil else { return nil }
            suppressNavigationUntilDirectionalRelease = false
            return nil
        }

        // D-pad up/down are release-confirmed Q&A actions.  A short press
        // emits only after release; a hold emits exactly one top/bottom intent
        // and suppresses the short intent.  No direction falls through to an
        // unconfirmed injected arrow key.
        if let dpad {
            switch dpad {
            case .up, .down:
                return questionAnswerAction(for: dpad, now: now)
            case .left:
                clearQuestionAnswerHold()
                return dpadIsNew ? .workspaceCatalog(.leaveProject) : nil
            case .right:
                clearQuestionAnswerHold()
                return dpadIsNew ? .workspaceCatalog(.enterProject) : nil
            }
        }
        if let shortPress = questionAnswerAction(for: nil, now: now) {
            return shortPress
        }
        guard let stick, stickIsNew else { return nil }
        switch stick {
        case .up:
            return .workspaceCatalog(.moveSelection(.previous))
        case .down:
            return .workspaceCatalog(.moveSelection(.next))
        case .left:
            return .workspaceCatalog(.leaveProject)
        case .right:
            return .workspaceCatalog(.enterProject)
        }
    }

    private mutating func absorbNavigationDuringDictation(
        _ snapshot: ControllerSnapshot,
        deadZone: Double
    ) {
        clearQuestionAnswerHold()
        let dpad = dpadDirection(snapshot)
        let stick = stickDirection(snapshot, deadZone: deadZone)
        previousStickDirection = stick
        if dpad != nil || stick != nil {
            suppressNavigationUntilDirectionalRelease = true
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
        suppressNavigationUntilDirectionalRelease = false
        dictationActive = false
        clearLayerState()
        cancelStartedAt = nil
        stopWasEmitted = false
        clearQuestionAnswerHold()
    }

    private mutating func clearLayerState() {
        commandPushToTalkActive = false
        runningLayerActive = false
        leftShoulderPressedAt = nil
        rightShoulderPressedAt = nil
        leftShoulderLayerActive = false
        rightShoulderLayerActive = false
        suppressShouldersUntilRelease = false
        commandApprovalPressedAt = nil
        commandApprovalEmitted = false
        actionPanelActive = false
        clearComposerRequestedAt = nil
        clearQuestionAnswerHold()
    }

    private mutating func questionAnswerAction(
        for direction: NavigationDirection?,
        now: TimeInterval
    ) -> ControllerAction? {
        guard let direction else {
            defer { clearQuestionAnswerHold() }
            guard let pending = questionAnswerDirection,
                  !questionAnswerHoldEmitted else {
                return nil
            }
            switch pending {
            case .up: return .questionAnswer(.previous)
            case .down: return .questionAnswer(.next)
            case .left, .right: return nil
            }
        }

        guard direction == .up || direction == .down else {
            clearQuestionAnswerHold()
            return nil
        }
        guard questionAnswerDirection == direction,
              let pressedAt = questionAnswerPressedAt else {
            questionAnswerDirection = direction
            questionAnswerPressedAt = now
            questionAnswerHoldEmitted = false
            return nil
        }
        guard !questionAnswerHoldEmitted else { return nil }

        let threshold = direction == .up
            ? Self.questionAnswerTopHoldDuration
            : Self.questionAnswerBottomHoldDuration
        guard now - pressedAt >= threshold else { return nil }
        questionAnswerHoldEmitted = true
        return .questionAnswer(direction == .up ? .top : .bottom)
    }

    private mutating func clearQuestionAnswerHold() {
        questionAnswerDirection = nil
        questionAnswerPressedAt = nil
        questionAnswerHoldEmitted = false
    }

    private mutating func absorbInputDuringDictation(
        _ snapshot: ControllerSnapshot,
        deadZone: Double
    ) {
        absorbNavigationDuringDictation(snapshot, deadZone: deadZone)
        clearLayerState()
    }

    private mutating func drainSafetyActions() -> [ControllerAction] {
        var actions: [ControllerAction] = []
        if dictationActive { actions.append(.stopDictation) }
        if commandPushToTalkActive {
            actions.append(.command(.stopPushToTalk))
        }
        return actions
    }
}
