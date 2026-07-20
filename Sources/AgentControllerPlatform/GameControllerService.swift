import Foundation
import GameController
import OSLog
import AgentControllerCore

/// 只读取 Xbox 手柄的 LT 和 X。连接、断连与睡眠时向上游发布安全边界。
@MainActor
public final class GameControllerService {
    public private(set) var currentSnapshot: ControllerSnapshot = .disconnected

    public var onSnapshot: ((ControllerSnapshot) -> Void)?
    public var onDeviceChange: ((String?) -> Void)?
    public var onSystemPowerBoundary: ((SystemPowerBoundary) -> Void)?

    private var controller: GCController?
    private var notificationTokens: [NSObjectProtocol] = []
    private let systemPowerObserver: any SystemPowerObserver
    private var lastInputSignature: String?
    private let logger = Logger(
        subsystem: "com.harryleft.agent-controller.macos",
        category: "Controller"
    )

    public init(
        systemPowerObserver: any SystemPowerObserver = NSWorkspaceSystemPowerObserver()
    ) {
        self.systemPowerObserver = systemPowerObserver
    }

    public func start() {
        guard notificationTokens.isEmpty else { return }
        GCController.shouldMonitorBackgroundEvents = true
        systemPowerObserver.start(
            onWillSleep: { [weak self] in self?.publishPowerBoundary(.willSleep) },
            onDidWake: { [weak self] in self?.publishPowerBoundary(.didWake) }
        )
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.attachFirstController() }
            },
            center.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.attachFirstController() }
            }
        ]
        attachFirstController()
    }

    public func stop() {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
        systemPowerObserver.stop()
        detach()
    }

    private func attachFirstController() {
        guard let candidate = GCController.controllers().first(where: {
            $0.extendedGamepad != nil
        }) else {
            detach()
            return
        }
        guard controller !== candidate else { return }
        detach()
        controller = candidate
        let name = candidate.vendorName ?? candidate.productCategory
        onDeviceChange?(name)
        logger.info("connected name=\(name, privacy: .public)")
        installHandler(for: candidate)
        publish(readSnapshot(from: candidate))
    }

    private func detach() {
        guard controller != nil || currentSnapshot.isConnected else { return }
        controller?.extendedGamepad?.valueChangedHandler = nil
        controller = nil
        currentSnapshot = .disconnected
        lastInputSignature = nil
        onDeviceChange?(nil)
        onSnapshot?(.disconnected)
        logger.info("disconnected")
    }

    private func installHandler(for controller: GCController) {
        controller.extendedGamepad?.valueChangedHandler = { [weak self, weak controller] _, _ in
            Task { @MainActor [weak self, weak controller] in
                guard let self, let controller, self.controller === controller else { return }
                self.publish(self.readSnapshot(from: controller))
            }
        }
    }

    private func readSnapshot(from controller: GCController) -> ControllerSnapshot {
        guard let gamepad = controller.extendedGamepad else { return .disconnected }
        return ControllerSnapshot(
            connected: true,
            buttons: gamepad.buttonX.isPressed ? [.x] : [],
            leftTrigger: Double(gamepad.leftTrigger.value)
        )
    }

    private func publish(_ snapshot: ControllerSnapshot) {
        currentSnapshot = snapshot
        let signature = "x=\(snapshot.buttons.contains(.x))|lt=\(snapshot.leftTrigger >= ControllerMappingEngine.triggerPressThreshold)"
        if signature != lastInputSignature {
            lastInputSignature = signature
            logger.info("input \(signature, privacy: .public)")
        }
        onSnapshot?(snapshot)
    }

    private func publishPowerBoundary(_ boundary: SystemPowerBoundary) {
        onSystemPowerBoundary?(boundary)
        logger.info("power boundary=\(boundary.rawValue, privacy: .public)")
    }
}

public enum SystemPowerBoundary: String, Equatable, Sendable {
    case willSleep
    case didWake
}
