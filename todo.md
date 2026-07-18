# Roadmap

This file tracks pending work only. Windows v0.7 behavior is documented in
`public/docs/controller-command-reference-v0.7.md`; the independent macOS
preview, its verified Xbox evidence, and its current limitations are documented
in `docs/macos.md`.

## Cross-platform

- [ ] Add a second production adapter only after its task discovery, command execution, state detection, and safety model have been researched; Claude Code is the first candidate.

## macOS preview

- [ ] Add a configurable submit binding for users whose Codex Enter behavior is not “send”.
- [ ] Validate additional Xbox models and wired USB connections without extrapolating from the single 2026-07-18 Xbox Wireless Controller test.
- [ ] Add Developer ID Application signing, Hardened Runtime, notarization, packaging, and upgrade handling before publishing a macOS Release.

## Windows v0.7 validation

- [ ] Run physical end-to-end validation of Power and Fast on a non-Max model; current Sol Max exposes no native Power control.
- [ ] Physically verify the shortcut-first Power / Fast transport (F17 / F18 / F20 with composer-button readback), its menu fallback, and the 30 s suspect cooldown; see `public/docs/controller-command-reference-v0.7.md`.
- [ ] Physically verify Simple-mode routing: the right stick keeps Power and Standard / Fast while the R3 picker stays visible, and RB+Y toggles Fast with the picker open.
- [ ] Validate the self-contained v0.7 package on a clean Windows account.

## Windows deferred and experimental work

- [ ] Re-enable Plan mode only after the route can verify the visible Codex state before and after every change; v0.7 exposes no controller binding for it.
- [ ] Prototype a virtual HID identity compatible with `v.oai.rad` only in an isolated experimental build; follow `public/docs/codex-micro-virtual-hid-bridge-plan.md`.
- [ ] Require Center → Direction → Center reports, device-fingerprint/version guards, explicit opt-in, and result verification before any virtual-HID action can report success.
- [ ] Do not ship or install a virtual HID driver in v0.7.
- [ ] Live-validate the new-task Project picker accessibility tree across Codex languages and releases.
- [ ] Replace best-effort keyboard traversal inside an open Project picker with verified option identity and result feedback.

## Windows architecture follow-up

- [ ] Extract controller gesture orchestration into a dedicated coordinator.
- [ ] Apply profile-specific controller visuals and first-run tuning defaults.
- [ ] Add a target Agent selector and a second production adapter.
- [ ] Replace the remaining `diagnostic.legacy.message` adapter with typed events.
- [ ] Coalesce high-frequency sidebar focus and composer preview events.

### Physical mapping preparation

- [ ] Keep v0.4a planning-only: do not change runtime button behavior until the v0.4b physical mapping is accepted.
- [ ] Require the runtime chain: physical input → physical gesture → virtual Micro input → context role → `CodexAction` → executor → verified feedback.
- [ ] Move `MainWindow.ProcessControllerState` button edges and stick routing into a testable controller coordinator.
- [ ] Stop calling `StartDictation`, `SendPrompt`, `CancelAction`, sidebar navigation, and composer adjustment directly from XInput button edges.
- [ ] Keep ABXY names only at the XInput transport boundary; use physical-position IDs such as `FaceSouth` inside gesture and profile layers.
- [ ] Replace the flat physical-input-to-business-action path with separate `ControllerProfile` and `VirtualMicroLayout` mappings.
- [ ] Expand optional rear inputs to `RearLeftUpper`, `RearLeftLower`, `RearRightUpper`, and `RearRightLower`.
- [ ] Mark rear inputs as independent, mirrored, or unavailable after capability probing; never make a core action rear-button-only.
- [ ] Complete Raw HID coverage for hat/D-pad, shoulders, triggers, Guide, and optional rear inputs instead of silently dropping them.
- [ ] Apply profile-specific stick/trigger tuning in the active input path instead of always using the global dead-zone value.
- [ ] Remove hard-coded face-button glyph assumptions from `DevicePageViewModel`.

### Semantic and safety foundation

- [ ] Add versioned contracts for hardware profile, gesture schema, virtual layout, action catalog, adapter, and user layout.
- [ ] Add a host-configurable `PhysicalGestureEngine` for down/up, tap, double-tap, hold, axis, chord suppression, and disconnect.
- [ ] Use an injectable `TimeProvider` for context arming, PTT latch, dial hold, repeat, cooldown, and undo timing.
- [ ] Add the stable virtual surface: six Agent slots, six Command slots, four analog directions, `DialStep`, `DialPress`, and `DialHold`.
- [ ] Add `controller.*` extension inputs and a versioned `VirtualMicroLayout` with migration and unknown-field preservation.
- [ ] Add a `CodexAction` catalog with frequency, context priority, risk, prerequisites, repeat policy, executors, verification, and feedback metadata.
- [ ] Add `ContextResolver` priority: SafetyConfirmation > ApprovalRequest > Question > ModalDialog > MenuOrListbox > ComposerControl > Dictation > RunningTurn > Base.
- [ ] Implement `Idle → Candidate → Armed → Executing → Cooldown`, freezing conflicting Base actions as soon as Candidate appears.
- [ ] Wait for input release when Question, Menu, or ComposerControl exits so the same press cannot leak into Base.
- [ ] Keep Cancel separate from Decline; allow Approve / Decline only in a verified approval context.
- [ ] Allow Stop and Steer only for a verified active turn belonging to the selected task.
- [ ] Add an `ExecutorRegistry` and a Codex capability manifest with explicit supported/degraded/unavailable states.
- [ ] Make managed shortcuts dynamic, conflict-aware, backed up, idempotent, reload-aware, and removable without overwriting user entries.

### Dispatch, Steer, Queue, and feedback

- [ ] Split `composer.dispatchDefault`, `turn.steer`, `turn.queue`, and `turn.stop` into separate adapter capabilities and actions.
- [ ] Probe selected-task active-turn state and Follow-up behavior without changing that preference.
- [ ] Add operations equivalent to `TryGetTurnState`, `TryGetFollowUpMode`, `DispatchDefault`, `SteerCurrentTurn`, `QueueForNextTurn`, and `ManageQueuedMessages`.
- [ ] Verify whether Dispatch started, steered, queued, stopped, or remained unknown.
- [ ] Add canonical outcomes: Succeeded, Unavailable, Blocked, Conflict, Degraded, and Failed.
- [ ] Show virtual surface/slot, action, context, executor path, verified result, and recovery guidance; never collapse Started, Steered, Queued, and Unknown into “sent”.

### Codex Micro completeness and settings

- [ ] Implement six immutable Agent slots with Most recent, Pinned, Priority, and Custom sources.
- [ ] Add single/double task switching, empty-slot binding, and explicit degraded behavior when background switching is unavailable.
- [ ] Represent Idle, Thinking, Complete unread, Requires input, Error, Unassigned, and selected state independently.
- [ ] Implement six configurable Command slots and restore defaults.
- [ ] Add push-to-talk double-pull latch plus distinct recording, processing, and transcript-ready feedback.
- [ ] Restore configurable virtual analog defaults and Composer-navigation / Reasoning-only dial modes.
- [ ] Add settings for slots, directions, gesture thresholds, layers, diagnostics, and capability status.
- [ ] Separate built-in actions, Skills, managed shortcuts, controlled composer text, and external URLs in the mapping UI.
- [ ] Display unsupported/degraded actions with a reason and provide a separate enhanced-controller rear-input view.

### Required test gates

- [ ] Deterministic timing tests for context arming, PTT latch, dial hold, repeat, cooldown, chord timeout, and disconnect.
- [ ] Gesture tests for hysteresis, dominant direction, neutral-before-reverse, D-pad/stick source separation, and non-repeatable toggles.
- [ ] Input-queue tests for short Down/Up pulses, duplicate packets, reconnect while held, and disconnect-generated releases.
- [ ] Context-leak tests for approval appearing during Cancel/Send, Question/Menu exit while held, and foreground/focus changes.
- [ ] Follow-up tests for idle Dispatch, running Steer/Queue defaults, one-shot opposite behavior, empty composer, and unknown dispatch.
- [ ] Agent-slot, controller-profile, shortcut-conflict, Codex-UIA-change, unsupported-capability, migration, and user-layout-preservation tests.

### Research blockers

- [ ] Reliable Windows task switching without foreground activation and a foreground gate that permits only verified background slot switching.
- [ ] Real-time selected-task status, thread/turn identity, active-turn state, and Follow-up behavior detection.
- [ ] Stable multilingual UIA for menus, Steer, Queue, approvals, questions, and queue management.
- [ ] Detect whether managed keybinding changes require Codex reload/restart.
- [ ] Define Priority-source ordering inside projects.
- [ ] Establish reliable hands-free dictation latch execution and verification.
- [ ] Establish stable queue edit, reorder, send-now, and delete semantics.
