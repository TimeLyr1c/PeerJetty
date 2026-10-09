# Glass and motion / 玻璃与动画

Long-term rules and reuse: [design system](design/DESIGN_SYSTEM.md), [components](design/COMPONENTS.md), [motion contract](design/MOTION.md). This document retains current appearance values and experimental implementation details.

长期规则见上方设计文档；本文保留当前参数与试验实现，不将某次动画试验视为全应用默认。

## Scope / 范围

The drop card uses `NSGlassEffectView.regular` on macOS 26+, with one content container. macOS 15 uses `NSVisualEffectView.hudWindow` instead; the minimum requirement remains macOS 15. Card geometry, drag targets and menu-bar/Mission Control clearance are unchanged. Settings and text bodies retain native, opaque layouts. Labels use semantic system colors rather than a forced dark appearance.

投放卡片在 macOS 26+ 使用标准原生玻璃，macOS 15 使用系统 HUD 磨砂兼容路径，最低系统要求不变。卡片尺寸、拖放区域和菜单栏／调度中心避让不变；设置和文本正文保留原生、不透明排版，文字使用系统语义颜色。

General → Enable interface animations saves locally, defaults on for existing configurations, and applies immediately. System Reduce Motion overrides this choice without changing it. Accessibility display changes are observed using public workspace notifications. Reduce Transparency and Increase Contrast are delegated to native materials; no private system opacity percentage is read or guessed. Whether every system glass preference affects this floating control still requires manual observation.

通用 → 启用界面动画：本机保存、旧配置默认开启、立即生效。“减少动态效果”优先且不改变用户选择，系统辅助显示变化通过公开通知观察。“减少透明度”和“增强对比度”交给原生材质适配；不读取或猜测私有透明度参数。各项系统玻璃偏好是否影响浮动卡片，仍需手动观察。

## Floating shadow / 悬浮投影

The native card sits in a transparent host with 32-point padding on each side. A single static rounded shadow has radius 16, downward offset 6 and opacity 24% in light appearance / 38% in dark appearance. Native window shadow is disabled; no black border or extra material is added. Card geometry remains unchanged. Host hit testing rejects the padding; the existing 50 ms position sampler controls window mouse passthrough outside the physical card without a new timer. This sampled handoff and real WindowServer composition require physical acceptance, especially near card edges and across screens.

卡片放入四周 32 点透明外壳，使用单层圆角静态投影：半径 16、向下偏移 6、浅色 24%／深色 38%。关闭窗口原有阴影，不增加黑描边或额外材质。卡片位置与尺寸不变，透明边距拒绝命中；沿用 50 毫秒位置采样控制窗口点透，不增加定时器。边缘采样切换、跨屏和真实系统合成效果仍需实机确认。

## Motion / 运动

Animation timing is fixed. Only Enable interface animations and Preview animation remain; the legacy animationSpeed field is ignored and omitted on the next configuration save. Card reveal uses the former Relaxed tuning; completion and text use Natural timing, with a 170ms overlap between final deceleration and check drawing.

动画节奏固定，保留总开关和预览。旧 animationSpeed 字段忽略并在下次保存时移除；卡片弹出沿用舒缓标定，完成与文本采用自然节奏，转圈最后 170ms 开始画勾。

| Stage / 阶段 | Fixed timing / 固定节奏 |
|---|---:|
| Outward spring calibration / 弹出弹簧标定 | 1220 ms |
| Text appear / 文本展开 | 340 ms |
| Status / 文字过渡 | 180 ms |
| Ring flip, 1.5 turns / 圆环翻转一圈半 | 720 ms |
| Pause before check / 画勾前暂停 | 0 ms |
| Check drawing / 对勾绘制 | 600 ms |
| Check overlap / 画勾提前重叠 | 170 ms |
| File success minimum / 成功反馈最短时长 | 1710 ms |
| Maximum ring speed / 圆环最大视觉速度 | 150%/s |
| Hold after check / 完成后停留 | 1.8 s |
| Dismiss / 收起 | 240 ms |

The card now uses native CASpringAnimation axes and anchor compensation, not 61 sampled transforms. Shared SpringParameters uses mass 1; card damping ratio 0.40, text/success feedback 0.72, calibrating frequency against the native settlingDuration; initial normalized velocity is the captured damping ratio × frequency. Time scaling preserves the character at 1220 ms. Initial size remains 92%/82%, with a visible rebound around 105.0% (bounded below 105.5%). The outward spring switches at its zero-velocity peak; the stronger return runs to actual native settlement without a tail cutoff. Opacity has a short non-spring fade on the same epoch. SpringMotion is sampled only on interruption, not per frame; repeated reveal does not restart, dismissal reopening carries current presentation size and physical velocity. Text retains 97% scaling and its existing timing, using the same parameters. Progress remains monotonic/rate-limited, not a spring.

卡片改为原生 CASpringAnimation，不再使用 61 点形变采样。共享参数质量为 1，卡片阻尼比 0.40，文本与成功反馈保持 0.72，根据系统收稳时长换算频率和初速度，弹出阶段沿用 1220ms 标定。初始宽 92%／高 82%、回弹约 105.0%，上限 105.5%；返回阶段运行到原生收稳时长，不截断尾部。形变与短透明度显现共用时刻，重复展开不重播；收起中重新打开保留当前视觉尺寸和运动速度。解析状态只在打断时计算，没有逐帧循环。文本沿用 97% 缩放和原有节奏，进度继续真实限速追赶。

The physical drag target is immediately available and fixed, independently of rendered deformation/opacity. Native window position, layout, transparent margins and registration never animate; keyboard focus remains immediate. Repeated drag sampling does not truncate the effect. Disabling animations/Reduce Motion presents the final state and retains confirmed-success hold time.

实际投放区域立即可用，独立于视觉形变和显现；窗口位置、排版、透明边距及拖放注册均不变，键盘焦点立即可用。重复拖拽采样不截断效果；关闭动画／减少动态效果立即展示最终状态并保留成功停留。

The ring follows real byte targets through a rate-limited visual trajectory. It may lag the latest reported percentage, never leads it and never retreats; accessible values/settings retain the true byte progress. Preparation/unknown totals show no invented percentage. Each new update retargets from the current mathematical position and velocity using a monotonic cubic segment. Duration is bounded below by 1.5 × remaining fraction / speed limit, with the endpoint-control constraint preserving monotonicity for tiny updates. This guarantees the derivative never exceeds the selected cap. Core Animation evaluates one replaceable finite effect, without background polling or a custom frame loop. Animations off/Reduce Motion display the true target immediately.

圆环依据真实字节目标，以限速曲线平滑追赶；视觉上可以略落后，但不会超前或倒退，设置／辅助功能仍保留真实进度。准备或总量未知不造百分比。新进度沿用当前数学位置和速度，以单调三次曲线衔接；时长下限和端点约束保证瞬间大跳、微小更新与频繁更新都不超过所选速率。仅替换一个有限 Core Animation 效果，不增加轮询或逐帧任务。关闭动画／减少动态效果立即显示真实目标。

Full bytes without receiver confirmation still show Waiting for confirmation. Only real success starts the green-ring completion followed by the two-stroke check and settlement. The visual finish also respects the cap: when far behind, it extends the sequence before the check, never delays actual transfer or acknowledgement, and never invents progress. The default minimum file success sequence is now 1.71 s, including the new flip stage; a ring starting near zero can take about 2.41 s. Hold starts only after this actual sequence finishes, not at a fixed nominal deadline. Failure/cancellation/unconfirmed events do not draw a check. Text keeps its confirmed-success icon feedback at the fixed natural success duration.

字节传完但未获接收确认仍显示“等待确认”；真实成功才补齐绿色圆环，再画两笔对勾并收稳。视觉补齐同样限速，落后较多时先延长圆环过程，不延迟传输或确认、不补演假进度。固定节奏包含新翻转阶段的文件成功变换最短 1.71 秒；从近零追赶时约 2.41 秒，实际整段完成后才开始停留计时。失败、取消、未确认不画对勾；文本成功图标也使用固定自然成功时长。

### Experimental ring flip / 试验性圆环翻转

After confirmation, the ring fills and turns green. During the 720ms flip there are exactly two visible green rings: the main ring and one finite companion at 65% peak opacity. Both turn one-and-a-half times in opposite directions, with different X tilts (+0.45 / -0.85 radians at peak) and opposite Z-plane twist (±0.70 radians). Tilt/twist use a smooth sine envelope over ninth-order rotation progress, converging to the same circle at rest. The companion uses eased opacity at entry/exit and fades out as rotation ends; the check starts 150ms before rotation ends and draws over 600ms. These are transform keyframes, not frame callbacks or optical motion blur. The reference screenshot provides geometry, not an exact Apple animation trajectory.

确认后圆环补齐并变绿；720ms 翻转期间仅显示两个绿环（主环＋一个伴随环，峰值不透明度 65%），反向翻转一圈半，同时沿不同倾角旋转。X 倾角峰值为 +0.45／−0.85 弧度，平面扭转为 ±0.70 弧度；倾角使用平滑包络，停稳时回到同一圆形。伴随环平滑显现／淡出，在翻转结束时淡出，最后 170ms 已开始用 600ms 画勾。只用有限原生关键帧，无逐帧回调；静态参考图不提供 Apple 原始运动轨迹。

Reduce Transparency or Increase Contrast suppresses trails, including during an active effect; Reduce Motion/animations off settle the ring and check immediately. Reset, cancellation and new progress remove every flip/color/trail key, preventing old completion from affecting a new transfer. The captured total completion time includes fill, flip, drawing and settlement, then the fixed hold begins. The file-only flip is an original visual experiment inspired by payment-style completion; it does not claim to reproduce Apple's exact animation. Text retains its existing success effect.

减少透明度／增强对比度禁用拖影，途中修改也会即时移除；减少动态效果／关闭动画直接展示最终圆环与对勾。重置、取消和新任务清除所有相关效果，旧完成回调不干扰新传输。总时长包含补齐、翻转、绘制和收稳，之后才开始原有停留。本次仅文件圆环试验，借鉴支付式完成反馈，不声称精确复刻 Apple 动画；文本成功效果不变。

The check centerline is measured from the supplied screenshot: reference circle center (470,479), centerline radius 144; points (416,484), (456,534), (526,429). Store points relative to the circle center/radius so rectangular bounds do not distort the ~72.35° elbow or endpoint spacing. Radial clearances are 62.34% / 60.59% / 47.87% of the radius before stroke caps; stroke width is 17.5% of radius, with round caps/joins. Raster scaling/compression limits exactness; owner visual comparison remains required. The same continuous strokeEnd curve crosses the elbow without restarting.

对勾按用户截图测量圆心、中心线半径与三个顶点，折角约 72.35°；顶点至圆环的径向留白约为半径的 62.34%／60.59%／47.87%（未计圆头）。路径随圆心／半径缩放，线宽为半径的 17.5%，保持圆头与连续画勾。截图缩放与压缩会影响测量精度，最终比例仍需视觉确认。

## Preview and checks / 预览与检查

General → Preview animation opens an isolated native glass preview. Its Replay button simulates preparation, progress, confirmation and dismissal using fixed timing. It refuses real file drops and never connects devices, transfers files, opens history or accesses production identity. The animation toggle/Reduce Motion still applies. Close this window normally; the separate `outputs/GlassMotionPreview.app` test harness also provides ⌘Q.

通用 → 预览动画打开隔离原生玻璃预览；“重新播放”演示准备、进度、确认和收起，使用固定节奏。拒绝真实文件投放，不连接设备、传文件、打开历史或访问日常身份；总开关和减少动态效果仍生效。正常关闭即可；独立测试预览还支持 ⌘Q。

`Scripts/test-motion.sh --deliver-preview` builds that standalone harness. `Scripts/test-motion.sh --compare` compares build16 at `52a3415` with the working tree; `PEERJETTY_MOTION_BASELINE_REF` overrides the reference. Short CPU/RSS samples exclude WindowServer/GPU and are not a full app benchmark. Native low-resolution replay captures live in ignored `outputs/previews/motion-build17/`; they supplement, rather than replace, full-resolution Air/mini acceptance. See [validation](VALIDATION.md).

短时 CPU／内存采样仅覆盖独立 UI 进程，未包含 WindowServer／GPU。忽略的预览目录保存三档真实低分辨率截帧回放，不能替代 Air／mini 全分辨率实机验收；结果见验证记录。

## References / 参考

[Apple Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/), [Apple spring animations](https://developer.apple.com/videos/play/wwdc2023/10158/), [NotchDrop](https://github.com/Lakr233/NotchDrop), [Dropover](https://dropoverapp.com/). These informed material, top-screen handoff and restrained feedback decisions. This change copies no third-party code and adds no UI/animation dependency.

以上作为材质、顶部交接和克制反馈的参考；本轮未复制第三方代码，也未增加 UI 或动画框架依赖。

### Success references / 成功反馈参考

[Apple Pay on the Web](https://developer.apple.com/videos/play/tech-talks/111381/) describes confirmed completion followed by a check and dismissal. [Apple's related Tap to Pay cashier guide](https://developer.apple.com/tap-to-pay/files/Tap-to-Pay-on-iPhone-Cashier-Guide-July2023.pdf) documents the completion check. These public sources do not specify exact path coordinates or per-stroke durations; our proportions and timing are independently implemented. No Apple artwork or third-party animation code is bundled.

Apple 公开资料说明确认完成、展示对勾与收起，但未给出精确路径和逐笔时长；本项目自行实现比例与节奏，不打包 Apple 图像或第三方动画代码。

## Native refinement comparison / 原生精修对比

The build21 source candidate retains five native toolbar categories. Settings.swift's local group helper provides consistent headings/spacing and 190-point label columns, left-aligned native controls, separate trust/history-clearing actions and collapsing disclosures. No glass form cards or page-transition animation is added. Existing callbacks and drafts remain intact.

build21 源码候选保留顶部五类导航，通用分成本机身份、语言、显示与启动、动画四组。其他页分离主操作、危险操作与详情，采用 190 点标签列和对齐的原生控件，不新增玻璃表单或分类动画；草稿与操作回调保持。

FileSuccessSequence captures fill/flip/pause/draw/settlement from the fixed profile and actual progress catch-up. Completion layers share one epoch; card reveal/shape share one epoch as well. The ring starts and ends at zero rotation velocity; short/long check strokes have no extra plateau. Confirmation and hold rules are unchanged.

完成序列集中计算补齐、翻转、暂停、绘制和收稳；各图层共用开始时刻，卡片显现和形变同样共用时刻。保留一圈半、两个绿环、蓝绿转换、确认条件与停留规则。

Run `Scripts/preview-design.sh` to create **outputs/previews/design-build21/After.app** and **Before.app**. Before is compiled from immutable previous physical-spring source at `606aa76`; After from the working tree. Both reuse production SettingsController and MotionPreviewWindow without constructing an engine/store or touching identity. Switch Before/After and language in the comparison window; the other side restarts only the isolated preview process. Close settings/animation to return to controls, or use ⌘Q to quit. Preview switches affect only the process; unconnected callbacks perform no real operations.

打开 After.app，顶部对比窗口可切换旧／新版、中英文，并打开设置或动画。关闭设置／动画窗口可回到控制窗口，⌘Q 退出。旧版使用上一轮物理弹簧提交 606aa76 的源码，新版使用当前代码；仅模拟设备，不连接、不传文件、不访问身份、不保存日常设置。动画窗口使用固定节奏；对比启动器不进入正式 App。

The owner approved the final appearance on 2026-10-08: 17.5%-radius stroke and 170ms overlapping check drawing. This refinement is prepared for the real 0.4.0/build21 App and DMG; physical Air/mini acceptance is pending.

用户已于 2026-10-08 确认最终预览（线宽 17.5%、提前 170ms 画勾），准备编入正式运行的 0.4.0/build21 App 与 DMG；Air／mini 双机验收另行记录。

Outbound damping ratio is 0.40 for roughly 5% height overshoot. At the first zero-velocity peak, return frequency increases 75% (stiffness x3.0625) and damping ratio becomes 0.65, avoiding a visible secondary bounce. Both native stages remain continuous and interruption-safe; text/progress springs are unchanged.

弹出阻尼比为 0.40，高度过冲约 5%；首次峰值速度归零后，返回频率提高 75%（刚度 3.0625 倍），返回阻尼比改为 0.65，减少后续晃动。两阶段保留位置／速度连续与打断保护，文本和进度不变。

SDK 27 native cleanup estimates for the two stages are about 678ms. These include the conservative native tail; they are not the first peak or first return time. / 当前 SDK 的两阶段原生清理估计约为 678ms，包含系统保守尾部估计，不是第一次过冲或回归标准尺寸的时间。
