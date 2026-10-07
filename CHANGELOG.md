# Changes

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
