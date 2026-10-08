# Glass and motion / 玻璃与动画

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
| Ring and check / 圆环与对勾 | 320 ms | 650 ms | 950 ms |
| Hold after check / 完成后停留 | 1 s | 1.8 s | 2.8 s |
| Dismiss / 收起 | 160 ms | 240 ms | 320 ms |

The card now reveals softly from 12% opacity while expanding from 86% width / 62% height. A sampled damped step response (damping ratio 0.56, normalized frequency 7.5) gives one visible squash/stretch rebound: maximum height about 105%, with the peak near halfway through the sequence rather than concentrated in its first frames. A smooth envelope settles the tiny remaining tail to identity with zero endpoint velocity. Only a finite, precomputed set of 61 layer transforms is used; there is no custom frame loop. Presentation translation compensates AppKit layer anchors to keep the visual center fixed. Text windows retain their smaller 97% uniform spring.

卡片从 12% 不透明度柔和显现，初始宽度 86%／高度 62%，使用阻尼比 0.56、归一化频率 7.5 的阶跃响应形成一次明显压缩／拉伸回弹；最大高度约 105%，峰值在时间轴中段，避免动作挤在开头。尾部平滑收束到单位变换，端点速度为零。只预先生成 61 个图层变换，无自定义逐帧循环；按 AppKit 锚点补偿视觉中心，文字窗口保留原有 97% 轻微均匀缩放。

The physical drag target is immediately available and fixed, independently of rendered deformation/opacity. Native window position, layout, transparent margins and registration never animate; keyboard focus remains immediate. Repeated drag sampling does not truncate the effect. Disabling animations/Reduce Motion presents the final state and retains confirmed-success hold time.

实际投放区域立即可用，独立于视觉形变和显现；窗口位置、排版、透明边距及拖放注册均不变，键盘焦点立即可用。重复拖拽采样不截断效果；关闭动画／减少动态效果立即展示最终状态并保留成功停留。

A small vector ring replaces the horizontal file progress bar. Known byte progress is monotonic; preparation/unknown totals show no invented percentage. Full bytes without the real success event show Waiting for confirmation. Only confirmed success completes the green ring, draws the short and long check strokes, then gently settles. Small files receive the full success sequence without delaying the actual transfer or replaying fictional progress. Failure, cancellation and unconfirmed transfers do not draw a check. Text retains its existing confirmed-success feedback rather than adopting this ring.

少量矢量图层组成圆环，替代文件横向进度条；真实字节进度不倒退，准备或未知总量不造百分比，传完但未确认显示“等待确认”。仅真实成功事件补齐绿色圆环、依次画出两笔对勾并收稳；小文件也完整展示，不延迟传输、不补演假进度。失败／取消／未确认不画对勾；文本保留原有确认反馈。

The compact check uses a sharper ~76° elbow, an inset right endpoint, and round caps. At the normal 30-point glyph size, conservative stroke-to-ring clearance is over 2.5 points. Short-stroke completion is computed from actual segment lengths; it accelerates into a brief corner pause, followed by a longer decelerating upward stroke. Circle completion and overall speed/hold settings are unchanged. This is our own geometry/timing inspired by Apple's completion feedback, not Apple's private animation or an exact reproduction.

对勾使用约 76° 更尖的折角、向圆心收进的右端和圆头；30 点图标中保守计算的描边留白超过 2.5 点。按真实线段长度定位短笔结束点，短笔加速、转角略停、长笔减速向上画出。圆环完成条件、整体成功时长和停留不变；路径与节奏自行设计，借鉴 Apple 完成反馈，并非精确复刻其私有动画。

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
