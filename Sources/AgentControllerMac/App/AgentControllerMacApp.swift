import AppKit
import SwiftUI

@main
struct AgentControllerMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Agent Controller", id: "main") {
            ControllerHUDHost(model: model)
                .frame(minWidth: 720, idealWidth: 780, minHeight: 620)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(model: model)
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
