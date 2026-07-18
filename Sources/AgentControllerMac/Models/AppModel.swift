import AgentControllerCore
import AgentControllerPlatform
import AppKit
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

    @Published var modelControlMode: ModelControlMode {
        didSet {
            modelControlStateMachine.setMode(modelControlMode)
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
    @Published private(set) var controllerInputLayer: ControllerInputLayer = .base
    @Published private(set) var keybindingStatus = "尚未配置"
    @Published private(set) var modelControlStatus = "Unavailable"
    @Published private(set) var lastAction = "等待输入"
    @Published private(set) var workspaceCatalogAvailable = false
    @Published private(set) var workspaceSlotStatuses: [ControllerHUDStatus] =
        Array(repeating: .unknown, count: CodexWorkspaceCatalog.agentSlotLimit)

    /// Y 面板中的六个 Codex 动作目前都没有经过真实 AX 结构与动作后状态
    /// 变化的验证。这个状态必须显式传给 HUD，不能把已投递快捷键误报为
    /// 可用或已确认。
    var actionPanelStatus: ControllerHUDStatus { .unavailable }

    /// RB 的语音操作有独立的、可确认的听写适配器；其余 Command 槽没有
    /// Codex 可观察回执。HUD 不能因一个局部路径存在而把整层误标成已确认。
    var commandLayerStatus: ControllerHUDStatus { .unavailable }

    /// RT Running 动作均没有当前 Codex 的精确 AX 回执，因此该层保持
    /// fail-closed，即使 Fork 的固定快捷键已实际投递也不改成已确认。
    var runningLayerStatus: ControllerHUDStatus { .unavailable }

    private enum Keys {
        static let bridgeEnabled = "bridgeEnabled"
        static let onlyWhenCodexForeground =
            "onlyWhenCodexForeground"
        static let deadZone = "deadZone"
    }

    private let defaults: UserDefaults
    private let controllerService: GameControllerService
    private let automation: CodexMacAutomation
    private let keybindingConfigurationService:
        CodexKeybindingConfigurationService
    private let modelControlModeStore: UserDefaultsModelControlModeStore
    private let actionSemantics = CodexActionSemantics()
    private var mappingEngine = ControllerMappingEngine()
    private var modelControlStateMachine: ModelControlStateMachine
    private var modelBindingAvailability: [
        CodexSemanticAction: CodexKeybindingAvailability
    ] = [:]
    private var currentSnapshot = ControllerSnapshot.disconnected
    /// Updated only by a GameController delivery, never by the periodic
    /// hold/foreground timer. This lets the core reject a cached snapshot
    /// after a silent wireless sleep.
    private var lastControllerObservationAt: TimeInterval?
    private var dictationDesiredByBridge = false
    private var dictationStartedByBridge = false
    private var dictationNeedsCleanup = false
    private var dictationRevision = 0
    private var dictationTask: Task<Void, Never>?
    private var lastDictationCleanupAttempt: TimeInterval = 0
    private var sidebarTask: Task<Void, Never>?
    private var sidebarRevision = 0
    private var workspaceNavigator = CodexWorkspaceCatalogNavigator()
    private var lastWorkspaceCatalogRefreshAt: TimeInterval = 0
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
        let modelControlModeStore = UserDefaultsModelControlModeStore(
            defaults: defaults
        )
        self.modelControlModeStore = modelControlModeStore
        modelControlStateMachine = ModelControlStateMachine(
            modeStore: modelControlModeStore
        )
        modelControlMode = modelControlModeStore.modelControlMode
        keybindingConfigurationService =
            CodexKeybindingConfigurationService()
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

        configureCodexKeybindings()

        controllerService.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            if snapshot.isConnected {
                lastControllerObservationAt = ProcessInfo.processInfo.systemUptime
            } else {
                lastControllerObservationAt = nil
            }
            process(snapshot)
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

    private func configureCodexKeybindings() {
        let result = keybindingConfigurationService.install()
        modelBindingAvailability = Dictionary(
            uniqueKeysWithValues: CodexSemanticAction.allCases.map {
                ($0, keybindingConfigurationService.bindingAvailability(for: $0))
            }
        )
        modelControlStatus = modelBindingStatusDescription()
        switch result.outcome {
        case let .updated(backupCreated, conflicts):
            let base = backupCreated ? "已配置 · 已备份" : "已配置"
            keybindingStatus = conflicts.isEmpty ? base : "\(base) · 部分冲突"
        case let .unchanged(conflicts):
            keybindingStatus = conflicts.isEmpty ? "已配置" : "部分冲突"
        case .invalidJSON:
            keybindingStatus = "配置无效 · 未修改"
        case .backupUnavailable, .ioFailure:
            keybindingStatus = "配置失败 · 未修改"
        case .restored:
            // install() never restores, but keep the UI exhaustive if the
            // service gains an explicit restore action later.
            keybindingStatus = "已恢复"
        }
        logger.info(
            "keybindings result=\(self.keybindingStatus, privacy: .public)"
        )
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

        let now = ProcessInfo.processInfo.systemUptime
        let inputContinuityEstablished = snapshot.isConnected &&
            lastControllerObservationAt.map {
                now - $0 <= ControllerMappingEngine.inputContinuityTimeout
            } == true

        let actions = mappingEngine.update(
            snapshot: snapshot,
            bridgeEnabled: bridgeEnabled,
            onlyWhenCodexForeground: onlyWhenCodexForeground,
            codexIsForeground: automation.isCodexForeground,
            timestamp: now,
            inputContinuityEstablished: inputContinuityEstablished,
            deadZone: deadZone)
        sessionPhase = mappingEngine.phase.displayName
        controllerInputLayer = mappingEngine.inputLayer
        if mappingEngine.phase != lastLoggedPhase {
            lastLoggedPhase = mappingEngine.phase
            logger.info("phase=\(self.sessionPhase, privacy: .public) bridge=\(self.bridgeEnabled, privacy: .public) codexForeground=\(self.automation.isCodexForeground, privacy: .public) inputContinuity=\(inputContinuityEstablished, privacy: .public)")
        }

        if !bridgeEnabled ||
            !snapshot.isConnected ||
            mappingEngine.phase != .active ||
            !automation.isCodexForeground {
            clearSidebarSelection()
            clearWorkspaceSelection()
        } else if mappingEngine.inputLayer == .agent {
            refreshWorkspaceCatalogIfNeeded()
        }

        processModelControls(snapshot)

        for action in actions {
            execute(action)
        }
    }

    private func processModelControls(_ snapshot: ControllerSnapshot) {
        guard bridgeEnabled,
              snapshot.isConnected,
              mappingEngine.phase == .active,
              automation.isCodexForeground else {
            modelControlStateMachine.reset()
            return
        }

        let input = ModelControlInput(
            rightX: snapshot.rightX,
            rightY: snapshot.rightY,
            rightStickPressed: snapshot.buttons.contains(.rightThumbstick)
        )
        let actions = modelControlStateMachine.update(
            input,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        for action in actions {
            if action == .openAgentControllerSettings {
                openAgentControllerSettings()
                continue
            }
            let availability = bindingAvailability(for: action)
            let result = automation.executeModelControl(
                action,
                bindingAvailability: availability
            )
            lastAction = "\(action.displayName) · \(result.diagnostic)"
        }
    }

    private func bindingAvailability(
        for action: ModelControlAction
    ) -> CodexKeybindingAvailability {
        guard case let .shortcut(.semantic(semanticAction)) =
                CodexModelControlDispatchPlan.resolve(action) else {
            return .unavailable
        }
        let availability = keybindingConfigurationService.bindingAvailability(
            for: semanticAction
        )
        modelBindingAvailability[semanticAction] = availability
        modelControlStatus = modelBindingStatusDescription()
        return availability
    }

    private func modelBindingStatusDescription() -> String {
        let labels: [(CodexSemanticAction, String)] = [
            (.reasoningDown, "F13"),
            (.reasoningUp, "F14"),
            (.openModelPicker, "F15"),
            (.toggleFastMode, "F16")
        ]
        return labels.map { action, key in
            let availability = modelBindingAvailability[action] ?? .unavailable
            return "\(key) \(availability == .available ? "可用" : "Unavailable")"
        }.joined(separator: " · ")
    }

    private func openAgentControllerSettings() {
        NSApp.activate(ignoringOtherApps: true)
        let shown = NSApp.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        )
        lastAction = shown ? "打开 Agent Controller 设置" : "设置 · Unavailable"
    }

    private func execute(_ action: ControllerAction) {
        switch action {
        case .openActionPanel:
            clearSidebarSelection()
            lastAction = "动作面板 · 所有 Codex 动作当前不可用"
            logger.info("action-panel result=opened-safe-unavailable")
            return
        case .closeActionPanel:
            clearSidebarSelection()
            lastAction = "动作面板 · 已关闭"
            logger.info("action-panel result=closed-local")
            return
        case .actionPanel(.requestClearComposerConfirmation):
            // Core 保留双 A 确认语义；本层不读取 composer 正文，也不尝试
            // 用 Delete、Command+A 或任意快捷键伪造清空成功。
            lastAction = "清空编辑器 · 再按 A 确认（当前不可用）"
            logger.info("action-panel action=clear-composer result=awaiting-confirmation")
            return
        case let .actionPanel(intent):
            executeActionPanelIntent(intent)
            return
        case .startDictation:
            clearSidebarSelection()
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
        case .command(.startPushToTalk):
            clearSidebarSelection()
            requestDictation(recording: true)
            return
        case .command(.stopPushToTalk):
            if !dictationStartedByBridge &&
                !dictationNeedsCleanup &&
                dictationTask == nil {
                dictationDesiredByBridge = false
                lastAction = "Command 语音 · 无桥接录音"
                return
            }
            requestDictation(recording: false)
            return
        case let .command(intent):
            clearSidebarSelection()
            executeCommandIntent(intent)
            return
        case let .running(intent):
            clearSidebarSelection()
            executeRunningIntent(intent)
            return
        case let .selectSidebarTask(direction):
            clearWorkspaceSelection()
            requestSidebarSelection(direction: direction)
            return
        case let .workspaceCatalog(intent):
            clearSidebarSelection()
            performWorkspaceCatalog(intent)
            return
        case .openPreviousTask:
            clearSidebarSelection()
            performRecentWorkspaceSelection(.previous)
            return
        case .openNextTask:
            clearSidebarSelection()
            performRecentWorkspaceSelection(.next)
            return
        case let .selectAgentSlot(slot):
            clearSidebarSelection()
            performAgentSlotSelection(slot)
            return
        case let .questionAnswer(intent):
            clearSidebarSelection()
            clearWorkspaceSelection()
            lastAction = intent == .previous
                ? "问答上一条 · 不可用（无安全执行器）"
                : "问答下一条 · 不可用（无安全执行器）"
            logger.info("action=qa-navigation result=unavailable-no-safe-executor")
            return
        case .openSelected:
            if sidebarTask != nil {
                lastAction = "侧边栏候选 · 正在确认，请重新按 A"
                logger.info(
                    "sidebar operation=open result=blocked-selection-in-flight"
                )
                return
            }
            if let threadID = workspaceNavigator.selectedTaskID {
                requestWorkspaceOpen(threadID: threadID)
                return
            }
            if automation.hasSidebarTaskSelection {
                requestSidebarOpen()
                return
            }
            lastAction = CodexBaseActionPolicy.unavailableDiagnostic(
                for: action
            ) ?? "打开任务 · Unavailable"
            logger.info("action=open result=unavailable-no-confirmed-candidate")
            return
        case .wakeCodex:
            clearSidebarSelection()
            clearWorkspaceSelection()
            requestCodexWakeConfirmation()
            return
        case .submit:
            clearSidebarSelection()
            clearWorkspaceSelection()
            // Never degrade to Return: a posted event is not a confirmed
            // composer submission, and this layer must not inspect text.
            lastAction = CodexBaseActionPolicy.unavailableDiagnostic(
                for: action
            ) ?? "提交 · Unavailable"
            logger.info("action=submit result=unavailable-no-ui-receipt")
            return
        case .cancel, .stopTask:
            clearSidebarSelection()
            clearWorkspaceSelection()
            // Escape has no semantic receipt for either a short-press cancel
            // or three-second stop.  Do not close arbitrary Codex UI state.
            lastAction = CodexBaseActionPolicy.unavailableDiagnostic(
                for: action
            ) ?? "Unavailable"
            logger.info("action=cancel result=unavailable-no-ui-receipt")
            return
        default:
            break
        }

        clearSidebarSelection()
        clearWorkspaceSelection()
        _ = automation.execute(action)
        lastAction = CodexBaseActionPolicy.unavailableDiagnostic(for: action)
            ?? "\(action.displayName) · Unavailable"
        logger.info("action=\(action.displayName, privacy: .public) result=unavailable")
    }

    private func requestCodexWakeConfirmation() {
        lastAction = "置前 Codex · 正在确认"
        Task { [weak self] in
            guard let self else { return }
            let result = await automation.wakeCodexAndConfirm()
            guard !Task.isCancelled else { return }
            lastAction = result.diagnostic
            logger.info("action=wake result=\(result == .foregroundConfirmed ? "confirmed" : "unavailable", privacy: .public)")
            refreshRuntimeState()
        }
    }

    private func executeCommandIntent(_ intent: CommandIntent) {
        guard let action = intent.codexCommandAction else {
            // start/stopPushToTalk are handled before this method and retain
            // their dedicated, exact dictation-state confirmation path.
            lastAction = "Command · 不可用"
            return
        }
        executeCodexSemanticRequest(
            .command(action),
            displayName: intent.displayName,
            logValue: intent.rawValue
        )
    }

    private func executeRunningIntent(_ intent: RunningIntent) {
        executeCodexSemanticRequest(
            .running(intent.codexRunningAction),
            displayName: intent.displayName,
            logValue: intent.rawValue
        )
    }

    /// Resolves the closed semantic policy immediately before dispatch.  The
    /// keybinding service rereads the file here; provisioning at launch is not
    /// treated as fresh evidence when another process may have changed it.
    private func executeCodexSemanticRequest(
        _ request: CodexActionRequest,
        displayName: String,
        logValue: String
    ) {
        let capability = actionSemantics.capability(for: request)
        let availability: CodexKeybindingAvailability
        let evidence: CodexActionEvidence?
        switch capability {
        case let .available(route, requiredEvidence):
            guard case let .fixedKeybinding(semanticAction) = route else {
                lastAction = "\(displayName) · 不可用（无精确 AX 执行器）"
                logger.info(
                    "semantic action=\(logValue, privacy: .public) result=unavailable-no-exact-adapter"
                )
                return
            }
            availability = keybindingConfigurationService.bindingAvailability(
                for: semanticAction
            )
            evidence = availability == .available ? requiredEvidence : nil
        case .unavailable:
            availability = .unavailable
            evidence = nil
        }

        switch actionSemantics.resolve(request, evidence: evidence) {
        case let .authorized(route, _):
            guard case .fixedKeybinding(.forkThread) = route else {
                // No other fixed-key route is currently admitted by the
                // policy. Keep this guard fail-closed if the catalog evolves.
                lastAction = "\(displayName) · 不可用（未接线语义路由）"
                logger.error(
                    "semantic action=\(logValue, privacy: .public) result=blocked-unwired-route"
                )
                return
            }
            let result = automation.executeForkThread(
                bindingAvailability: availability
            )
            lastAction = "\(displayName) · \(result.diagnostic)"
            logger.info(
                "semantic action=\(logValue, privacy: .public) result=\(result == .shortcutPostedWithoutUIConfirmation ? "posted-unconfirmed" : "unavailable", privacy: .public)"
            )
        case let .unavailable(reason):
            lastAction = "\(displayName) · 不可用（\(reason.displayName)）"
            logger.info(
                "semantic action=\(logValue, privacy: .public) result=unavailable reason=\(reason.logValue, privacy: .public)"
            )
        }
    }

    private func executeActionPanelIntent(_ intent: ActionPanelIntent) {
        clearSidebarSelection()
        let request = CodexActionRequest.actionPanel(
            intent.codexActionPanelAction
        )

        // `CodexActionSemantics` is a closed, fail-closed policy.  In the
        // current macOS preview it authorizes no Y action because no adapter
        // can prove a unique AX control and a fresh post-action state change.
        // Do not route these intents through `automation.execute`: that path
        // only proves event posting, not Codex's visible result.
        switch actionSemantics.resolve(request, evidence: nil) {
        case .authorized:
            lastAction = "\(intent.displayName) · 不可用（缺少已接线 AX 适配器）"
            logger.error(
                "action-panel action=\(intent.logValue, privacy: .public) result=blocked-no-adapter"
            )
        case .unavailable:
            lastAction = "\(intent.displayName) · 不可用（未验证精确 AX 状态变化）"
            logger.info(
                "action-panel action=\(intent.logValue, privacy: .public) result=unavailable-no-verified-route"
            )
        }
    }

    private func requestSidebarSelection(
        direction: SidebarTaskDirection
    ) {
        guard sidebarTask == nil else {
            lastAction = "侧边栏候选 · 上一次移动仍在确认"
            return
        }

        sidebarRevision += 1
        let revision = sidebarRevision
        lastAction = direction == .previous
            ? "侧边栏候选 · 正在向上确认"
            : "侧边栏候选 · 正在向下确认"
        sidebarTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await automation.selectSidebarTask(
                direction: direction
            )
            guard sidebarRevision == revision else { return }
            lastAction = result.diagnostic
            sidebarTask = nil
        }
    }

    private func requestSidebarOpen() {
        guard sidebarTask == nil else { return }

        sidebarRevision += 1
        let revision = sidebarRevision
        lastAction = "打开侧边栏任务 · 正在确认"
        sidebarTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await automation.openSelectedSidebarTask()
            guard sidebarRevision == revision else { return }
            lastAction = result.diagnostic
            sidebarTask = nil
        }
    }

    private func clearSidebarSelection() {
        guard sidebarTask != nil ||
                automation.hasSidebarTaskSelection else {
            return
        }
        sidebarRevision += 1
        sidebarTask?.cancel()
        sidebarTask = nil
        automation.clearSidebarTaskSelection()
    }

    private func refreshWorkspaceCatalogIfNeeded(
        force: Bool = false
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastWorkspaceCatalogRefreshAt >= 1 else { return }
        lastWorkspaceCatalogRefreshAt = now
        guard let catalog = try? CodexWorkspaceCatalog() else {
            workspaceCatalogAvailable = false
            workspaceSlotStatuses = Array(
                repeating: .unavailable,
                count: CodexWorkspaceCatalog.agentSlotLimit
            )
            workspaceNavigator.invalidate()
            return
        }
        workspaceCatalogAvailable = true
        workspaceNavigator.replaceCatalog(catalog)
        workspaceSlotStatuses = (0..<CodexWorkspaceCatalog.agentSlotLimit).map {
            catalog.agentSlots.indices.contains($0) ? .confirmed : .unavailable
        }
    }

    private func performWorkspaceCatalog(_ intent: WorkspaceCatalogIntent) {
        guard workspaceGateIsOpen() else {
            lastAction = "Workspace Catalog · 已阻止"
            return
        }
        refreshWorkspaceCatalogIfNeeded(force: true)
        let result: CodexWorkspaceCatalogNavigator.Result
        switch intent {
        case let .moveSelection(direction):
            result = workspaceNavigator.moveSelection(direction)
        case .enterProject:
            result = workspaceNavigator.enterProject()
        case .leaveProject:
            result = workspaceNavigator.leaveProject()
        case .cycleRoot:
            result = workspaceNavigator.cycleRoot()
        }
        recordWorkspaceResult(result, operation: "catalog")
    }

    private func performRecentWorkspaceSelection(
        _ direction: SidebarTaskDirection
    ) {
        guard workspaceGateIsOpen() else {
            lastAction = "Workspace Catalog · 已阻止"
            return
        }
        refreshWorkspaceCatalogIfNeeded(force: true)
        recordWorkspaceResult(
            workspaceNavigator.moveRecentTask(direction),
            operation: direction == .previous ? "previous" : "next"
        )
    }

    private func performAgentSlotSelection(_ slot: AgentSlot) {
        guard workspaceGateIsOpen() else {
            lastAction = "Agent 槽位 \(slot.rawValue) · 已阻止"
            return
        }
        refreshWorkspaceCatalogIfNeeded(force: true)
        recordWorkspaceResult(
            workspaceNavigator.selectAgentSlot(slot),
            operation: "agent-slot"
        )
    }

    private func recordWorkspaceResult(
        _ result: CodexWorkspaceCatalogNavigator.Result,
        operation: String
    ) {
        switch result {
        case .confirmed:
            lastAction = "Workspace Catalog · 已确认"
            logger.info("workspace operation=\(operation, privacy: .public) result=selection-confirmed")
        case .unavailable:
            lastAction = "Workspace Catalog · 不可用"
            logger.info("workspace operation=\(operation, privacy: .public) result=unavailable")
        }
    }

    private func requestWorkspaceOpen(threadID: UUID) {
        guard workspaceGateIsOpen(), sidebarTask == nil else {
            lastAction = "打开 Workspace 任务 · 已阻止"
            return
        }
        sidebarRevision += 1
        let revision = sidebarRevision
        lastAction = "打开 Workspace 任务 · 正在确认"
        sidebarTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await automation.openWorkspaceTask(threadID: threadID)
            guard sidebarRevision == revision else { return }
            lastAction = result.diagnostic
            sidebarTask = nil
            clearWorkspaceSelection()
        }
    }

    private func clearWorkspaceSelection() {
        workspaceNavigator.clearSelection()
    }

    private func workspaceGateIsOpen() -> Bool {
        bridgeEnabled &&
            currentSnapshot.isConnected &&
            mappingEngine.phase == .active &&
            automation.isCodexForeground
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
        case .workspaceCatalog: "Workspace Catalog"
        case .questionAnswer: "问答导航"
        case .selectSidebarTask(let direction):
            direction == .previous ? "侧边栏上一任务" : "侧边栏下一任务"
        case .openModelPicker: "模型选择"
        case .openPreviousTask: "上一任务"
        case .openNextTask: "下一任务"
        case .selectAgentSlot(let slot): "Agent 槽位 \(slot.rawValue)"
        case .command(let intent): "Command · \(intent.rawValue)"
        case .running(let intent): "运行中 · \(intent.rawValue)"
        case .openActionPanel: "打开动作面板"
        case .closeActionPanel: "关闭动作面板"
        case .actionPanel(let intent): "动作面板 · \(intent.rawValue)"
        }
    }
}

private extension ModelControlAction {
    var displayName: String {
        switch self {
        case .adjustReasoningPower(.down): "Power -"
        case .adjustReasoningPower(.up): "Power +"
        case .selectSimpleSpeed(.standard): "Standard"
        case .selectSimpleSpeed(.fast): "Fast"
        case let .selectAdvancedTarget(target): "Advanced \(target.rawValue)"
        case let .stepAdvancedTarget(target, direction):
            "Advanced \(target.rawValue) \(direction == .up ? "上" : "下")"
        case .openModelMenu: "模型菜单"
        case .openAgentControllerSettings: "打开设置"
        }
    }
}

private extension ActionPanelIntent {
    var codexActionPanelAction: CodexActionPanelAction {
        switch self {
        case .newTask: .newTask
        case .historyBack: .historyBack
        case .historyForward: .historyForward
        case .toggleSidebar: .toggleSidebar
        case .clearComposer: .clearComposerAfterConfirmation
        case .projectContext: .projectContext
        case .requestClearComposerConfirmation:
            preconditionFailure("confirmation is a local panel transition")
        }
    }

    var displayName: String {
        switch self {
        case .newTask: "新建任务"
        case .historyBack: "历史后退"
        case .historyForward: "历史前进"
        case .toggleSidebar: "切换侧边栏"
        case .clearComposer: "清空编辑器"
        case .projectContext: "项目上下文"
        case .requestClearComposerConfirmation: "清空编辑器确认"
        }
    }

    var logValue: String {
        switch self {
        case .newTask: "new-task"
        case .historyBack: "history-back"
        case .historyForward: "history-forward"
        case .toggleSidebar: "toggle-sidebar"
        case .clearComposer: "clear-composer"
        case .projectContext: "project-context"
        case .requestClearComposerConfirmation: "clear-composer-confirmation"
        }
    }
}

private extension CommandIntent {
    var codexCommandAction: CodexCommandAction? {
        switch self {
        case .approve: .approve
        case .decline: .decline
        case .fork: .fork
        case .dispatch: .dispatch
        case .toggleFast, .startPushToTalk, .stopPushToTalk: nil
        }
    }

    var displayName: String {
        switch self {
        case .toggleFast: "切换 Fast"
        case .approve: "批准"
        case .decline: "拒绝"
        case .fork: "Fork"
        case .dispatch: "发送"
        case .startPushToTalk: "Command 语音开始"
        case .stopPushToTalk: "Command 语音结束"
        }
    }
}

private extension RunningIntent {
    var codexRunningAction: CodexRunningAction {
        switch self {
        case .steer: .steer
        case .queue: .queue
        case .stop: .stop
        case .fork: .fork
        }
    }

    var displayName: String {
        switch self {
        case .steer: "Steer"
        case .queue: "Queue"
        case .stop: "停止运行"
        case .fork: "Fork"
        }
    }
}

private extension CodexActionUnavailableReason {
    var displayName: String {
        switch self {
        case .noVerifiedRoute: "无已验证路径"
        case .evidenceNotConfirmed: "证据未确认"
        }
    }

    var logValue: String {
        switch self {
        case .noVerifiedRoute: "no-verified-route"
        case .evidenceNotConfirmed: "evidence-not-confirmed"
        }
    }
}

private final class UserDefaultsModelControlModeStore: ModelControlModeStoring {
    private static let key = "modelControlMode"
    private let defaults: UserDefaults

    var modelControlMode: ModelControlMode {
        didSet {
            defaults.set(modelControlMode.rawValue, forKey: Self.key)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        modelControlMode = ModelControlMode(
            rawValue: defaults.string(forKey: Self.key) ?? ""
        ) ?? .simple
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
