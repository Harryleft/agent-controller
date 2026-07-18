# Agent Controller 工程规则

## 平台边界

- 本仓库包含两套独立运行时：Windows WPF 在 `app/`，macOS SwiftUI/SwiftPM 在 `Package.swift` 与 `Sources/`。不要跨平台复用 XInput、WPF、`user32.dll` 或 AppKit/GameController 实现。
- Windows v0.7 的事实入口是 `public/docs/controller-command-reference-v0.7.md`；macOS 的事实入口是 `docs/macos.md`。v0.4/VHF 文件是有版本范围的历史设计或实验契约。

## macOS 修改规则

- 验证命令：`swift test`，随后 `./script/build_and_run.sh --verify`。
- 首次真机开发先运行 `./script/setup_local_signing.sh`；`.local-signing/`、`.build/`、`dist/` 与日志不得提交。
- 手柄输入必须经过 Bridge、前台 Codex 与回中门禁；断连、切走前台或关闭 Bridge 时必须排空 LT 并等待回中。
- 普通键只允许白名单动作并定向投递到已验证的 `com.openai.codex` PID；事件投递不是 UI 成功证据。
- LT 只能在当前 Codex focused/main window 中精确匹配唯一听写按钮，验证同一控件和窗口焦点后发送 Space，再以新鲜 AX 状态确认。
- 不得用全局鼠标、坐标点击、模糊 AX 标签、`AXPress` 或 `Ctrl+Shift+D` 代替 LT 确认链路。
- 若听写已由用户启动，桥接不得取得所有权；开始结果不明时保留停止清理责任，不能假报成功。

## 验收

- 单元测试只证明状态机和标签策略；实时 AX 测试默认跳过，命令见 `docs/macos.md`。
- 涉及 GameController、权限、Codex UI 或语音的修改必须做真机冒烟，并记录设备身份、权限、开始/停止确认和真实转写证据。
- Developer ID 签名、公证或 Release 未完成前，只能称 macOS 开发预览，不能称可分发正式版。
