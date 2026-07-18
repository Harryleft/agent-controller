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

应用包同时声明 `GCSupportsControllerUserInteraction=true` 与
`GCSupportedGameControllers/ProfileName=ExtendedGamepad`。这使打包产物与
实际只接入 `GCExtendedGamepad` 的运行时合同一致；构建验收会直接检查这两个
Info.plist 键，不能只靠源码注释或连接成功来推断声明正确。

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
| A | 仅打开已确认的 Catalog / 侧边栏任务候选并等待新鲜 AX 确认；没有候选时明确显示 Unavailable，不投递 Return |
| X | 仅在 `composer.submit` 的固定 F18 绑定无冲突、当前前台 Codex 的同一 focused/main 窗口内存在唯一、已聚焦、可编辑的 `AXTextArea` 且 `AXNumberOfCharacters > 0` 时提交；三个阶段必须是同一 AXTextArea identity，投递仅定向该 PID。随后同一 PID/窗口/元素的 composer 必须变为 `0`，才显示“Composer 已清空（已确认）”；这不是 turn 完成。空、歧义、元素焦点或窗口漂移、权限或绑定冲突都显示 Unavailable 且不投递。 |
| Y | 打开本地 Action 层；六项 Codex 动作当前都因缺少精确 AX 回执而显示 Unavailable，不投递快捷键 |
| B 短按 | 取消或关闭当前界面；当前缺少精确 UI 回执，明确显示 Unavailable，且不投递 Escape |
| B 按住 3 秒 | 停止当前任务；当前缺少精确 UI 回执，明确显示 Unavailable，且不投递 Escape |
| LT 按住 / 松开 | 精确定位并聚焦当前主窗口的听写控件，向 Codex PID 发送 Space，并确认开始 / 结束 |
| 右摇杆（Simple） | 左/右尝试降低/提高 reasoning；下尝试 Fast；仅在固定 F13/F14/F16 绑定实时可用时定向投递，仍显示“未确认 Codex UI”；上（Standard）当前 Unavailable |
| R3 短按 / 长按 500 ms | 短按仅在 F15 绑定可用时尝试打开模型菜单并显示“未确认”；长按打开 Agent Controller 设置 |
| 左摇杆 ↑ / ↓ | 移动应用自有的 Workspace Catalog 选择；只保存无标题的 UUID 候选，不打开任务 |
| 左摇杆 ← / → | 离开 / 进入当前 Catalog 中已选择的项目目录；没有已选择项目则不可用 |
| L3 | 循环四个根目录：置顶任务、置顶项目、项目、无项目任务 |
| 十字键 ↑ / ↓ | 短按在松开后产生问答上一条 / 下一条；↑ 按住 4 秒产生问答首条，↓ 按住 3 秒产生问答末条。四种意图均无安全且可确认的执行器，明确显示 Unavailable，不投递方向键 |
| 十字键 ← / → | 与左摇杆一致，离开 / 进入当前 Catalog 中已选择的项目目录；不投递方向键 |
| LB / RB 短按 | 在 Catalog 的无标题最近任务列表中选择上一条 / 下一条；不打开任务 |
| 按住 LB + 十字键四向 / View / Menu | 选择 Agent 槽位 1–6；HUD 仅显示槽位状态，绝不显示任务标题 |
| 按住 RB + View | 复用 LT 的精确听写开始 / 结束确认路径 |
| 按住 RB + X | 仅在 F17 Fork 绑定实时可用时定向投递；明确显示“未确认 Codex UI” |
| 按住 RB + A / B / Y / Menu | Approve / Decline / Fast / Dispatch 当前没有可验证回执，显示 Unavailable |
| RT + A | 与 RB + X 相同的 F17 Fork 路径，仍不报告 Codex 已完成 |
| RT + X / Y / 按住 B 3 秒 | Steer / Queue / Stop 当前没有可验证回执，显示 Unavailable；B 的三秒门槛仍在核心层生效 |
| LB + RB | 未定义组合，直接拒绝；必须同时松开两肩键后才恢复 |

断连、桥接关闭或前台切换会暂停会话；重新接管前必须让按钮、摇杆和扳机回中，避免连接瞬间误触。LT 录音期间切走前台后，应用保留清理责任；返回 Codex 时会优先尝试结束听写。

“已定向投递，未确认 Codex UI”不是成功状态。它只证明固定快捷键配置仍匹配且事件已发往当前前台 Codex PID；HUD 的 RB / RT 层与设置页的 Model 状态仍显示 Unavailable。Advanced 模型模式没有稳定的精确菜单状态合同，因此所有方向当前 fail-closed。

## Workspace Catalog 选择合同

1. 左摇杆、LB/RB 和 Agent 槽位只操作应用内存中的 Catalog 选择，Catalog 只保留任务 UUID、更新时间和不透明项目 ID；项目名称在解码时即丢弃，也不保存标题、提示词、回复或路径。选择结果在界面标为“仅本地”，绝不表示 Codex 已切换任务。
2. 项目根目录与置顶目录只在本地全局状态有完整字段证据时提供；缺字段、空目录、无当前项目或越界槽位均返回不可用，不猜测项目归属。
3. A 仅对当前 Catalog 的任务 UUID 启动打开链路。自动化先重新读取当前前台 Codex 的可见 AX 侧边栏；目标 UUID 必须通过全局唯一的精确标题身份解析。没有唯一匹配、AX 树不完整、窗口/PID 改变或焦点失败时一律拒绝。
4. 只有上述重新解析成功后才允许 `codex://threads/<uuid>`；系统接收深链不算成功。同一任务身份必须在新鲜 AX 工具栏中连续两次出现，才报告“已打开并确认”。
5. Bridge 关闭、手柄断连、Codex 切出前台、未回中或其它非 Catalog 动作都会清除选择；恢复后必须先回中。HUD 仅投影 1–6 槽位的“仅本地/不可用/未知”状态，不泄露标题。
6. Base D-pad 上下是单独的问答导航意图：短按仅在松开后发出上一条 / 下一条；↑ 按住 4 秒仅发出一次首条，↓ 按住 3 秒仅发出一次末条，长按绝不先发短按。方向改变、断连、Bridge/前台门禁或任何独占输入层都会清除候选；在专用执行器能给出可观察确认之前，四种意图始终不可用，不能复用左摇杆 Catalog 路径或退化为普通方向键。

## LT 听写确认合同

1. 只在当前前台 Codex 的 focused/main AXWindow 内检索唯一、可用、尺寸合理的 AXButton。
2. 只接受精确标签：开始为 `Dictate`、`听写`、`聽寫`；停止为 `Stop dictation`、`Stop listening`、`Stop recording`、`停止听写`、`停止聽寫`、`停止口述`、`停止录音`。模糊匹配、多控件、遍历不完整都会拒绝执行。
3. 先设置准确控件的 AX focus，等待 30 ms 让 Electron 传播焦点，再确认 focused element 与 focused window 都仍是原目标。
4. 只向已验证的 Codex PID 发送 Space；不使用全局鼠标、坐标点击、`AXPress` 或 `Ctrl+Shift+D`。
5. 每轮轮询都重新创建 AX application/root。开始只接受“唯一停止按钮出现”；结束只接受“唯一开始按钮连续两次出现”。转写过渡期既不算成功也不算失败，最长等待 6 秒。
6. 如果听写本来就由用户手动启动，桥接不取得所有权，LT 松开不会替用户停止。若桥接可能已经启动但确认超时，则保留清理责任并重试停止，避免遗留持续录音。

当前 Codex 的 Electron AXButton 对 `AXPress` 返回成功但不会触发 React 处理器；向 PID 定向投递鼠标事件也不会触发。全局鼠标点击虽可能生效，但会引入坐标和跨应用误触风险，已明确排除。

## X 提交确认合同

1. Agent Controller 只管理官方 `composer.submit` 的固定 `F18`。`keybindings.json` 中任何其他命令占用 F18、该命令已有其它键、或存在重复受管项，都会令 X 不可用；绝不覆盖用户冲突配置，也不回退到 Enter。调度时的检查不视为授权，实际投递前会同步重读并紧邻 `postToPid` 复核；外部进程在这个不可加锁的文件检查后仍可能改写配置，因此不能把它描述为跨进程原子保证。
2. 提交前只允许读取同一前台 `com.openai.codex` PID、focused/main window identity、唯一 focused + editable `AXTextArea` 的 role/focus/editability 与 `AXNumberOfCharacters`。不读取 `AXValue`、placeholder、标题或任何 prompt/reply，也不记录它们。
3. 提交前 `AXNumberOfCharacters` 必须大于零，并在投递前立即复核同一 PID、窗口和原 AXTextArea identity；任一空值、多个候选、非文本区、元素焦点或窗口不一致均不投递。
4. 事件仅通过 `CGEvent.postToPid` 发往已复核的 Codex PID。投递后每次轮询重建 AX root；只有同一 PID、同一窗口、同一 unique focused/editable `AXTextArea` 的字符数变为零，结果才是“Composer 已清空（已确认）”。Electron 替换元素一律 Unavailable。
5. 这个收据只证明可观察到 composer 已清空，不能证明 Codex 已开始、排队、Steer，或完成一个 turn。自动测试使用内容为空的快照和假适配器，不会读取或操作真实 Codex composer。

## 自动测试与诊断

常规测试不会操纵当前 Codex；实时测试默认跳过：

```bash
swift test
RUN_LIVE_CODEX_DICTATION_TEST=1 \
  swift test --filter LiveCodexDictationTests/testCurrentCodexDictationRoundTrip
RUN_LIVE_CODEX_SIDEBAR_TEST=1 \
  swift test --filter LiveCodexSidebarTests/testCurrentCodexSidebarFocusRoundTrip
# 会真实提交当前 composer；仅在可丢弃内容中手动启用。
RUN_LIVE_CODEX_COMPOSER_SUBMIT_TEST=1 \
  swift test --filter LiveCodexComposerSubmitTests/testCurrentCodexComposerClearsAfterFixedSubmit
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

默认入口顺序执行 `swift test`、`./script/build_and_run.sh --verify` 与 `git diff --check`，会按现有行为停止同名应用、重建 `dist/AgentControllerMac.app` 并启动验证实例。

如果不能干扰当前运行的 Agent Controller，使用：

```bash
./script/verify_unattended.sh --no-relaunch
```

该模式只执行 `swift test`、`swift build --product AgentControllerMac` 与 `git diff --check`；不会调用 `pkill`、不会创建/删除/重建 `dist/AgentControllerMac.app`，也不会启动 GUI。它不能与 `--collect-logs` 组合，也不产生物理手柄证据。

核心测试已覆盖：长时间 idle 后仍保持 Active 且下一次真实按键不被吞掉、断连/重连时按住按钮必须先回中、LT 在断连或关闭 Bridge 时只产生一次停止清理，以及 active 手柄从 `GCController.controllers()` 清单消失时即使漏掉通知也会先断连再允许候选重连。桥接还订阅 `NSWorkspace.willSleepNotification` / `didWakeNotification`：睡眠边界立即排空桥接拥有的听写和瞬态选择；唤醒递增输入 epoch，旧 handler callback 与同一 controller 的保留缓存都不能进入回中门禁，必须等待该 epoch 的真实 `GameController` value-change delivery。正常启动或明确断连后的新 attach 仍是可信设备边界，可同步提供初始快照给回中门禁。GameController 没有公开的睡眠/心跳 API；因此本桥接绝不将“60 秒没有输入事件”解释为睡眠。自动测试不操作真实睡眠，也不能证明 TCC 授权或 Codex UI 在物理唤醒后仍可用。

需要在用户在场时收集短期运行证据，可使用（默认 30 秒，最多 120 秒）：

```bash
./script/verify_unattended.sh --collect-logs 30
```

该收集器不伪造 GameController 输入、不阻止系统休眠、不删除用户数据；只输出设备连接、Bridge phase/权限 gate 与 action result 的摘要。它主动过滤原始输入与 Codex 内容，不读取或保存 prompt/reply。零条记录只表示该时间窗没有观测到合格事件，不能视为物理验收通过。

系统休眠、蓝牙重连、手柄固件与 TCC 都在自动测试边界之外。连接生命周期同时由 `GCControllerDidConnect` / `GCControllerDidDisconnect` 通知和 `GCController.controllers()` 定期清单核对处理；清单中的正常 idle 永不使 epoch 失效，也不会进入回中门禁。系统实际发出睡眠/唤醒通知时，日志只记录 `boundary`、`epoch` 与 `gate` 元数据，不记录 Codex 正文或原始输入内容。若 macOS 未发睡眠通知、手柄又仍留在清单中，公开 API 无法区分“静置”与“睡眠”，不得伪称已检测到睡眠。因此用户回来后，在 5 分钟内用已连接的 Xbox 完成以下清单：

1. 让 Mac 进入睡眠后唤醒；观察应用等待本 epoch 的真实手柄 delivery，再进入“等待回中”。先故意按住 A 或 LT，再全部松开，确认没有自动执行动作，回中后才恢复 Active。
2. 拔掉并重新连接手柄；确认断连期间没有动作，重连后再次要求回中。
3. 保持手柄完全回中并静置超过 60 秒；确认仍为 Active，随后按一次 A 或 LB，确认该真实按键未被回中门禁吞掉。
4. 按住 LT 使听写开始后断连或切出 Codex；恢复条件后确认听写被清理，且没有重复停止或遗留录音。
5. 恢复辅助功能/事件投递与 Codex 麦克风权限后，完成一次 LT 说话、松开、真实转写和停止按钮回读；`posted` 不是成功证据。
6. 检查短期摘要中有实际的 `connected`、`phase`、权限 gate 与相应 action result；没有这些记录时标注为“未完成物理验收”，不要以自动测试替代。

## 已知边界

- Codex 改动可访问性名称、角色、窗口结构或焦点行为时，LT 会失效并返回未确认；不得新增模糊匹配或坐标点击来掩盖兼容性破坏。
- B 取消/停止以及 Y Action 动作仍没有精确 UI 结果回读；当前一律显示 Unavailable，不投递 Escape/Command+N。X 只拥有上文的 F18 + composer-cleared 收据，绝不声称 turn 已完成；后续适配器必须在不读取或记录 composer 正文的前提下，证明同一窗口中的新鲜状态变化。
- 侧边栏任务选择依赖当前 Codex AX 树、标题与只读 session index 的唯一关联；同名、缺失或不唯一时宁可拒绝，不能用模糊标题匹配、坐标点击或任意深链兜底。
- GameController 能识别设备不等于 Menu、Home、Share、背键与震动在每个型号上一致；Share 和背键是可选增强能力。
- 自动化仅允许目标为前台 `com.openai.codex`。不要去掉此前台、同 PID、同窗口和精确控件限制。
- 公开分发仍缺 Developer ID 签名、公证、安装与升级流程；本地稳定签名不能分发。

## 真机验收清单

1. 冷启动时按住任意按钮连接手柄，确认不会触发动作；全部回中后才进入 Active。
2. 逐一验证 A/B/X/Y、Menu、R3、十字键、左右摇杆与 LT；A 无候选、B 与 Y 内六项必须显示 Unavailable 且不改变 Codex；X 仅在空/歧义/冲突时不投递，并在非空 composer 的同一窗口变空后显示“Composer 已清空（已确认）”，不得把它记为 turn 完成；LT 按住后应出现停止按钮，说一句话，松开后应恢复开始按钮并写入转写。
3. 以左摇杆移动 Catalog 选择、进出一个项目并循环四根目录；分别短按 LB/RB 及按住 LB 选择槽位 1–6，确认 HUD 没有显示任务标题。Base D-pad 上/下应只报告不可用，不能改变 Catalog 选择或投递方向键。
4. 对已确认 Catalog 任务按 A，确认 Codex 打开唯一匹配的任务，且日志出现 `open-confirmed`；制造同名、无匹配或候选失效情形时，确认 A 不会打开错误任务。
5. 撤销辅助功能权限后按 LT，确认应用报告未确认；普通快捷键的授权状态应独立显示。
6. 撤销 Codex 麦克风权限，确认问题被识别为 Codex 录音前提，而不是误导用户反复授权 Agent Controller。
7. LT 按住期间断开手柄，确认应用暂停并在条件恢复后清理听写状态；Catalog 已有候选时断连、关闭 Bridge 或切出 Codex，确认候选被清除且恢复后必须回中。
8. 切换到其他前台应用，确认除 Menu 置前外的输入被阻止，且事件不会落入新前台应用。
9. 新增型号、USB 连接、Share 或背键支持时，单独记录 GameController 身份与端到端证据，不能沿用 2026-07-18 的单设备结论。
10. 按住 RB 分别测试 View、A/B/X/Y/Menu，再测试 RT+A/X/Y/B；只有 View 的听写状态变化可报告 confirmed，Fork 只能报告 posted-unconfirmed，其余必须 Unavailable。
