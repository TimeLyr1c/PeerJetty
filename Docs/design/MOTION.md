# Native motion contract / 原生动画规范

Current refinement: rotation uses symmetric ninth-order progress; FileSuccessSequence overlaps the final 90ms of rotation with check drawing. CardSpringState owns two finite native stages with a single stronger-return transition at the first zero-velocity overshoot peak. Reopening preserves the existing trajectory and does not compound the return gain.

当前精修：旋转采用中点最快的对称九次曲线，转圈最后 90ms 已开始画勾，形成轻微重叠。卡片在首次过冲峰值速度归零时，只增强一次返回弹簧；中途重开沿用当前阶段，不重复加力。

## Meaning and ownership / 意义与归属

Motion is a JavaScript reference library here, **not** a dependency. Sources/PeerJetty/Motion.swift is PeerJetty's own AppKit/Core Animation infrastructure. Reuse it; don't introduce another animator or translate React APIs literally. Motion should express completion, direction, continuity or feedback, never replace state information.

Motion 库仅供参考；项目里的 Motion.swift 是自己的原生实现。使用 AppKit/Core Animation，不添加 JS 动画运行时。

| Responsibility / 职责 | Owner / 归属 |
|---|---|
| Preference + accessibility | MotionPolicy; persisted animation enable with fixed timing in PeerCore models |
| Speed profiles / file stages | MotionProfile + FileSuccessSequence + SpringParameters; values documented in ../APPEARANCE.md |
| Simple fades, physical axis springs, analytical interruption state and keyed cleanup | MotionEffects |
| Show/hide ordering, interruption revisions | WindowMotion |
| Monotonic rate-limited real progress | ProgressMotion |
| File ring/check sequence + task-aware hold | TransferGlyph + DropPanelController in DropZone.swift |
| Confirmed text feedback/focus | TextWindows.swift using shared effects |

## Choosing an effect / 选择实现

Use platform behavior first. Hover/color/opacity normally need a native simple transition, not a spring. New ordinary state effects generally target **150–300 ms**; an effect's intent and interruption behavior matter more than its nominal duration. Complex enter/exit, layout and gesture feedback can use AppKit animation contexts, CASpringAnimation or finite Core Animation keyframes through the existing infrastructure. Do not animate layout/hit geometry simply to move a decoration.

普通新动画通常 150–300 毫秒；复杂弹簧按交互调整，考虑阻尼、初速度与收稳，不能把曲线简单拉长后截断。现有固定节奏、卡片果冻展开和完成过程是用户明确选择的例外，数值沿用 [APPEARANCE.md](../APPEARANCE.md)，本轮不调整它们。

Use subtle direction/device relationships only when useful: e.g. a finite source-to-target handoff can explain transfer direction. It must not fabricate bytes, loop while idle or imply success before confirmation. Failure is readable and actionable, not a dramatic shake.

## Invariants / 不变量

- Focus, IME, typing, paste, cancel and drag acceptance are immediate; no wait for the visual sequence.
- Drag target/window geometry stays fixed. Visual scale/perspective must not expand registration or shadow-margin hit areas.
- Progress follows real bytes, never leads or retreats; unknown totals show preparation, and bytes complete without acknowledgement show waiting. Smoothing can lag; no fake replay or delayed network work.
- A check begins only for confirmed success. Failure/cancel/unconfirmed don't play success; hold starts after the actual finish, and a new task takes over immediately.
- Capture the fixed timing profile at start. Interrupt with current presentation/velocity as appropriate. Revisions/IDs guard every delayed cleanup, hide and completion.
- Key custom effects with PeerJetty.*; remove stale effects when hidden/reset/superseded. Hide the window before restoring alpha to prevent a final-frame flash. Do not remove unrelated native animations.
- No custom frame loop, animation polling, idle rotation, particles or infinite decorative effects. Keep layer count bounded and animation duration finite.

以上规则不依赖是否开启动画；关闭动画必须落在正确最终状态，不漏完成回调，也不改变协议、历史或配对行为。

## Accessibility / 辅助功能

The local animation switch is respected; public Reduce Motion overrides it without changing the saved preference. Reduce Transparency/Increase Contrast suppress optional trails; semantic text and final glyph remain. Native material handles supported system appearance behavior. No private system transparency parameter or platform setting modification.

减少动态效果直接收稳；减少透明度／增强对比度不展示可选拖影。设置、历史窗口不增加额外开合动画，正文保持不透明。

## Current experiment boundary / 当前实验边界

build20's two Y-axis ring turns, three fading trails and blue-to-green transition are a **local experiment**, not the default for all completion UI. No exact Apple Pay reproduction is claimed. The dedicated build21 refinement uses two angled green rings turning in opposite directions and a screenshot-proportioned check; owner visual acceptance is still pending. Preserve that candidate until the owner accepts/simplifies it in a dedicated change; this specification does not silently remove a just-requested effect. Consider clarity, latency, repeated-use comfort and cost before promotion. Text keeps its existing confirmed-success feedback.

当前一圈半翻转与拖影需要 Air/mini 实际验收；可以在下一次独立改动中选择简化，不扩展到所有控件。默认理念是克制，实验须有用途与证据。

## Verification / 验证

For motion changes run Scripts/test-motion.sh; use --deliver-preview only when a native preview is useful. Exercise instant/long/unknown-total transfers, acknowledgement, failures/cancellation, repeated success, parallel/new tasks, rapid reopen and disabling motion mid-effect. Verify the fixed timing profile and accessibility changes. Use the actual reusable card with simulated events; do not connect production identities to a preview.

Also run relevant drop/text/localization checks when those surfaces change. Record light/dark, complex backgrounds, long localized strings, notch/external screen, target boundaries and final-frame behavior. A locked/absent GUI cannot certify native appearance. Small captures and short CPU/RSS samples aren't full-resolution or WindowServer/GPU performance evidence. Compare changed effects for bounded layers/tasks and actual responsiveness; do not claim two-machine acceptance from single-machine tests.

Official references: [Motion transitions](https://motion.dev/docs/react-transitions), [Motion accessibility](https://motion.dev/docs/react-accessibility), [Apple HIG motion](https://developer.apple.com/design/human-interface-guidelines/motion), [Apple springs](https://developer.apple.com/videos/play/wwdc2023/10158/). Apply principles natively and check current documentation; no third-party code is copied by this configuration.

## Physical spring refinement / 物理弹簧精修

SpringParameters calibrates the native settling estimate and preserves mass 1 and per-effect damping in fixed timing (card outbound 0.40 / return 0.65; text/success 0.72). SpringMotion/CardSpringState own finite analytical position and velocity snapshots for retargeting; rendering is CASpringAnimation, never a display loop. Card axis/anchor springs share a linear animation-group clock, without applying another easing curve over the physical solution. Fade, progress and completion stages retain their separate responsibilities. Before/After now compares d894e53 pacing refinement against this candidate, both using native views and no production identity.

原生物理弹簧负责形变，短淡化负责显现，真实限速曲线负责进度，共享完成时间线负责翻转／画勾／停留。预览比较上一轮精修与当前候选；不安装 Web 库、不改传输与配置，仍待用户视觉确认。

2026-10-08 pacing adjustment: slower, more elastic card opening; faster file flip/check, one continuous stroke timing curve across the elbow. Exact values in APPEARANCE.md. Text opening, progress limits and hold unchanged. / 根据试用反馈分开调整展开与完成节奏，保留真实进度、确认及停留，不把卡片弹性变化扩散到文本窗口。
