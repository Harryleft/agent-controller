import Foundation
import GameController
import OSLog
import AgentControllerCore

/// 将 macOS GameController 事件归一化为核心层快照。
@MainActor
public final class GameControllerService {
    public private(set) var currentSnapshot: ControllerSnapshot = .disconnected
    public private(set) var currentDevice: ControllerDeviceDescriptor?

    public var onSnapshot: ((ControllerSnapshot) -> Void)?
    public var onDeviceChange: ((ControllerDeviceDescriptor?) -> Void)?

    private var controller: GCController?
    private var activeDeviceReducer =
        ActiveControllerDeviceReducer<ObjectIdentifier>()
    private var notificationTokens: [NSObjectProtocol] = []
    private var lastDiagnosticSignature: String?
    private let logger = Logger(
        subsystem: "com.harryleft.agent-controller.macos",
        category: "Controller"
    )

    public init() {}

    /// 开始监听已连接和后续连接的扩展手柄。
    public func start() {
        guard notificationTokens.isEmpty else { return }

        GCController.shouldMonitorBackgroundEvents = true
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.selectFirstExtendedGamepad()
                }
            },
            center.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                // Notification is not Sendable. Reduce it to the immutable
                // process-local identity before crossing into MainActor.
                let disconnectedDeviceID = (
                    notification.object as? GCController
                ).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    self?.handleDisconnectNotification(disconnectedDeviceID)
                }
            }
        ]

        selectFirstExtendedGamepad()
    }

    /// 停止接收手柄状态，并向上游明确发布断连状态。
    public func stop() {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
        disconnect()
    }

    /// Reconciles the active device against GameController's current
    /// controller inventory. This is deliberately lifecycle-only: it never
    /// manufactures an input snapshot or treats a quiet controller as asleep.
    ///
    /// Call this periodically in addition to observing connect/disconnect
    /// notifications, as Apple's public API specifies both mechanisms for
    /// connection lifecycle tracking.
    public func reconcileControllerInventory() {
        selectFirstExtendedGamepad()
    }

    private func selectFirstExtendedGamepad(
        excludingDeviceID: ObjectIdentifier? = nil
    ) {
        let candidates = GCController.controllers().filter {
            ObjectIdentifier($0) != excludingDeviceID &&
                $0.extendedGamepad != nil
        }
        let candidateIDs = candidates.map(ObjectIdentifier.init)

        switch activeDeviceReducer.reconcile(availableDeviceIDs: candidateIDs) {
        case .unchanged, .nonActiveDisconnectIgnored:
            return
        case .activeDisconnected:
            detachCurrentControllerAndPublishDisconnect()
            selectFirstExtendedGamepad(excludingDeviceID: excludingDeviceID)
            return
        case let .activate(deviceID):
            guard let candidate = candidates.first(where: {
                ObjectIdentifier($0) == deviceID
            }) else {
                // The Core reducer only selects from `candidates`; if that
                // invariant is ever broken, fail closed rather than attaching
                // an arbitrary controller.
                activeDeviceReducer.reset()
                detachCurrentControllerAndPublishDisconnect()
                return
            }
            attach(candidate)
        }
    }

    private func attach(_ candidate: GCController) {
        controller?.extendedGamepad?.valueChangedHandler = nil
        controller = candidate

        let device = ControllerDeviceDescriptor(
            vendorName: candidate.vendorName,
            productCategory: candidate.productCategory,
            profileIsXbox: candidate.extendedGamepad is GCXboxGamepad,
            hasExtendedGamepad: true
        )
        currentDevice = device
        onDeviceChange?(device)
        let vendor = device.vendorName ?? "unknown"
        let product = device.productCategory ?? "unknown"
        logger.info("connected vendor=\(vendor, privacy: .public) product=\(product, privacy: .public) xboxProfile=\(device.profileIsXbox, privacy: .public) classification=\(device.category.rawValue, privacy: .public)")

        guard let gamepad = candidate.extendedGamepad else {
            disconnect()
            return
        }
        gamepad.valueChangedHandler = { [weak self, weak candidate] _, _ in
            Task { @MainActor [weak self, weak candidate] in
                guard let self, let candidate, self.controller === candidate else { return }
                self.publishSnapshot(from: candidate)
            }
        }
        publishSnapshot(from: candidate)
    }

    private func handleDisconnectNotification(
        _ disconnectedDeviceID: ObjectIdentifier?
    ) {
        guard let disconnectedDeviceID else {
            selectFirstExtendedGamepad()
            return
        }

        switch activeDeviceReducer.disconnectNotified(
            for: disconnectedDeviceID
        ) {
        case .nonActiveDisconnectIgnored, .unchanged, .activate(_):
            return
        case .activeDisconnected:
            detachCurrentControllerAndPublishDisconnect()
            selectFirstExtendedGamepad(excludingDeviceID: disconnectedDeviceID)
        }
    }

    private func disconnect() {
        activeDeviceReducer.reset()
        detachCurrentControllerAndPublishDisconnect()
    }

    private func detachCurrentControllerAndPublishDisconnect() {
        let hadController = controller != nil || currentDevice != nil
        controller?.extendedGamepad?.valueChangedHandler = nil
        controller = nil
        currentDevice = nil
        lastDiagnosticSignature = nil
        onDeviceChange?(nil)
        publish(.disconnected)
        if hadController {
            logger.info("disconnected")
        }
    }

    private func publishSnapshot(from controller: GCController) {
        guard let gamepad = controller.extendedGamepad else {
            disconnect()
            return
        }

        var buttons = Set<ControllerButton>()
        insert(&buttons, .a, when: gamepad.buttonA.isPressed)
        insert(&buttons, .b, when: gamepad.buttonB.isPressed)
        insert(&buttons, .x, when: gamepad.buttonX.isPressed)
        insert(&buttons, .y, when: gamepad.buttonY.isPressed)
        insert(&buttons, .menu, when: gamepad.buttonMenu.isPressed)
        insert(&buttons, .options, when: gamepad.buttonOptions?.isPressed == true)
        insert(&buttons, .home, when: gamepad.buttonHome?.isPressed == true)
        insert(&buttons, .leftShoulder, when: gamepad.leftShoulder.isPressed)
        insert(&buttons, .rightShoulder, when: gamepad.rightShoulder.isPressed)
        insert(&buttons, .leftThumbstick, when: gamepad.leftThumbstickButton?.isPressed == true)
        insert(&buttons, .rightThumbstick, when: gamepad.rightThumbstickButton?.isPressed == true)
        insert(&buttons, .dpadUp, when: gamepad.dpad.up.isPressed)
        insert(&buttons, .dpadDown, when: gamepad.dpad.down.isPressed)
        insert(&buttons, .dpadLeft, when: gamepad.dpad.left.isPressed)
        insert(&buttons, .dpadRight, when: gamepad.dpad.right.isPressed)
        insert(&buttons, .leftTrigger, when: gamepad.leftTrigger.isPressed)
        insert(&buttons, .rightTrigger, when: gamepad.rightTrigger.isPressed)

        if #available(macOS 12.0, *), let xboxGamepad = gamepad as? GCXboxGamepad {
            insert(&buttons, .share, when: xboxGamepad.buttonShare?.isPressed == true)
        }

        publish(
            ControllerSnapshot(
                connected: true,
                buttons: buttons,
                leftStick: SIMD2(
                    Double(gamepad.leftThumbstick.xAxis.value),
                    Double(gamepad.leftThumbstick.yAxis.value)
                ),
                rightStick: SIMD2(
                    Double(gamepad.rightThumbstick.xAxis.value),
                    Double(gamepad.rightThumbstick.yAxis.value)
                ),
                leftTrigger: Double(gamepad.leftTrigger.value),
                rightTrigger: Double(gamepad.rightTrigger.value)
            )
        )
    }

    private func publish(_ snapshot: ControllerSnapshot) {
        currentSnapshot = snapshot
        logDiagnosticChange(snapshot)
        onSnapshot?(snapshot)
    }

    /// Log only meaningful input-state transitions so a physical-controller
    /// test is readable without persisting every analog sample.
    private func logDiagnosticChange(_ snapshot: ControllerSnapshot) {
        guard snapshot.isConnected else { return }

        let buttons = snapshot.buttons.map(\.rawValue).sorted().joined(separator: ",")
        let buttonSummary = buttons.isEmpty ? "none" : buttons
        let left = direction(x: snapshot.leftX, y: snapshot.leftY)
        let right = direction(x: snapshot.rightX, y: snapshot.rightY)
        let leftTrigger = triggerBand(snapshot.leftTrigger)
        let rightTrigger = triggerBand(snapshot.rightTrigger)
        let signature = [buttonSummary, left, right, leftTrigger, rightTrigger]
            .joined(separator: "|")
        guard signature != lastDiagnosticSignature else { return }
        lastDiagnosticSignature = signature

        let ltValue = String(format: "%.2f", snapshot.leftTrigger)
        let rtValue = String(format: "%.2f", snapshot.rightTrigger)
        logger.info("input buttons=\(buttonSummary, privacy: .public) left=\(left, privacy: .public) right=\(right, privacy: .public) lt=\(ltValue, privacy: .public) rt=\(rtValue, privacy: .public)")
    }

    private func direction(x: Double, y: Double) -> String {
        guard max(abs(x), abs(y)) >= 0.35 else { return "neutral" }
        if abs(y) >= abs(x) { return y >= 0 ? "up" : "down" }
        return x >= 0 ? "right" : "left"
    }

    private func triggerBand(_ value: Double) -> String {
        if value >= ControllerMappingEngine.dictationStartThreshold { return "active" }
        if value > ControllerMappingEngine.dictationStopThreshold { return "transition" }
        return "released"
    }

    private func insert(
        _ buttons: inout Set<ControllerButton>,
        _ button: ControllerButton,
        when isPressed: Bool
    ) {
        if isPressed {
            buttons.insert(button)
        }
    }
}
