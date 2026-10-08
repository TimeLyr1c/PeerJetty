# Glass and motion / 玻璃与动画

## Scope / 范围

The drop card uses `NSGlassEffectView.regular` on macOS 26+, with one content container. macOS 15 uses `NSVisualEffectView.hudWindow` instead; the minimum requirement remains macOS 15. Card geometry, drag targets and menu-bar/Mission Control clearance are unchanged. Settings and text bodies retain native, opaque layouts. Labels use semantic system colors rather than a forced dark appearance.

投放卡片在 macOS 26+ 使用标准原生玻璃，macOS 15 使用系统 HUD 磨砂兼容路径，最低系统要求不变。卡片尺寸、拖放区域和菜单栏／调度中心避让不变；设置和文本正文保留原生、不透明排版，文字使用系统语义颜色。

General → Enable interface animations saves locally, defaults on for existing configurations, and applies immediately. System Reduce Motion overrides this choice without changing it. Accessibility display changes are observed using public workspace notifications. Reduce Transparency and Increase Contrast are delegated to native materials; no private system opacity percentage is read or guessed. Whether every system glass preference affects this floating control still requires manual observation.

通用 → 启用界面动画：本机保存、旧配置默认开启、立即生效。“减少动态效果”优先且不改变用户选择，系统辅助显示变化通过公开通知观察。“减少透明度”和“增强对比度”交给原生材质适配；不读取或猜测私有透明度参数。各项系统玻璃偏好是否影响浮动卡片，仍需手动观察。

## Motion / 运动

- Actual file drag: immediate, fixed card; the icon alone has a short feedback pulse.
- Non-drag preview and first text composer/reader appearance: 240 ms, 0.98→1 content scale with a damped spring and smooth window opacity. Keyboard focus is immediate.
- Dismissal: 160 ms. Status changes: 120 ms fade. Confirmed success: 220 ms icon pulse, once per file transfer ID; failed/unconfirmed text never produces success feedback.
- No new custom opening animation for settings/history. Disabling motion presents final states and cancels active custom effects.
- Reopening invalidates old hide completions. Core Animation uses bounded keyed effects, replacing previous feedback from its presentation scale. Hidden content clears custom animations. No particles, perpetual animations or added polling loops.

实际拖拽：卡片立即出现且固定，只对图标做轻微反馈。非拖拽预览、文本发送／查看首次出现：240 毫秒、0.98→1 轻微缩放与柔和显现，焦点立即可用。收起 160 毫秒，状态淡化 120 毫秒，已确认成功图标反馈 220 毫秒；失败／未确认不播放成功。设置和历史不增加自定义开合动画。关闭动画立即收稳；重新打开会使旧收起回调失效，反馈不叠加，隐藏后清除自定义动画。不增加持续动画、粒子或轮询。

## Preview and checks / 预览与检查

Run `Scripts/test-motion.sh --deliver-preview`, then open `outputs/GlassMotionPreview.app`. It contains replay, fixed drag-target, light/dark and isolated text-input controls, plus a quit button. Fake transfer progress never connects devices, sends files, uses production identities or opens history. Do not confuse this preview with the product app.

运行以上脚本后打开隔离预览，可回放出现、拖入、进度、成功、失败和收起，反复点击检查中断；可切换浅／深色和动画，查看独立文本输入。预览不连接设备、不传文件、不使用日常身份或历史。退出预览请点“退出预览”。

`Scripts/test-motion.sh --compare` compares the pre-change card at `630a441` with the working tree using a short isolated CPU/RSS sample. Set `PEERJETTY_MOTION_BASELINE_REF` to override that reference. These measurements exclude WindowServer/GPU and are not a full app benchmark. See [validation](VALIDATION.md) for results and outstanding physical checks.

短时性能采样只比较隔离 UI 进程，未包含 WindowServer／GPU，也不是整机或完整应用基准；数据与待验收内容见验证记录。

## References / 参考

[Apple Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/), [Apple spring animations](https://developer.apple.com/videos/play/wwdc2023/10158/), [NotchDrop](https://github.com/Lakr233/NotchDrop), [Dropover](https://dropoverapp.com/). These informed material, top-screen handoff and restrained feedback decisions. This change copies no third-party code and adds no UI/animation dependency.

以上作为材质、顶部交接和克制反馈的参考；本轮未复制第三方代码，也未增加 UI 或动画框架依赖。
