import SwiftUI
import AgentControllerCore

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("桥接") {
                Toggle("启用手柄桥接", isOn: $model.bridgeEnabled)
                Toggle(
                    "仅当前台是 Codex 时控制",
                    isOn: $model.onlyWhenCodexForeground)
            }

            Section("摇杆") {
                HStack {
                    Slider(value: $model.deadZone, in: 0.12...0.55)
                    Text(model.deadZone, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                Text("增大死区可以抑制老旧手柄的摇杆漂移。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("模型控制") {
                Picker("模式", selection: $model.modelControlMode) {
                    Text("Simple").tag(ModelControlMode.simple)
                    Text("Advanced").tag(ModelControlMode.advanced)
                }
                .pickerStyle(.segmented)
                Text("Simple 使用固定 F13/F14/F15/F16；每个快捷键单独校验。Advanced 在当前 Codex UI 无法精确验证时会保持 Unavailable。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.modelControlStatus)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 360)
        .padding()
    }
}
