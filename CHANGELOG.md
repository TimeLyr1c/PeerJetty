# Changes

## Unreleased — subtle ring refinements, planned build21

Widens the ring tilt difference, thickens strokes 16%, and slows the finite flip from 620ms to 720ms with eased companion visibility. Pause before the unchanged check reduces from 200ms to 170ms. Reference geometry, card reveal and fixed settings remain unchanged. Preview only.

稍微拉开双环倾角，线条加粗 16%；翻转从 620ms 放慢到 720ms，伴随环平滑显现与淡出，画勾前暂停缩到 170ms。对勾比例、卡片弹出与设置不变，先更新预览。

## Unreleased — reference check and two green rings, planned build21

The check now scales relative to the ring using sampled reference proportions (~72° elbow). Replaces three faint ghosts with one green companion: two rings total spin/flip on different tilted planes in opposite directions. Color completes during fill; 620ms flip, 200ms pause and 600ms drawing retained. Isolated preview only.

按参考图校准对勾角度与留白；原三层拖影改为双绿环，在不同倾角反向转动／翻面。补齐阶段完成变绿，保留固定翻转、暂停、画勾节奏，先交付预览。

## Unreleased — fixed motion timing, planned build21

Removed animation speed selectors and persisted speed configuration. Reveal uses Relaxed card tuning; completion uses a 620ms one-and-a-half-turn flip, 200ms pause and 600ms check. Animation toggle and accessibility overrides remain. Legacy speed values are ignored.

移除设置和预览的速度选择；固定舒缓弹出、620ms 一圈半翻转、200ms 暂停与 600ms 画勾。保留动画总开关与辅助功能优先规则；旧速度字段自动忽略。

## Unreleased — 5% rebound and one-turn completion, planned build21

Card height overshoot is roughly 5%; return frequency gain is 75% with stronger damping to limit secondary movement. Completion uses one turn at 340/620/860ms, with the existing slow/fast/slow curve and pre-check pause. Comparison baseline 5c6d6b6; preview only.

卡片过冲约 5%，返回频率提高 75%并增强阻尼；圆环改为一圈，翻转 340／620／860ms，保留慢／快／慢曲线和画勾前停顿。仅更新隔离预览，暂不生成安装包。

## Unreleased — steeper motion tuning, planned build21

Rotation uses ninth-order smootherstep with flatter endpoints and a sharper middle speed peak; duration, turns, color synchronization and continuous check drawing retained. Pause before the check increases to 180/250/320ms. Card damping changes to 0.53 for about 3% overshoot; return frequency gain rises to 55%, applied once. Original geometry and input behavior unchanged. Comparison baseline 3396b22, preview only.

旋转改为开头／结尾更缓、中段更陡的九次曲线，时长、两圈、颜色同步和连续画勾保持；画勾前停顿增至 180／250／320ms。卡片阻尼调整为 0.53，过冲约 3%，返回频率加力提高到 55%，只应用一次。命中区域与操作行为不变，预览比较 3396b22／当前候选。

## Unreleased — completion pause and stronger return, planned build21

Symmetric slow/fast/slow two-turn rotation at 280/500/700ms, with synchronized color/trails. A front-facing green-ring pause of 100/150/200ms precedes the existing continuous check drawing. Card outward motion stays unchanged; return frequency increases 35% once at the first zero-velocity peak. Piecewise native state preserves position/velocity through reopening without compounding strength. Comparison baseline: 95ac75a. Preview only; no installer or publication.

两圈旋转采用慢／快／慢对称曲线（280／500／700ms），颜色与拖影同步；正面绿色圆环暂停 100／150／200ms 后开始原有连续画勾。弹出阶段保持，首次过冲峰值速度归零时返回频率提高 35%，只加力一次；分段原生状态保留重开时的位置和速度。预览比较 95ac75a／当前候选，不生成安装包或发布。

## Unreleased — native refinement preview (planned build21), 2026-10-08

Keeps five native settings categories with grouped forms and aligned controls. Softens card compression to 92% width / 82% height with a bounded soft rebound; retains three speed durations. Centralizes the completion timeline/epoch, smooths two-turn flip start/end, and joins the check strokes without an extra pause. Turns, trails, blue-green transition and confirmation/hold rules remain. Isolated Before/After previews compile build20/current source. No protocol, identity, text-window or update-window changes. Installer generation awaits preview acceptance; build20 retained.

五类原生设置改为分组表单与对齐控件；卡片初始 92%／82%，单次回弹受限，三档时长不变。统一完成时钟，翻转起止平滑、两笔对勾不再额外停顿；两圈、拖影、蓝绿转换、确认与停留保留。隔离旧新版预览使用固定上一轮精修／当前源码；不改协议、身份、文本或更新窗口。预览确认后再生成安装包，保留 build20。

Replaces sampled card deformation with native physical springs (mass 1, damping 0.72), native settling duration and interruption velocity. Shares physical tuning with text/success feedback; progress and completion stages unchanged. Comparison baseline is 04cfade. Still preview-first planned build21, no installer or publication.

卡片展开改用原生物理弹簧，质量 1、阻尼 0.72，按系统收稳并保留打断速度；文本与成功反馈共享参数，真实进度和完成阶段不变。对比基线更新为 04cfade，仍属于待确认 build21，不另打包或发布。

Pacing follow-up: card opening 520/860/1220ms with softer damping (0.58), about 2.4% rebound. File success turns ~63% faster, check draws ~17% faster, with one continuous easing curve through the elbow. Other effects, progress, hold and identities unchanged. Compare 04cfade/current preview; still planned build21 without installer generation.

节奏微调：三档展开 520／860／1220ms，卡片阻尼降至 0.58、回弹约 2.4%。文件成功翻转快约 63%，画勾快约 17%，拐角沿用一条连续缓动；其他动画、真实进度、停留与身份保持。预览比较 04cfade／当前候选，仍属于待确认 build21。

## 0.4.0 / build 20 — local visual experiment, 2026-10-08

After confirmed file progress completes, the ring makes two vertical-axis turns with three faint fading trails, changing blue to green during rotation; only then draws the check. Suppresses trails for Reduce Transparency/Increase Contrast, respects Reduce Motion, and clears all effects on new progress or cancellation. Success hold includes the extra flip stage. Original payment-style visual experiment, not an exact Apple animation copy. Text and transfer protocol unchanged; local App/DMG only, build19 retained.

文件确认成功并补齐后，圆环绕竖轴翻转两圈，带三层渐淡拖影，翻转中由蓝变绿，停稳后才画对勾。减少透明度／增强对比度禁用拖影，减少动态效果直接收稳，新任务或取消清除旧效果；成功停留覆盖新增翻转阶段。自行设计的支付式视觉试验，非精确复制 Apple 动画；文本与协议不变，仅本地 App／DMG，保留 build19。

## 0.4.0 / build 19 — local test candidate, 2026-10-08

Gives the drop-card spring initial momentum for a faster far-away return and slower approach. The file ring now smoothly retargets from current position/velocity with a visual rate cap (Fast 300%, Natural 150%, Relaxed 100% per second), never exceeding real progress. Slows confirmed ring-to-check feedback to at least 650/1200/1750 ms; rate-limited final fill may extend it. Hold starts after the actual sequence, with new transfers/cancellation still preempting safely. No transfer delay, fake progress or new continuous task. Includes native motion, burst/tiny-update rate checks and bilingual layouts; physical Air/mini acceptance pending. Local App/DMG only; build18 retained.

弹簧增加初速度，远处回归更快、近处减速更明显。文件圆环从当前位置与速度连续追赶，视觉限速为快速每秒 300%、自然 150%、舒缓 100%，不超前于真实进度。确认后的圆环／对勾变换放慢至至少 650／1200／1750ms，限速补齐可能进一步延长；实际整段结束才计停留，新任务与取消仍可立即接管。不延迟传输、不造进度、不增加持续任务。原生运动、频繁／微小更新限速与双语布局检查通过；Air／mini 实机待确认，仅本地测试包，保留 build18。

## 0.4.0 / build 18 — local test candidate, 2026-10-08

Softens the drop-card reveal with a buffered fade and centered squash/stretch rebound (Fast 380 ms, Natural 620 ms, Relaxed 880 ms). The physical drag target remains immediately usable. Insets the success check, sharpens its elbow and gives the two strokes different pacing with a brief corner pause. Text opening, transfer confirmation and success hold rules stay unchanged. Native interruption/reduction, geometry and bilingual layout checks passed; full-resolution Air/mini visual acceptance remains pending. Local App/DMG only; build17 is retained.

投放卡片改为柔和显现、原位压缩／拉伸／轻弹收稳：快速 380ms、自然 620ms、舒缓 880ms，实际投放立即可用。对勾缩小并向圆心收进、折角更尖，两笔采用不同节奏并在转角略停。文本开合、传输确认与成功停留规则不变；原生中断／减少动态效果、几何与中英文布局检查通过，Air／mini 全分辨率观感待确认。仅本地 App／DMG，保留 build17。

## 0.4.0 / build 17 — local test candidate, 2026-10-08

Adds locally saved Fast / Natural / Relaxed motion, default Natural, and an isolated animation preview. Fixed drag targets remain immediately usable while the card gently springs in place. Real byte progress now uses a vector ring; only confirmed success completes it and draws a two-stroke check, followed by the selected hold time. Small files retain full success feedback; new/parallel transfers, duplicate completion and stale hide callbacks are guarded. Text effects share the speed; animation-off/Reduce Motion settles immediately without losing the hold. Includes bilingual documentation, automated regression checks and native preview captures. Air/mini physical acceptance remains pending. Local App/DMG only; no install, push or public release.

新增本机保存的快速／自然／舒缓（默认自然）及隔离动画预览；拖拽目标立即可用，卡片原位轻弹。真实字节圆环仅在确认成功后补齐、画出两笔对勾，按所选速度停留；小文件保留完整反馈，防并行／新任务被旧成功或隐藏回调覆盖。文本效果共用速度；关闭动画／减少动态效果立即收稳但保留停留。含双语说明、自动回归及原生预览截帧；Air／mini 实机验收待确认，仅本地 App／DMG，不安装、推送或公开发布。

## 0.4.0 / build 16 — local test candidate, 2026-10-08

Adds a padded transparent glass-card host with one static rounded floating shadow, retaining the card/drop geometry. Uses an explicit 18-point medium menu-bar symbol. Menu and Dock visibility are now independent saved preferences; legacy configurations preserve their prior combination. Reopening with both hidden temporarily restores only the menu icon and opens Settings, without changing saved choices. Login/service launches retain hidden preferences. Includes bilingual recovery controls and isolated state/layout/transfer checks. Physical Air/mini composition, click-through and launch acceptance remain pending. Local App/DMG only; no automatic installation or public release.

透明外壳承载原生玻璃及单层圆角悬浮投影，保持卡片与投放几何；菜单图标明确为 18 点中等字重。菜单栏与 Dock 独立保存，旧配置保留原组合后迁移。两者都隐藏时手动重新打开，仅本次临时恢复菜单栏并打开设置，不改保存选择；登录／服务启动继续隐藏。含双语临时恢复入口与隔离状态、布局及传输检查。Air／mini 真实合成、点透与启动验收待完成；仅本地 App／DMG，不自动安装或公开发布。

## 0.4.0 / build 15 — local test candidate, 2026-10-08

Simplifies the menu to Pair, Send Files, Send Text, Check for Updates, Settings and Quit. General now controls menu-bar visibility using native persisted state; hiding shows a Dock icon for recovery without stopping transfers. History and latest text live in Text settings, previews and recent files in Transfers, and diagnostic build details in About. Keeps manual connection addresses/port in a collapsed section and caches the listener port for settings opened later. Long warnings use a short card cue with complete scrollable details in Settings. Fixes the final-frame dismissal flash by hiding before restoring opacity. Normal version labels omit build numbers; installer/provenance metadata retains them. No public Release or automatic installation.

菜单收敛为配对、发送文件、发送文本、检查更新、设置、退出。通用页用系统原生保存状态控制菜单栏图标；隐藏后显示 Dock 入口，传输继续。历史和最近文本移入文本设置，预览和最近文件保留在传输设置，构建诊断位于关于页。手动连接地址与端口折叠显示，缓存监听端口避免晚打开设置时为空。长警告改为简短卡片提示，设置提供完整可滚动详情。收起先隐藏再恢复透明度，修复末帧闪回；正常版本显示去掉构建号，安装包和诊断元数据保留。不自动安装、不公开发布。

## 0.4.0 / build 14 — local test candidate, 2026-10-08

Combines categorized native settings, unified text composer/reader/history layouts, larger centered drop-card text, and native drop-card glass (macOS 26+, system frosted fallback on macOS 15). Adds a local, live Enable interface animations switch, overridden by system Reduce Motion. Actual drag targets stay immediate and stationary; previews and text windows use short, restrained elastic feedback with cancellation-safe transitions. Protocol, identities and text-history rules remain unchanged. Automated checks pass; physical Air/mini, accessibility material and macOS 15 acceptance remain pending. Local App/DMG only; not a public Release.

集中交付原生分类设置、统一文本发送／查看／历史排版、投放卡片字体与居中优化，以及原生玻璃卡片（macOS 26+；macOS 15 系统磨砂）。通用页新增立即生效的本机动画开关，系统减少动态效果优先。实际拖拽目标立即出现且固定，预览与文本窗口使用短促克制的弹性反馈，动画可中断。协议、配对身份、历史规则不变。自动检查通过，Air／mini 实机、辅助显示材质及 macOS 15 验收待完成；仅本地 App／DMG，不公开发布。

## 0.4.0 / build 13 — local test candidate, 2026-10-07

Adds Send Text from the menu bar: a focused multiline panel with paired targets, native copy/paste/select-all shortcuts, ⌘Enter to send, Esc to close, and runtime-only drafts. Text uses existing paired TLS identities with optional `text-v1` negotiation, a 256 KiB UTF-8 limit, matching receipt IDs, bounded queues and duplicate protection. Unconfirmed sends time out after 30 seconds without automatic retries; older peers can still transfer files.

Successful sends and receipts are always saved in a private local SQLite history. Show Text History hides the entry without stopping recording; keep the latest 500 entries, 30 days or forever, with explicit hide/clear/retention choices. Receipt notifications expose only device names; click to view and explicitly copy. Text never overrides the clipboard or opens links automatically and is independent of file auto-open. Includes bilingual UI/docs and isolated storage, AppKit and TLS checks. Physical two-Mac acceptance remains pending. This candidate is not a public GitHub Release.

菜单栏新增“发送文本”：顶部多行输入、已配对目标、普通复制／粘贴／全选快捷键、⌘Enter 发送、Esc 关闭、本次运行草稿。复用配对 TLS 身份，通过可选 `text-v1` 能力传输，单条最大 256 KiB UTF-8，匹配收到确认，限制队列并防重复；30 秒无确认提示未确认收到，不自动重发，旧版仍可传文件。

成功收发始终保存到本机私有 SQLite 历史。“显示文本历史”仅隐藏入口，不停止记录；默认最近 500 条，可改为 30 天或一直保留，隐藏／清空／缩短保留前明确确认。通知仅显示设备名称，点击查看并主动复制，不自动改剪贴板或打开链接，不受文件自动打开影响。包含中英文和隔离检查，双机实机验收仍待完成；本轮不发布 GitHub Release。


## 0.3.2 / build 11 — stable release, 2026-10-07

Adds manual Check for updates from the menu bar and Settings. Reads GitHub’s Latest stable Release without authentication, compares numeric product versions, displays notes and opens the matching release page for manual DMG installation. Handles no releases, missing installers, local builds ahead of public releases, network errors and rate limits. Does not download/install automatically or modify pairing and transfer settings.

菜单栏和设置新增“检查更新”：主动查询 GitHub Latest 正式 Release，按数字比较版本，显示说明并引导手动下载 DMG。处理无正式版本、缺安装包、本地版本领先、断网和接口限流；不自动下载/安装，也不修改配对或传输设置。

Published as Latest at https://github.com/TimeLyr1c/PeerJetty/releases/tag/v0.3.2, using the existing tested DMG from source `a5316f42c45122107cac2ad3843a443f05578cb5`. Includes the drop-card and bilingual UI improvements developed in the intervening local candidates. Only the DMG is uploaded; ad hoc signed and not notarized.

已集中发布为 Latest 正式版，沿用原测试 DMG，标签指向实际源码提交；包含中间测试候选完成的投放卡片及应用双语改进。公开附件仅 DMG，仍为临时签名、未公证。

## 0.3.1 / build 10 — local test candidate, 2026-10-06

Adds a Language picker to Settings with Follow system, English and 简体中文. Choices save locally and apply after quitting and reopening PeerJetty; active transfers are not restarted. Existing installations follow system. Removes the misleading WeChat file-access shortcut, which only opened Full Disk Access settings; drag-and-drop support remains. Pairing and transfer configuration are unchanged. Native macOS dialogs retain OS language selection.

设置新增“跟随系统 / English / 简体中文”语言选择，自动保存在本机，退出重开后生效，不强制中断传输。旧安装默认跟随系统。移除仅打开“完全磁盘访问权限”页面的“微信文件访问权限”按钮，保留微信拖拽能力；配对与传输设置不变，系统弹窗仍按 macOS 的语言显示。

## 0.3.0 / build 9 — local test candidate, 2026-10-06

Adds English and Simplified Chinese interface and diagnostics, selected from macOS system/per-app language preferences with English fallback. Uses stable .strings keys and native .stringsdict plural rules for item counts; permission descriptions ship in both languages. Wraps longer settings explanations, enlarges pairing guidance, and reserves space for translated drop-card controls.

Known rejection diagnostics carry optional bounded error keys/arguments alongside legacy text, so new peers can render them in their own language while older protocol-v1 peers ignore the new fields. Pairing identifiers, device identity, file names, user device names, and receive/open settings are unchanged. Transfer throttling uses a language-independent flag. Explicit-language formatting/layout and legacy JSON checks are automated; physical mixed-language two-Mac acceptance is pending. The owner reports successful use of the preceding 0.2.6 candidate.

新增英文和简体中文界面、通知、应用错误及系统权限说明，跟随系统或单应用语言偏好，缺失翻译回退英文。数量使用原生单复数规则，设置和配对说明支持较长文案，投放卡片为翻译后的按钮保留空间。已知拒收原因附带可选错误代码与参数，保留旧版可读文字；协议仍为 v1，设备身份、配对和接收/打开设置不变。中英文格式、布局、消息兼容及隔离传输检查已通过；实体 Mac 一中一英互传待验收。用户报告前一版 0.2.6 使用正常。

## 0.2.6 / build 8 — local test candidate, 2026-10-05

Moves activation into an approach region below the menu bar: the drop card stays at least 64 points below the physical screen edge and clears the menu/notch area by at least 12 points. File drags show a stationary target immediately, removing the top-edge slide animation and the need to reach macOS’s Mission Control gesture region. Preview/status presentation uses a short fade. This reduces gesture overlap without modifying system preferences or intercepting system gestures; dragging past the card to the actual edge can still invoke macOS. Geometry, simulated approach-path, drag-session and isolated AppKit checks cover the new activation route; physical mini/Air gesture-conflict acceptance is pending. Pairing and transfer behavior are unchanged.

## 0.2.5 / build 7 — local test candidate, 2026-10-05

Replaces the notch-style black rectangle with an independent rounded HUD card below the menu bar and display safe area. Opens only when a file drag reaches the current screen’s top-center trigger; uses actual auxiliary screen areas for notch location/width, supports cross-screen activation, and retains the card while moving into it. Handles screen-layout and menu-bar geometry changes, stale drag pasteboards, and Reduce Motion. Pairing, transfer protocol, and receive/open settings are unchanged. Automated geometry, drag-session and isolated AppKit layout checks pass; physical two-Mac/full-screen/Space acceptance is pending. Not yet installed or publicly released.

## 0.2.4 / build 6 — first public release, 2026-10-05

Published at https://github.com/TimeLyr1c/PeerJetty/releases/tag/v0.2.4 from source commit `ef49e674889298a1dd8d9a75f118e89abcb5b85f`, with an Apple Silicon DMG installer. ZIP, checksums and build/signature records are retained in the local release archive rather than uploaded as release assets. Ad hoc signed, not notarized.

Adds a persistent receiver-side “open after receiving” switch, disabled by default including legacy configuration upgrades. Only successful committed roots are handed to the system default application; opening failures preserve received files and are reported. Settings now scroll to accommodate smaller screens. Pairing and transfer protocol unchanged; The project owner reports successful two-Mac use; this does not establish coverage of every edge case.

## 0.2.3 / build 5 — new icon, local candidate, 2026-10-05

Uses the project owner’s replacement PeerJetty PNG and records the non-notch display improvement plan. The display behavior is unchanged in this build; screen-edge activation and geometry adjustments are planned separately. Pairing and transfer implementation unchanged. Not automatically installed or published.

## 0.2.2 / build 4 — PeerJetty rename, local candidate, 2026-10-05

Renames the app UI, SwiftPM target, executable, build output and new installer filenames to PeerJetty. Copies validated legacy settings once without overwriting current settings or deleting the old file; preserves the Bundle ID, Keychain identity and protocol v1 identifiers for compatibility. Adds MIT licensing records and bundles LICENSE with the app. Keeps Original and historical packages unchanged. Compilation and automated checks are recorded in VALIDATION.md; physical upgrade acceptance remains pending. Not automatically installed or publicly released.

## 0.2.1 / build 3 — local test candidate, 2026-10-05

Adds version/build display in Settings and About, build provenance including source revision and dirty state, explicit version management, and immutable installer archives with checksums. Records the i18n, naming, licensing, GitHub and update roadmap. No changes to the pairing identity or transfer protocol; not automatically installed or publicly released.

## 0.2.0 — 2026-10-04

Native bidirectional LAN app with Bonjour discovery, mutual TLS, two-screen pairing confirmation, device trust/revocation, Keychain identity, configurable destination, streamed files/folders, integrity checks, exclusive collision-safe commits, progress/cancellation, notifications, menu/settings and notch/non-notch drop zone. Received files are never opened automatically. No SSH or per-user connection credentials in source.

Preserves Original starter separately. macOS 15+ required for memory-only test identity import. First local build is arm64, ad hoc signed, not notarized. Two-device physical acceptance and original source/icon licensing remain pending before public release.
