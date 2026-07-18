import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statusGrid
                controllerCard
                permissionCard
                mappingCard
                footer
            }
            .padding(24)
        }
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Agent Controller")
                    .font(.largeTitle.bold())
                Text("Xbox 手柄驱动 macOS Codex")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("桥接", isOn: $model.bridgeEnabled)
                .toggleStyle(.switch)
                .controlSize(.large)
        }
    }

    private var statusGrid: some View {
        HStack(spacing: 10) {
            StatusPill(
                title: "手柄",
                value: model.isControllerConnected ? "已连接" : "未连接",
                color: model.isControllerConnected ? .green : .secondary)
            StatusPill(
                title: "Codex",
                value: model.codexForeground ? "前台" :
                    (model.codexRunning ? "后台" : "未运行"),
                color: model.codexForeground ? .green : .orange)
            StatusPill(
                title: "权限",
                value: model.canPostEvents && model.accessibilityTrusted
                    ? "已就绪" : "未完整授权",
                color: model.canPostEvents && model.accessibilityTrusted
                    ? .green : .red)
            StatusPill(
                title: "会话",
                value: model.sessionPhase,
                color: model.sessionPhase == "Active" ? .green : .secondary)
        }
    }

    private var controllerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("设备", value: model.controllerName)
                LabeledContent(
                    "兼容层",
                    value: model.controllerCompatibility)
                LabeledContent(
                    "Codex 快捷键",
                    value: model.keybindingStatus)
                Divider()
                Text("实时输入")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(model.liveInput)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("控制器", systemImage: "gamecontroller.fill")
        }
    }

    private var permissionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    "仅当前台是 Codex 时控制",
                    isOn: $model.onlyWhenCodexForeground)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.canPostEvents
                            ? "事件投递已授权"
                            : "需要事件投递权限")
                        Text(model.accessibilityTrusted
                            ? "辅助功能已授权（LT 语音必需）"
                            : "需要辅助功能权限（LT 语音必需）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("请求控制权限") {
                        model.requestSystemPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("置前 Codex") {
                        model.focusCodex()
                    }
                }
            }
            .padding(4)
        } label: {
            Label("安全门禁", systemImage: "lock.shield")
        }
    }

    private var mappingCard: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                MappingRow(control: "Menu / ☰", action: "置前 Codex")
                MappingRow(control: "A", action: "打开已确认的侧边栏任务 / 确认焦点项")
                MappingRow(control: "X", action: "提交输入")
                MappingRow(control: "Y", action: "新建任务")
                MappingRow(control: "B", action: "短按取消；按住 3 秒停止")
                MappingRow(control: "LT", action: "按住说话")
                MappingRow(control: "R3", action: "模型选择器")
                MappingRow(control: "十字键 / 左摇杆", action: "普通四向导航")
                MappingRow(control: "LB + ↑ / ↓", action: "选择可见侧边栏任务（不打开）")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("macOS 基础映射", systemImage: "keyboard")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
            Text(model.lastAction)
                .lineLimit(1)
            Spacer()
            Text("断连或切走前台后，需先回中才能恢复")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

private struct StatusPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(value)
                    .font(.callout.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct MappingRow: View {
    let control: String
    let action: String

    var body: some View {
        GridRow {
            Text(control)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(minWidth: 150, alignment: .leading)
            Text(action)
                .foregroundStyle(.secondary)
        }
    }
}
