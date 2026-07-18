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
| 2026-07-18 | vendor `Xbox Wireless Controller`、product `Xbox One`、`GCXboxGamepad=true` | 连接与回中、LT 按住开始/松开结束、真实说话转写、A 确认；LB + 上/下选择多个可见任务、A 对三个不同脱敏任务身份完成深链打开与 AX 确认；松开 LB 后普通方向导航正常 |

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
| Menu / ☰ | 启动或置前 Codex；仅在同一 Codex PID 连续两次成为前台后报告“已确认” |
| A | 若有已确认的侧边栏候选，则通过唯一 UUID 的 `codex://threads/<uuid>` 深链打开并等待确认；否则确认当前焦点项（Return） |
| X | 提交当前输入；当前缺少不读取正文的精确 UI 回执，明确显示 Unavailable，且不投递 Return |
| Y | 新建任务（Command + N） |
| B 短按 | 取消或关闭当前界面；当前缺少精确 UI 回执，明确显示 Unavailable，且不投递 Escape |
| B 按住 3 秒 | 停止当前任务；当前缺少精确 UI 回执，明确显示 Unavailable，且不投递 Escape |
| LT 按住 / 松开 | 精确定位并聚焦当前主窗口的听写控件，向 Codex PID 发送 Space，并确认开始 / 结束 |
| R3 | 打开模型选择器（Control + Shift + M） |
| 左摇杆 ↑ / ↓ | 移动应用自有的 Workspace Catalog 选择；只保存无标题的 UUID 候选，不打开任务 |
| 左摇杆 ← / → | 离开 / 进入当前 Catalog 中已选择的项目目录；没有已选择项目则不可用 |
| L3 | 循环四个根目录：置顶任务、置顶项目、项目、无项目任务 |
| 十字键 ↑ / ↓ | 问答上一条 / 下一条意图；当前没有安全且可确认的执行器，因此明确显示为不可用，不投递方向键 |
| 十字键 ← / → | 与左摇杆一致，离开 / 进入当前 Catalog 中已选择的项目目录；不投递方向键 |
| LB / RB 短按 | 在 Catalog 的无标题最近任务列表中选择上一条 / 下一条；不打开任务 |
| 按住 LB + 十字键四向 / View / Menu | 选择 Agent 槽位 1–6；HUD 仅显示槽位状态，绝不显示任务标题 |

断连、桥接关闭或前台切换会暂停会话；重新接管前必须让按钮、摇杆和扳机回中，避免连接瞬间误触。LT 录音期间切走前台后，应用保留清理责任；返回 Codex 时会优先尝试结束听写。

## Workspace Catalog 选择合同

1. 左摇杆、LB/RB 和 Agent 槽位只操作应用内存中的 Catalog 选择，Catalog 只保留 UUID 与更新时间，不保存标题、提示词、回复或路径。选择成功仅表示本地状态已确认，绝不表示 Codex 已切换任务。
2. 项目根目录与置顶目录只在本地全局状态有完整字段证据时提供；缺字段、空目录、无当前项目或越界槽位均返回不可用，不猜测项目归属。
3. A 仅对当前 Catalog 的任务 UUID 启动打开链路。自动化先重新读取当前前台 Codex 的可见 AX 侧边栏；目标 UUID 必须通过全局唯一的精确标题身份解析。没有唯一匹配、AX 树不完整、窗口/PID 改变或焦点失败时一律拒绝。
4. 只有上述重新解析成功后才允许 `codex://threads/<uuid>`；系统接收深链不算成功。同一任务身份必须在新鲜 AX 工具栏中连续两次出现，才报告“已打开并确认”。
5. Bridge 关闭、手柄断连、Codex 切出前台、未回中或其它非 Catalog 动作都会清除选择；恢复后必须先回中。HUD 仅投影 1–6 槽位的确认/不可用/未知状态，不泄露标题。
6. Base D-pad 上下是单独的问答导航意图；在专用执行器能给出可观察确认之前，它始终不可用，不能复用左摇杆 Catalog 路径或退化为普通方向键。

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
RUN_LIVE_CODEX_SIDEBAR_TEST=1 \
  swift test --filter LiveCodexSidebarTests/testCurrentCodexSidebarFocusRoundTrip
# 会依次打开两个不同任务；仅在用户明确允许切换当前 Codex 任务时运行。
RUN_LIVE_CODEX_SIDEBAR_OPEN_TEST=1 \
  swift test --filter LiveCodexSidebarTests/testCurrentCodexSidebarOpenAndConfirm
```

实时测试要求 Codex 在前台、两类 Agent Controller 权限与 Codex 麦克风权限就绪，并应在可丢弃的 composer 中运行。听写测试验证当前 Codex AX 开始/停止回路，不经过物理手柄，也不会主动说话，所以不能替代 LT 真实转写验收。侧边栏 focus 测试只移动候选；open 测试会打开任务，且只有同一身份连续两次 AX 回读成功才通过。

查看结构化日志：

```bash
./script/build_and_run.sh --telemetry
```

关键证据包括 `connected ... xboxProfile=true`、`permission postEvent=true accessibility=true`，以及 `dictation target=recording result=confirmed` / `dictation target=idle result=confirmed`。侧边栏操作应出现 `sidebar operation=select result=selection-confirmed` 或 `sidebar operation=open result=open-confirmed`，其中 `task` 仅为 UUID 派生短哈希。日志中的 `posted` 只表示事件路径执行过，不等于听写或任务打开已确认。

### 无人值守验证与休眠恢复边界

在不接触物理手柄的 CI、离席或开发机验证中，运行：

```bash
./script/verify_unattended.sh
```

该入口顺序执行 `swift test`、`./script/build_and_run.sh --verify` 与 `git diff --check`。核心测试已覆盖：600 秒闲置后的状态不合成新按键、断连/重连时按住按钮必须先回中、LT 在断连或关闭 Bridge 时只产生一次停止清理，以及超过 60 秒未收到新 GameController 快照时强制重新回中。最后一项覆盖“无线手柄静默休眠但系统未发断连通知”的保守路径：首次恢复按键会被吞掉，松开后才重新 Active。它们只验证确定性的快照状态机，不能证明 macOS 从物理 Xbox 手柄唤醒后仍会发送通知、TCC 授权仍有效、或 Codex UI 仍接受动作。

需要在用户在场时收集短期运行证据，可使用（默认 30 秒，最多 120 秒）：

```bash
./script/verify_unattended.sh --collect-logs 30
```

该收集器不伪造 GameController 输入、不阻止系统休眠、不删除用户数据；只输出设备连接、Bridge phase/权限 gate 与 action result 的摘要。它主动过滤原始输入与 Codex 内容，不读取或保存 prompt/reply。零条记录只表示该时间窗没有观测到合格事件，不能视为物理验收通过。

系统休眠、蓝牙重连、手柄固件与 TCC 都在自动测试边界之外。因此用户回来后，在 5 分钟内用已连接的 Xbox 完成以下清单：

1. 观察应用先进入“等待回中”；先故意按住 A 或 LT，再全部松开，确认没有自动执行动作，回中后才恢复 Active。
2. 拔掉并重新连接手柄；确认断连期间没有动作，重连后再次要求回中。
3. 按住 LT 使听写开始后断连或切出 Codex；恢复条件后确认听写被清理，且没有重复停止或遗留录音。
4. 恢复辅助功能/事件投递与 Codex 麦克风权限后，完成一次 LT 说话、松开、真实转写和停止按钮回读；`posted` 不是成功证据。
5. 检查短期摘要中有实际的 `connected`、`phase`、权限 gate 与相应 action result；没有这些记录时标注为“未完成物理验收”，不要以自动测试替代。

## 已知边界

- Codex 改动可访问性名称、角色、窗口结构或焦点行为时，LT 会失效并返回未确认；不得新增模糊匹配或坐标点击来掩盖兼容性破坏。
- X 提交、B 取消/停止仍没有精确 UI 结果回读；当前一律显示 Unavailable，不投递 Return/Escape。后续适配器必须在不读取或记录 composer 正文的前提下，证明同一窗口中的新鲜状态变化。
- 侧边栏任务选择依赖当前 Codex AX 树、标题与只读 session index 的唯一关联；同名、缺失或不唯一时宁可拒绝，不能用模糊标题匹配、坐标点击或任意深链兜底。
- GameController 能识别设备不等于 Menu、Home、Share、背键与震动在每个型号上一致；Share 和背键是可选增强能力。
- 自动化仅允许目标为前台 `com.openai.codex`。不要去掉此前台、同 PID、同窗口和精确控件限制。
- 公开分发仍缺 Developer ID 签名、公证、安装与升级流程；本地稳定签名不能分发。

## 真机验收清单

1. 冷启动时按住任意按钮连接手柄，确认不会触发动作；全部回中后才进入 Active。
2. 逐一验证 A/B/X/Y、Menu、R3、十字键、左摇杆与 LT；LT 按住后应出现停止按钮，说一句话，松开后应恢复开始按钮并写入转写。
3. 以左摇杆移动 Catalog 选择、进出一个项目并循环四根目录；分别短按 LB/RB 及按住 LB 选择槽位 1–6，确认 HUD 没有显示任务标题。Base D-pad 上/下应只报告不可用，不能改变 Catalog 选择或投递方向键。
4. 对已确认 Catalog 任务按 A，确认 Codex 打开唯一匹配的任务，且日志出现 `open-confirmed`；制造同名、无匹配或候选失效情形时，确认 A 不会打开错误任务。
5. 撤销辅助功能权限后按 LT，确认应用报告未确认；普通快捷键的授权状态应独立显示。
6. 撤销 Codex 麦克风权限，确认问题被识别为 Codex 录音前提，而不是误导用户反复授权 Agent Controller。
7. LT 按住期间断开手柄，确认应用暂停并在条件恢复后清理听写状态；Catalog 已有候选时断连、关闭 Bridge 或切出 Codex，确认候选被清除且恢复后必须回中。
8. 切换到其他前台应用，确认除 Menu 置前外的输入被阻止，且事件不会落入新前台应用。
9. 新增型号、USB 连接、Share 或背键支持时，单独记录 GameController 身份与端到端证据，不能沿用 2026-07-18 的单设备结论。
