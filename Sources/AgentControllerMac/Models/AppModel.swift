import AgentControllerCore
import AgentControllerPlatform
import Combine
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    @Published var bridgeEnabled: Bool {
        didSet {
            defaults.set(bridgeEnabled, forKey: Keys.bridgeEnabled)
            process(currentSnapshot)
        }
    }

    @Published var onlyWhenCodexForeground: Bool {
        didSet {
            defaults.set(
                onlyWhenCodexForeground,
                forKey: Keys.onlyWhenCodexForeground)
            process(currentSnapshot)
        }
    }

    @Published var deadZone: Double {
        didSet {
            defaults.set(deadZone, forKey: Keys.deadZone)
        }
    }

    @Published private(set) var controllerName = "未连接"
    @Published private(set) var controllerCompatibility = "等待手柄"
    @Published private(set) var isControllerConnected = false
    @Published private(set) var liveInput = "—"
    @Published private(set) var codexRunning = false
    @Published private(set) var codexForeground = false
    @Published private(set) var canPostEvents = false
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var sessionPhase = "Locked"
    @Published private(set) var lastAction = "等待输入"

    private enum Keys {
        static let bridgeEnabled = "bridgeEnabled"
        static let onlyWhenCodexForeground =
            "onlyWhenCodexForeground"
        static let deadZone = "deadZone"
    }

    private let defaults: UserDefaults
    private let controllerService: GameControllerService
    private let automation: CodexMacAutomation
    private var mappingEngine = ControllerMappingEngine()
    private var currentSnapshot = ControllerSnapshot.disconnected
    private var dictationDesiredByBridge = false
    private var dictationStartedByBridge = false
    private var dictationNeedsCleanup = false
    private var dictationRevision = 0
    private var dictationTask: Task<Void, Never>?
    private var lastDictationCleanupAttempt: TimeInterval = 0
    private var timer: Timer?
    private var lastPermissionRefreshAt: TimeInterval = 0
    private var lastLoggedPhase: ControllerSessionPhase?
    private var lastLoggedPermissionState: PermissionState?
    private let logger = Logger(
        subsystem: "com.harryleft.agent-controller.macos",
        category: "Bridge"
    )

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        controllerService = GameControllerService()
        automation = CodexMacAutomation()

        if defaults.object(forKey: Keys.bridgeEnabled) == nil {
            bridgeEnabled = true
        } else {
            bridgeEnabled = defaults.bool(forKey: Keys.bridgeEnabled)
        }

        if defaults.object(
            forKey: Keys.onlyWhenCodexForeground) == nil
        {
            onlyWhenCodexForeground = true
        } else {
            onlyWhenCodexForeground = defaults.bool(
                forKey: Keys.onlyWhenCodexForeground)
        }

        let storedDeadZone = defaults.double(forKey: Keys.deadZone)
        deadZone = storedDeadZone == 0 ? 0.24 : storedDeadZone

        controllerService.onSnapshot = { [weak self] snapshot in
            self?.process(snapshot)
        }
        controllerService.onDeviceChange = { [weak self] device in
            self?.updateDevice(device)
        }
        controllerService.start()

        timer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRuntimeState()
            }
        }

        refreshRuntimeState()
    }

    func requestSystemPermission() {
        logger.info("control authorization requested")
        automation.requestAuthorization()
        refreshRuntimeState(forcePermissionRefresh: true)
    }

    func focusCodex() {
        execute(.wakeCodex)
        refreshRuntimeState()
    }

    private func updateDevice(
        _ device: ControllerDeviceDescriptor?
    ) {
        guard let device else {
            controllerName = "未连接"
            controllerCompatibility = "等待手柄"
            isControllerConnected = false
            return
        }

        controllerName =
            device.vendorName ??
            device.productCategory ??
            "Game Controller"
        controllerCompatibility = device.category.displayName
        isControllerConnected = true
    }

    private func refreshRuntimeState(
        forcePermissionRefresh: Bool = false
    ) {
        codexRunning = automation.isCodexRunning
        codexForeground = automation.isCodexForeground
        let now = ProcessInfo.processInfo.systemUptime
        if forcePermissionRefresh ||
            now - lastPermissionRefreshAt >= 2 {
            lastPermissionRefreshAt = now
            canPostEvents = automation.canPostEvents
            accessibilityTrusted =
                MacInputAuthorization.isAccessibilityTrusted
            logPermissionStateIfNeeded()
        }

        // A periodic update is required for the three-second B hold and for
        // foreground/permission transitions that do not emit controller data.
        process(currentSnapshot)
        retryDictationCleanupIfNeeded()
    }

    private func logPermissionStateIfNeeded() {
        let state = PermissionState(
            postEvent: canPostEvents,
            accessibility: accessibilityTrusted
        )
        guard state != lastLoggedPermissionState else { return }
        lastLoggedPermissionState = state
        logger.info(
            "permission postEvent=\(state.postEvent, privacy: .public) accessibility=\(state.accessibility, privacy: .public)"
        )
    }

    private func process(_ snapshot: ControllerSnapshot) {
        currentSnapshot = snapshot
        isControllerConnected = snapshot.isConnected
        liveInput = Self.describe(snapshot)

        let actions = mappingEngine.update(
            snapshot: snapshot,
            bridgeEnabled: bridgeEnabled,
            onlyWhenCodexForeground: onlyWhenCodexForeground,
            codexIsForeground: automation.isCodexForeground,
            timestamp: ProcessInfo.processInfo.systemUptime,
            deadZone: deadZone)
        sessionPhase = mappingEngine.phase.displayName
        if mappingEngine.phase != lastLoggedPhase {
            lastLoggedPhase = mappingEngine.phase
            logger.info("phase=\(self.sessionPhase, privacy: .public) bridge=\(self.bridgeEnabled, privacy: .public) codexForeground=\(self.automation.isCodexForeground, privacy: .public)")
        }

        for action in actions {
            execute(action)
        }
    }

    private func execute(_ action: ControllerAction) {
        switch action {
        case .startDictation:
            requestDictation(recording: true)
            return
        case .stopDictation:
            if !dictationStartedByBridge &&
                !dictationNeedsCleanup &&
                dictationTask == nil {
                dictationDesiredByBridge = false
                lastAction = "结束语音 · 无桥接录音"
                return
            }
            requestDictation(recording: false)
            return
        default:
            break
        }

        let succeeded = automation.execute(action)
        lastAction = "\(action.displayName) · \(succeeded ? "已执行" : "已阻止")"
        let result = succeeded ? "executed" : "blocked"
        logger.info("action=\(action.displayName, privacy: .public) result=\(result, privacy: .public)")
    }

    private func requestDictation(recording: Bool) {
        dictationDesiredByBridge = recording
        dictationRevision += 1
        lastAction = recording
            ? "开始语音 · 正在确认"
            : "结束语音 · 正在确认"

        guard dictationTask == nil else { return }
        dictationTask = Task { @MainActor [weak self] in
            await self?.reconcileDictationState()
        }
    }

    private func reconcileDictationState() async {
        while dictationDesiredByBridge != dictationStartedByBridge ||
                (!dictationDesiredByBridge && dictationNeedsCleanup) {
            let recording = dictationDesiredByBridge
            let attemptRevision = dictationRevision
            let result = await automation.setDictation(
                recording: recording
            )

            if recording && result == .alreadySatisfied {
                // 听写可能由用户手动启动；桥接没有执行状态转换，因此
                // 不取得所有权，LT 松开也不能替用户停止它。
                dictationDesiredByBridge = false
                dictationStartedByBridge = false
                dictationNeedsCleanup = false
                lastAction = "开始语音 · 已在录音，桥接未接管"
                logger.info(
                    "action=开始语音 result=already-active-not-owned"
                )
                break
            }

            if result.succeeded {
                dictationStartedByBridge = recording
                dictationNeedsCleanup = recording
                lastAction = recording
                    ? "开始语音 · 已确认录音"
                    : "结束语音 · 已确认停止"
                logger.info(
                    "action=\(recording ? "开始语音" : "结束语音", privacy: .public) result=confirmed"
                )
                // LT 可能在开始确认期间已经松开；循环会立即执行反向
                // 状态切换，不会把短触发留成持续录音。
                continue
            }

            if recording && result == .stateNotConfirmed {
                // 点击已经定向投递给 Codex，只是状态确认失败。保守地
                // 保留清理责任，LT 松开或返回前台后会尝试停止。
                dictationNeedsCleanup = true
            }

            lastAction = "\(recording ? "开始语音" : "结束语音") · \(result.diagnostic)"
            logger.error(
                "action=\(recording ? "开始语音" : "结束语音", privacy: .public) result=not-confirmed reason=\(result.diagnostic, privacy: .public)"
            )
            if dictationRevision != attemptRevision {
                continue
            }
            break
        }

        dictationTask = nil
    }

    private func retryDictationCleanupIfNeeded() {
        guard dictationStartedByBridge ||
                dictationNeedsCleanup ||
                dictationDesiredByBridge ||
                dictationTask != nil else {
            return
        }

        let needsCleanup =
            !bridgeEnabled ||
            !currentSnapshot.isConnected ||
            mappingEngine.phase != .active ||
            currentSnapshot.leftTrigger <=
                ControllerMappingEngine.dictationStopThreshold
        guard needsCleanup else { return }

        if dictationDesiredByBridge {
            requestDictation(recording: false)
        }
        guard automation.isCodexForeground else {
            if dictationStartedByBridge {
                lastAction = "语音待结束 · 返回 Codex 后自动清理"
            }
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDictationCleanupAttempt >= 1 else { return }
        lastDictationCleanupAttempt = now
        requestDictation(recording: false)
    }

    private static func describe(
        _ snapshot: ControllerSnapshot
    ) -> String {
        guard snapshot.isConnected else { return "—" }

        let buttons = snapshot.buttons
            .map(\.displayName)
            .sorted()
            .joined(separator: "  ")
        let analog = String(
            format: "L %.2f/%.2f · R %.2f/%.2f · LT %.2f",
            snapshot.leftX,
            snapshot.leftY,
            snapshot.rightX,
            snapshot.rightY,
            snapshot.leftTrigger)
        return buttons.isEmpty ? analog : "\(buttons) · \(analog)"
    }
}

private struct PermissionState: Equatable {
    let postEvent: Bool
    let accessibility: Bool
}

private extension ControllerAction {
    var displayName: String {
        switch self {
        case .wakeCodex: "置前 Codex"
        case .openSelected: "确认"
        case .submit: "提交"
        case .openNewThread: "新建任务"
        case .cancel: "取消"
        case .stopTask: "停止任务"
        case .startDictation: "开始语音"
        case .stopDictation: "结束语音"
        case .navigate(let direction): "方向 \(direction.displayName)"
        case .openModelPicker: "模型选择"
        }
    }
}

private extension ControllerSessionPhase {
    var displayName: String {
        switch self {
        case .locked: "Locked"
        case .paused: "Paused"
        case .waitingForNeutral: "等待回中"
        case .active: "Active"
        }
    }
}

private extension NavigationDirection {
    var displayName: String {
        switch self {
        case .up: "上"
        case .down: "下"
        case .left: "左"
        case .right: "右"
        }
    }
}

private extension ControllerButton {
    var displayName: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .menu: "Menu"
        case .options: "View"
        case .home: "Home"
        case .share: "Share"
        case .leftShoulder: "LB"
        case .rightShoulder: "RB"
        case .leftThumbstick: "L3"
        case .rightThumbstick: "R3"
        case .leftTrigger: "LT"
        case .rightTrigger: "RT"
        case .dpadUp: "↑"
        case .dpadDown: "↓"
        case .dpadLeft: "←"
        case .dpadRight: "→"
        }
    }
}

private extension ControllerDeviceCategory {
    var displayName: String {
        switch self {
        case .xbox: "Xbox 原生模式"
        case .standard: "标准扩展手柄"
        case .unsupported: "不支持的输入 profile"
        }
    }
}
