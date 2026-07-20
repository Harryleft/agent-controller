import AppKit
import SwiftUI

@main
struct AgentControllerMacApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Agent Controller", systemImage: "gamecontroller") {
            Text(model.status)
            Divider()
            Button("退出") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}
