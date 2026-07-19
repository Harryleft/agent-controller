import AgentControllerCore
import SwiftUI

/// Keeps the HUD lifecycle beside the main SwiftUI scene without adding HUD
/// concerns to AppModel. The model remains the sole source of runtime gates.
struct ControllerHUDHost: View {
    @ObservedObject var model: AppModel
    @StateObject private var hud = ControllerHUDPanelController()

    var body: some View {
        ContentView(model: model)
            .onAppear {
                refreshHUD(runtimeState)
            }
            .onChange(of: runtimeState) { _, state in
                refreshHUD(state)
            }
            .onDisappear {
                hud.hide()
            }
    }

    private var runtimeState: ControllerHUDRuntimeState {
        ControllerHUDRuntimeState(
            bridgeEnabled: model.bridgeEnabled,
            codexForeground: model.codexForeground,
            controllerConnected: model.isControllerConnected
        )
    }

    private func refreshHUD(_ state: ControllerHUDRuntimeState) {
        hud.update(runtimeState: state)
    }
}
