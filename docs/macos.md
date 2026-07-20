# macOS MVP（开发预览）

macOS 端是独立的 SwiftPM/SwiftUI 小型桥接，只保留两个已在真机验收的功能：

| Xbox 输入 | 动作 |
| --- | --- |
| LT | 第一次按下按住右 Option，调用用户已配置的豆包输入法语音；第二次按下释放右 Option。 |
| X | 语音空闲时向前台 Codex 投递 Return；语音仍活动时，先释放右 Option、等待 350ms，再投递 Return。 |

应用不读取或记录 Codex 输入框正文，也不再维护 F18、`keybindings.json`、Codex 听写按钮、任务导航、模型控制、HUD 或设置页。

## 运行边界

- 支持 macOS 14+、Codex 桌面版与 `GCExtendedGamepad`；当前已验证 Xbox Wireless Controller。
- 只有 Codex 位于前台、手柄连接且已回中时，LT/X 才生效。
- 断连、Codex 切出前台或系统睡眠时，桥接会释放其按住的右 Option；恢复后必须先回中。
- LT 需要事件投递与辅助功能授权；Codex/豆包输入法仍需自行具备麦克风权限。
- Return 的投递只证明事件已发送，是否真正提交以用户在 Codex 界面中的观察为准。

## 构建验证与真机验收

```bash
cd agent-controller
./script/setup_local_signing.sh
swift test
./script/build_and_run.sh --verify
```

构建产物为 `dist/AgentControllerMac.app`，仅使用本地开发签名，未做 Developer ID 签名或公证。

`--verify` 只验证 Swift 构建、应用签名、手柄声明和进程启动；它不证明辅助功能权限、手柄输入、豆包转写或 Codex 提交已经成功。若只需不重启 GUI 的机械验证，运行：

```bash
./script/verify_unattended.sh --no-relaunch
```

需要收集不含 Codex 正文的手柄运行证据时，可运行 `./script/verify_unattended.sh --collect-logs 30`。该日志仍不能替代界面中的真实转写与提交确认。

真机验收顺序：连接手柄并回中；LT 开始说话；再次 LT 或直接 X 结束语音；确认豆包文本进入 Codex 输入框；按 X 并在界面确认消息已提交。
