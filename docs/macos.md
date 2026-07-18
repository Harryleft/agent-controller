# macOS v0.1.0（开发预览）

macOS 端是独立的原生 SwiftUI 实现，不尝试复用 Windows 的 WPF、XInput 或 `user32.dll` 运行时。两条输入链路刻意分开：

- 普通动作：`Xbox 手柄 → GameController.framework → 会话与前台门禁 → 定向 Quartz 键盘事件 → Codex`；
- LT 听写：`Xbox 手柄 → 门禁 → 当前 Codex 主窗口的精确 AX 听写控件 → 聚焦与同窗复核 → 定向 Space → 新鲜 AX 状态确认`。

第二条链路的成功标准是 Codex 可访问性状态真的变化，不是“键盘事件已经构造或投递”。

## 系统与设备

- macOS 14 或更高版本；
- 已安装 Codex 桌面版（bundle ID：`com.openai.codex`）；
- Apple GameController 框架可识别的 `GCExtendedGamepad`；
- 使用 LT 听写时，Codex 自身还要有麦克风权限和可用麦克风。

Apple 在 2026-01-19 更新的兼容清单包括：

- Xbox Wireless Controller（蓝牙版，Model 1708）；
- Xbox Series X / Series S 无线控制器；
- Xbox Elite Wireless Controller Series 2；
- Xbox Adaptive Controller。

参考：[Apple 支持的 Xbox 控制器](https://support.apple.com/zh-cn/111101) 与 [在 Mac 上连接游戏控制器](https://support.apple.com/guide/games/connect-a-game-controller-devf8cec167c/mac)。这份清单表示平台兼容范围，不等于 Agent Controller 已逐型号验收。未列出的 Xbox 布局手柄只要提供 `GCExtendedGamepad`，也会以“标准扩展手柄”模式接入，但必须单独真机确认。

### 已验证硬件

| 日期 | GameController 识别 | 已验证范围 |
| --- | --- | --- |
| 2026-07-18 | vendor `Xbox Wireless Controller`、product `Xbox One`、`GCXboxGamepad=true` | 连接与回中、LT 按住开始/松开结束、真实说话转写、A 确认 |

`productCategory` 是系统暴露的分类字符串，不足以反推精确硬件型号或代次；因此不能把本次记录扩大成 Model 1708、Series、Elite、USB 等未观察结论。

## 构建与运行

```bash
cd agent-controller
./script/setup_local_signing.sh
swift test
./script/build_and_run.sh --verify
```

`setup_local_signing.sh` 首次创建项目专用的稳定本地身份，后续可幂等重复执行。构建脚本把 SwiftPM 可执行文件封装为 `dist/AgentControllerMac.app`，签名、校验并启动。开发预览尚未使用 Developer ID Application 签名、Hardened Runtime、公证或 Release 分发。

### 为什么需要稳定本地签名

macOS 按应用代码签名身份追踪事件投递和辅助功能授权。ad-hoc 签名依赖单次构建的 `cdhash`；重建后可能被 TCC 当作新应用，造成“代码没变但权限失效”。

项目自签名身份和随机 keychain 密码只保存在 gitignored 的 `.local-signing/`。私钥源文件与 P12 只存在于创建过程的临时目录；签名时才临时加入用户 keychain 搜索列表，退出后恢复。它不会写系统级信任，也不能替代用于公开分发的 Developer ID 身份与公证。

## 首次授权

Agent Controller 不采集音频；真正录音的是 Codex。权限分工如下：

1. 在 Agent Controller 中点击“请求控制权限”，授予事件投递；
2. 打开“系统设置 → 隐私与安全性 → 辅助功能”，允许 `AgentControllerMac`；
3. 打开“系统设置 → 隐私与安全性 → 麦克风”，确认 Codex 已获授权；
4. 重新启动 Agent Controller，并保持“仅当前台是 Codex 时控制”开启。

从 ad-hoc 构建迁移到稳定签名时，旧授权不会自动继承。先退出旧实例，移除或关闭辅助功能中的旧条目，再从稳定签名后的 app 重新请求权限。

`CGPreflightPostEventAccess` 只能证明当前授权状态；`CGEvent.postToPid` 没有逐事件交付回执。因此普通快捷键只能报告“已按白名单向已验证 Codex PID 投递”，不能证明 UI 已执行动作。LT 额外读取可访问性状态，只有状态切换才报告成功。

缺少权限、桥接关闭、Codex 不在前台，或手柄连接后尚未回中时，应用会吞掉输入，不报告成功。

## 当前映射

| Xbox 输入 | macOS Codex 动作 |
| --- | --- |
| Menu / ☰ | 启动或置前 Codex |
| A | 确认 / 打开当前焦点项（Return） |
| X | 提交输入（Return；依赖 Codex 的 Enter 发送设置） |
| Y | 新建任务（Command + N） |
| B 短按 | 取消或关闭当前界面（Escape） |
| B 按住 3 秒 | 停止当前任务（Escape，带长按门槛） |
| LT 按住 / 松开 | 精确定位并聚焦当前主窗口的听写控件，向 Codex PID 发送 Space，并确认开始 / 结束 |
| R3 | 打开模型选择器（Control + Shift + M） |
| 十字键或左摇杆 | 向当前 Codex 控件发送方向键 |

断连、桥接关闭或前台切换会暂停会话；重新接管前必须让按钮、摇杆和扳机回中，避免连接瞬间误触。LT 录音期间切走前台后，应用保留清理责任；返回 Codex 时会优先尝试结束听写。

## LT 听写确认合同

1. 只在当前前台 Codex 的 focused/main AXWindow 内检索唯一、可用、尺寸合理的 AXButton。
2. 只接受精确标签：开始为 `Dictate`、`听写`、`聽寫`；停止为 `Stop dictation`、`Stop listening`、`Stop recording`、`停止听写`、`停止聽寫`、`停止口述`、`停止录音`。模糊匹配、多控件、遍历不完整都会拒绝执行。
3. 先设置准确控件的 AX focus，等待 30 ms 让 Electron 传播焦点，再确认 focused element 与 focused window 都仍是原目标。
4. 只向已验证的 Codex PID 发送 Space；不使用全局鼠标、坐标点击、`AXPress` 或 `Ctrl+Shift+D`。
5. 每轮轮询都重新创建 AX application/root。开始只接受“唯一停止按钮出现”；结束只接受“唯一开始按钮连续两次出现”。转写过渡期既不算成功也不算失败，最长等待 6 秒。
6. 如果听写本来就由用户手动启动，桥接不取得所有权，LT 松开不会替用户停止。若桥接可能已经启动但确认超时，则保留清理责任并重试停止，避免遗留持续录音。

当前 Codex 的 Electron AXButton 对 `AXPress` 返回成功但不会触发 React 处理器；向 PID 定向投递鼠标事件也不会触发。全局鼠标点击虽可能生效，但会引入坐标和跨应用误触风险，已明确排除。

## 自动测试与诊断

常规测试不会操纵当前 Codex；实时测试默认跳过：

```bash
swift test
RUN_LIVE_CODEX_DICTATION_TEST=1 \
  swift test --filter LiveCodexDictationTests/testCurrentCodexDictationRoundTrip
```

实时测试要求 Codex 在前台、两类 Agent Controller 权限与 Codex 麦克风权限就绪，并应在可丢弃的 composer 中运行。它验证当前 Codex AX 开始/停止回路，不经过物理手柄，也不会主动说话，所以不能替代 LT 真实转写验收。

查看结构化日志：

```bash
./script/build_and_run.sh --telemetry
```

关键证据包括 `connected ... xboxProfile=true`、`permission postEvent=true accessibility=true`，以及 `dictation target=recording result=confirmed` / `dictation target=idle result=confirmed`。日志中的 `posted` 只表示事件路径执行过，不等于听写已确认。

## 已知边界

- Codex 改动可访问性名称、角色、窗口结构或焦点行为时，LT 会失效并返回未确认；不得新增模糊匹配或坐标点击来掩盖兼容性破坏。
- 普通动作没有 UI 结果回读。Codex 更新或用户改键后，事件可能被目标进程忽略；尤其 X 依赖当前 Enter 发送设置。
- GameController 能识别设备不等于 Menu、Home、Share、背键与震动在每个型号上一致；Share 和背键是可选增强能力。
- 自动化仅允许目标为前台 `com.openai.codex`。不要去掉此前台、同 PID、同窗口和精确控件限制。
- 公开分发仍缺 Developer ID 签名、公证、安装与升级流程；本地稳定签名不能分发。

## 真机验收清单

1. 冷启动时按住任意按钮连接手柄，确认不会触发动作；全部回中后才进入 Active。
2. 逐一验证 A/B/X/Y、Menu、R3、十字键、左摇杆与 LT；LT 按住后应出现停止按钮，说一句话，松开后应恢复开始按钮并写入转写。
3. 撤销辅助功能权限后按 LT，确认应用报告未确认；普通快捷键的授权状态应独立显示。
4. 撤销 Codex 麦克风权限，确认问题被识别为 Codex 录音前提，而不是误导用户反复授权 Agent Controller。
5. LT 按住期间断开手柄，确认应用暂停并在条件恢复后清理听写状态。
6. 切换到其他前台应用，确认除 Menu 置前外的输入被阻止，且事件不会落入新前台应用。
7. 新增型号、USB 连接、Share 或背键支持时，单独记录 GameController 身份与端到端证据，不能沿用 2026-07-18 的单设备结论。
