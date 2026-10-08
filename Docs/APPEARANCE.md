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

General → Animation speed offers **Fast / Natural / Relaxed**, defaulting to Natural for new and legacy configurations (unknown stored values also fall back). A change applies to the next effect; an active effect retains its captured timing. Existing text opening/closing and confirmed success feedback share the speed. Settings/history receive no new custom opening effects.

通用 → 动画速度提供 **快速／自然／舒缓**，新安装、旧配置和未知保存值均默认自然；修改从下一次效果生效，当前效果使用开始时的节奏。文本开合及确认成功反馈使用同一档，设置／历史不增加开合动画。

| Stage / 阶段 | Fast / 快速 | Natural / 自然 | Relaxed / 舒缓 |
|---|---:|---:|---:|
| Card appear / 卡片展开 | 380 ms | 620 ms | 880 ms |
| Text appear / 文本展开 | 220 ms | 340 ms | 480 ms |
| Status / 文字过渡 | 100 ms | 180 ms | 240 ms |
| Ring flip / 成功圆环翻转 | 585 ms | 1080 ms | 1575 ms |
| File success minimum / 文件成功反馈最短时长 | 1235 ms | 2280 ms | 3325 ms |
| Maximum ring speed / 圆环最大视觉速度 | 300%/s | 150%/s | 100%/s |
| Hold after check / 完成后停留 | 1 s | 1.8 s | 2.8 s |
| Dismiss / 收起 | 160 ms | 240 ms | 320 ms |

The card now uses native CASpringAnimation axes and anchor compensation, not 61 sampled transforms. Shared SpringParameters uses mass 1 and damping ratio 0.72, calibrating frequency against the native settlingDuration; initial normalized velocity is 0.72 × frequency. Time scaling preserves the character at 380/620/880 ms. Initial size remains 92%/82%, with a rebound below 102%. Each spring runs to its actual native settlement; no tail envelope truncates motion. Opacity has a short non-spring fade on the same epoch. SpringMotion is sampled only on interruption, not per frame; repeated reveal does not restart, dismissal reopening carries current presentation size and physical velocity. Text retains 97% scaling and its existing timing, using the same parameters. Progress remains monotonic/rate-limited, not a spring.

卡片改为原生 CASpringAnimation，不再使用 61 点形变采样。共享参数质量为 1、阻尼比 0.72，根据系统收稳时长换算频率和初速度，三档仍接近 380／620／880ms。初始宽 92%／高 82%、回弹低于 102%；运行到原生收稳时长，不截断尾部。形变与短透明度显现共用时刻，重复展开不重播；收起中重新打开保留当前视觉尺寸和运动速度。解析状态只在打断时计算，没有逐帧循环。文本沿用 97% 缩放和原有节奏，进度继续真实限速追赶。

The physical drag target is immediately available and fixed, independently of rendered deformation/opacity. Native window position, layout, transparent margins and registration never animate; keyboard focus remains immediate. Repeated drag sampling does not truncate the effect. Disabling animations/Reduce Motion presents the final state and retains confirmed-success hold time.

实际投放区域立即可用，独立于视觉形变和显现；窗口位置、排版、透明边距及拖放注册均不变，键盘焦点立即可用。重复拖拽采样不截断效果；关闭动画／减少动态效果立即展示最终状态并保留成功停留。

The ring follows real byte targets through a rate-limited visual trajectory. It may lag the latest reported percentage, never leads it and never retreats; accessible values/settings retain the true byte progress. Preparation/unknown totals show no invented percentage. Each new update retargets from the current mathematical position and velocity using a monotonic cubic segment. Duration is bounded below by 1.5 × remaining fraction / speed limit, with the endpoint-control constraint preserving monotonicity for tiny updates. This guarantees the derivative never exceeds the selected cap. Core Animation evaluates one replaceable finite effect, without background polling or a custom frame loop. Animations off/Reduce Motion display the true target immediately.

圆环依据真实字节目标，以限速曲线平滑追赶；视觉上可以略落后，但不会超前或倒退，设置／辅助功能仍保留真实进度。准备或总量未知不造百分比。新进度沿用当前数学位置和速度，以单调三次曲线衔接；时长下限和端点约束保证瞬间大跳、微小更新与频繁更新都不超过所选速率。仅替换一个有限 Core Animation 效果，不增加轮询或逐帧任务。关闭动画／减少动态效果立即显示真实目标。

Full bytes without receiver confirmation still show Waiting for confirmation. Only real success starts the green-ring completion followed by the two-stroke check and settlement. The visual finish also respects the cap: when far behind, it extends the sequence before the check, never delays actual transfer or acknowledgement, and never invents progress. The default minimum file success sequence is now 2.28 s, including the new flip stage; a ring starting near zero can take about 2.98 s. Hold starts only after this actual sequence finishes, not at a fixed nominal deadline. Failure/cancellation/unconfirmed events do not draw a check. Text keeps its confirmed-success icon feedback at the slower selected success duration.

字节传完但未获接收确认仍显示“等待确认”；真实成功才补齐绿色圆环，再画两笔对勾并收稳。视觉补齐同样限速，落后较多时先延长圆环过程，不延迟传输或确认、不补演假进度。自然档包含新翻转阶段的文件成功变换最短 2.28 秒；从近零追赶时约 2.98 秒，实际整段完成后才开始停留计时。失败、取消、未确认不画对勾；文本成功图标也使用较慢的所选成功时长。

### Experimental ring flip / 试验性圆环翻转

After confirmed progress finishes filling, the full ring rotates **twice around the vertical (Y) axis**, with mild perspective and a finite curve that accelerates continuously from rest and decelerates to rest. It changes from blue to green during the flip, then stops facing forward before the check starts. The stationary gray progress track is hidden during success so it does not mask the flip. Three extra vector ring layers trail at phase offsets 0.045/0.09/0.135, peak opacity 18%/10%/6%, and fade to zero before the flip ends. They are finite layers, not a particle emitter or continuous motion blur renderer.

真实成功确认并补齐后，完整圆环绕**竖直 Y 轴翻转两圈**，带轻微透视、起止速度归零的平滑曲线；翻转过程中由蓝变绿，正面停稳后立即开始对勾。成功阶段隐藏静止灰色底圈，避免遮蔽翻转。三个矢量圆环以 0.045／0.09／0.135 相位滞后，峰值不透明度 18%／10%／6%，翻转结束前淡出；不是粒子或持续运动模糊。

Reduce Transparency or Increase Contrast suppresses trails, including during an active effect; Reduce Motion/animations off settle the ring and check immediately. Reset, cancellation and new progress remove every flip/color/trail key, preventing old completion from affecting a new transfer. The captured total completion time includes fill, flip, drawing and settlement, then the existing selected hold begins. The file-only flip is an original visual experiment inspired by payment-style completion; it does not claim to reproduce Apple's exact animation. Text retains its existing success effect.

减少透明度／增强对比度禁用拖影，途中修改也会即时移除；减少动态效果／关闭动画直接展示最终圆环与对勾。重置、取消和新任务清除所有相关效果，旧完成回调不干扰新传输。总时长包含补齐、翻转、绘制和收稳，之后才开始原有停留。本次仅文件圆环试验，借鉴支付式完成反馈，不声称精确复刻 Apple 动画；文本成功效果不变。

The compact check uses a sharper ~76° elbow, an inset right endpoint, and round caps. At the normal 30-point glyph size, conservative stroke-to-ring clearance is over 2.5 points. Short-stroke completion is computed from actual segment lengths; the short stroke uses the first 28% of drawing time, joining a longer upward stroke without an extra constant-value corner pause. Confirmation and hold settings are unchanged; success drawing now uses the slower timings above. This is our own geometry/timing inspired by Apple's completion feedback, not Apple's private animation or an exact reproduction.

对勾使用约 76° 更尖的折角、向圆心收进的右端和圆头；30 点图标中保守计算的描边留白超过 2.5 点。按真实线段长度定位短笔结束点，短笔使用绘制时长的前 28%，直接衔接较慢的长笔，不再增加固定转角停顿。确认条件与停留规则不变，成功绘制使用上方的新时长；路径与节奏自行设计，借鉴 Apple 完成反馈，并非精确复刻其私有动画。

The card controller owns the hold deadline, starting after the check sequence finishes. Transfer IDs deduplicate success and invalidate stale hide callbacks; new transfers/drops take over immediately. Concurrent active transfers remain visible instead of being replaced by another transfer's completion. Dismissal orders the window out before restoring opacity. Keyed finite effects are cancelled on hiding; no spinner, particles, per-frame loop or added background polling.

控制器从对勾结束统一计时；传输 ID 防重复，旧隐藏回调失效，新传输／投放立即接管。并行任务未结束时保留活动任务进度；隐藏窗口之后才恢复透明度。有限图层动画在隐藏后清除，无持续旋转、粒子、逐帧循环或新增后台轮询。

## Preview and checks / 预览与检查

General → Preview animation opens an isolated native glass preview. Its local speed selector and Replay button simulate preparation, progress, confirmation and dismissal without changing the saved speed. It refuses real file drops and never connects devices, transfers files, opens history or accesses production identity. The animation toggle/Reduce Motion still applies. Close this window normally; the separate `outputs/GlassMotionPreview.app` test harness also provides ⌘Q.

通用 → 预览动画打开隔离原生玻璃预览；局部速度选择与“重新播放”演示准备、进度、确认和收起，不修改保存速度。拒绝真实文件投放，不连接设备、传文件、打开历史或访问日常身份；总开关和减少动态效果仍生效。正常关闭即可；独立测试预览还支持 ⌘Q。

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

FileSuccessSequence captures fill/flip/draw/settlement from the selected profile and actual progress catch-up. Completion layers share one epoch; card reveal/shape share one epoch as well. The ring starts and ends at zero rotation velocity; short/long check strokes have no extra plateau. Confirmation/hold/three speed settings are unchanged.

完成序列集中计算补齐、翻转、绘制和收稳；各图层共用开始时刻，卡片显现和形变同样共用时刻。保留两圈、三拖影、蓝绿转换、确认条件与停留规则。

Run `Scripts/preview-design.sh` to create **outputs/previews/design-build21/After.app** and **Before.app**. Before is compiled from immutable previous refinement source at `911df2d`; After from the working tree. Both reuse production SettingsController and MotionPreviewWindow without constructing an engine/store or touching identity. Switch Before/After and language in the comparison window; the other side restarts only the isolated preview process. Close settings/animation to return to controls, or use ⌘Q to quit. Preview switches affect only the process; unconnected callbacks perform no real operations.

打开 After.app，顶部对比窗口可切换旧／新版、中英文，并打开设置或动画。关闭设置／动画窗口可回到控制窗口，⌘Q 退出。旧版使用上一轮精修提交 911df2d 的源码，新版使用当前代码；仅模拟设备，不连接、不传文件、不访问身份、不保存日常设置。三档动画在动画窗口中选择；对比启动器不进入正式 App。

This is a preview-first candidate: build21 App/DMG generation waits for owner confirmation. Existing version metadata and build20 packages are retained; no automatic installation, push or release.

本轮先交付隔离预览，用户确认后再生成 build21 App／DMG。当前版本元数据与 build20 安装包保留，不自动安装、推送或发布。
