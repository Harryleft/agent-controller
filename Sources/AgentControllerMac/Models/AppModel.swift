import AgentControllerCore
import AgentControllerPlatform
import Combine
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status = "等待手柄连接"

    private let controllerService = GameControllerService()
    private let automation = CodexMacAutomation()
    private var mappingEngine = ControllerMappingEngine()
    private var currentSnapshot = ControllerSnapshot.disconnected
    private var pendingSubmit: Task<Void, Never>?
    private var timer: Timer?
    private let logger = Logger(
        subsystem: "com.harryleft.agent-controller.macos",
        category: "Bridge"
    )

    init() {
        controllerService.onSnapshot = { [weak self] snapshot in
            self?.currentSnapshot = snapshot
            self?.process(snapshot)
        }
        controllerService.onDeviceChange = { [weak self] name in
            self?.status = name.map { "已连接：\($0)" } ?? "手柄已断开"
        }
        controllerService.onSystemPowerBoundary = { [weak self] _ in
            self?.process(.disconnected)
        }
        controllerService.start()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.processForegroundGate() }
        }
    }

    private func processForegroundGate() {
        process(currentSnapshot)
    }

    private func process(_ snapshot: ControllerSnapshot) {
        let actions = mappingEngine.update(
            snapshot: snapshot,
            bridgeEnabled: true,
            codexIsForeground: automation.isCodexForeground
        )
        for action in actions { execute(action) }
    }

    private func execute(_ action: ControllerAction) {
        switch action {
        case .startVoice:
            pendingSubmit?.cancel()
            setVoice(recording: true)
        case .stopVoice:
            pendingSubmit?.cancel()
            setVoice(recording: false)
        case .submit:
            pendingSubmit?.cancel()
            submit()
        case .stopVoiceAndSubmit:
            pendingSubmit?.cancel()
            let result = setVoice(recording: false)
            guard result.applied else { return }
            status = "语音结束，正在提交"
            pendingSubmit = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled,
                      let self,
                      currentSnapshot.isConnected,
                      automation.isCodexForeground else { return }
                submit()
            }
        }
    }

    @discardableResult
    private func setVoice(
        recording: Bool
    ) -> DoubaoVoiceShortcutAutomationResult {
        let result = automation.setDoubaoVoiceShortcut(recording: recording)
        status = recording ? "豆包语音：\(result.diagnostic)" : "结束语音：\(result.diagnostic)"
        logger.info("voice action=\(recording ? "start" : "stop", privacy: .public) result=\(result.logValue, privacy: .public)")
        return result
    }

    private func submit() {
        let result = automation.submit()
        status = result.diagnostic
        logger.info("submit result=\(result.logValue, privacy: .public)")
        pendingSubmit = nil
    }
}
