# Agent Controller 工程规则

## 平台边界

- 本仓库包含两套独立运行时：Windows WPF 在 `app/`，macOS SwiftUI/SwiftPM 在 `Package.swift` 与 `Sources/`。不要跨平台复用 XInput、WPF、`user32.dll` 或 AppKit/GameController 实现。
- Windows v0.7 的事实入口是 `public/docs/controller-command-reference-v0.7.md`；macOS 的事实入口是 `docs/macos.md`。v0.4/VHF 文件是有版本范围的历史设计或实验契约。

## macOS 修改规则

- 验证命令：`swift test`，随后 `./script/build_and_run.sh --verify`。
- 首次真机开发先运行 `./script/setup_local_signing.sh`；`.local-signing/`、`.build/`、`dist/` 与日志不得提交。
- 当前 MVP 只有 LT 与 X：LT 通过用户已配置的豆包输入法右 Option 开始/结束语音，X 向前台 `com.openai.codex` 投递 Return。
- 手柄输入必须经过前台 Codex 与回中门禁；断连、切走前台或系统睡眠时必须释放由桥接按住的右 Option。
- 不得重新引入任务 Catalog、模型控制、F18/keybindings 写入、Codex AX 听写、HUD 或可配置按键，除非有新的已验收功能需求。
- 键盘事件已投递不等于 Codex UI 已完成；真实提交仍由用户在界面确认。

## 验收

- 单元测试只证明状态机和投递结果；涉及 GameController、权限、Codex UI 或语音的修改必须做真机冒烟，并记录真实转写与提交证据。
- Developer ID 签名、公证或 Release 未完成前，只能称 macOS 开发预览，不能称可分发正式版。
