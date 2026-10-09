# Component inventory / 组件清单

Source inventory checked 2026-10-08; this is a code inventory, not a new screenshot-based visual audit. Paths below are relative to the repository root. Keep shared components close to real callers; do not create a universal component framework preemptively.

本清单基于实际源码，记录可复用点和差异；不是新增的视觉实测报告。新增组件先找已有实现，再找原生控件，最后才自定义。

## Current ownership / 当前归属

| Owner / 文件 | Existing parts / 已有部分 | Reuse boundary / 复用边界 |
|---|---|---|
| Sources/PeerJetty/Settings.swift | SettingsController, categorized NSToolbar pages, native controls; group/heading/hint/row/setting/button/separator helpers; scrollable detailContent | Settings page patterns and diagnostics; preserve callbacks, draft settings and independent icon switches. / 分类设置与详情。 |
| Sources/PeerJetty/TextWindows.swift | PlainTextView/ComposerTextView, plainTextScroll, TextSurfaceScroll/Border, TextStatus, TextLayout, TextComposer/Reader/HistoryWindow, history row | Plain-text keyboard/IME behavior and editor surface already shared by sender/reader. Private helpers are local, not a public cross-window API. / 复用纯文本规则与正文样式。 |
| Sources/PeerJetty/DropZone.swift | DropZoneView, TransferGlyph, DropCardHost, DropPanelController; MotionPreviewWindow | Product-specific target, native material/shadow and progress glyph. Preview exercises the real view with simulated events. / 投放与预览，不扩散玻璃。 |
| Sources/PeerJetty/DropPresentation.swift | DropScreenMetrics, DropPresentation | Screen/notch/menu-bar geometry and activation regions; keep independent of decorative transforms. / 投放几何。 |
| Sources/PeerJetty/MenuBar.swift | Native status item/menu, visibility policy | Compact six-action menu and native template symbol. / 不复制设置页选项进菜单。 |
| Sources/PeerJetty/UpdateWindow.swift | Native update dialog and read-only release notes | Working fixed-coordinate window; future layout work should reuse native text/layout patterns, not create a web modal. / 更新界面。 |
| Sources/PeerJetty/Motion.swift | MotionPolicy/Profile/Effects, ProgressMotion, WindowMotion | The sole native animation infrastructure; see MOTION.md. / 集中策略。 |
| Sources/PeerCore/Localization.swift + Resources | L10n, English/Chinese resources | UI labels/errors separate from literal names/content. / 不翻译用户正文。 |

## Native mapping for HeroUI references / 参考转译

| Reference pattern | Native choice |
|---|---|
| Button / Switch / Select | NSButton / checkbox or NSSwitch where appropriate / NSPopUpButton |
| Form / field / description | NSTextField + associated label + wrapping hint in NSStackView/Auto Layout |
| Modal / destructive confirmation | NSAlert sheet tied to its owner, native button ordering |
| Tabs / category navigation | Existing NSToolbar settings categories; NSTabView/NSSegmentedControl only if the actual flow warrants them |
| Tooltip | NSView.toolTip as supplementary information; visible text/details for essential state |
| List / selection / empty state | NSTableView and existing history row/empty-state pattern |
| Progress / status | TransferGlyph for the drop card, native controls elsewhere; engine-derived state + readable label |

Borrow interaction anatomy and state coverage, not HeroUI's web spacing, CSS class names, browser focus implementation or decorative look.

参考组件的结构、禁用／选中／错误状态和键盘行为；不要照搬网页视觉和 CSS。

## Incremental cleanup queue / 后续小范围统一

- **Repeated row/button/spacer helpers:** SettingsController and TextLayout both use native factories. Keep the private helpers for now; when a feature needs both, extract a small shared AppKit helper with explicit sizing and compression policies. Do not expose every private helper or add an unused abstraction. / 有实际共同调用点再提取。
- **Read-only text surfaces:** sender/reader already share plainTextScroll, but update notes and settings diagnostics use separate 13 pt, 10 pt inset/bezel patterns. Those serve different roles; consolidate literal text safety and wrapping first, choose role-specific typography rather than blanket 14 pt replacement. / 先统一纯文本安全与行为，再讨论外观。
- **UpdateWindow fixed frames:** candidate for Auto Layout and bilingual/small-window checks in a dedicated change; current text/settings surfaces use constraints. No mass window migration in this task. / 更新窗口是最明确的后续布局统一点。
- **Status feedback:** TextStatus combines symbol/text/color while settings and updates mostly use labels/details. Consider a small shared status presentation only when preserving complete errors and callback behavior is demonstrated. / 不为了统一丢失完整错误。
- **DropZone.swift responsibilities:** contains drag parsing, card/controller/glyph and preview. Split by responsibility only during relevant maintenance; reuse the actual card in preview, never duplicate a fake production view. / 不把大文件拆分当独立目标。
- **Experimental motion:** build20 flipping/trails are still a local experiment; decide after device acceptance whether to keep or simplify. Do not reuse them for ordinary buttons or every success message. / 实验不等于全局设计语言。

No production component was found clearly safe to delete as dead temporary code in this scoped inspection. Original/ is a preserved baseline; tests and isolated preview are deliberate tools. Build/capture outputs remain ignored. Do not delete these because they look temporary; remove a candidate only after checking callers, lifecycle and verification coverage.

本轮未认定可直接删除的生产临时代码；原始基线、隔离预览和测试都有明确用途。不要盲删或为重构改稳定功能。

## Relevant checks / 验证入口

- Scripts/test-localization.sh with English and zh-Hans: settings/native layout and resources.
- Scripts/test-text.sh: drafts, IME/keyboard, reader/history semantics and layout checks.
- Scripts/test-drop-presentation.sh: fixed geometry, bilingual card and isolated drag checks.
- Scripts/test-menu.sh: visibility/reopen behavior and menu contract.
- Scripts/test-updates.sh: update state/response behavior.
- Scripts/test-motion.sh: finite effects, interruption, progress and preview.

Use checks affected by the actual change; don't run network/identity tests for a documentation-only rule update. Native composition, hardware input and two-device experience still need honest Air/mini acceptance.

Native refinement reuses a local settings group helper and FileSuccessSequence. Scripts/preview-design.sh compares fixed 5c6d6b6 pacing refinement/current production views without an engine. / 本轮增加本地分组与共享完成时间线，对比启动器只用于隔离测试。

SpringParameters + SpringMotion/CardSpringState in Motion.swift share physical tuning and interruption state across card/text/success springs. No additional UI dependency or persistent setting. / 原生弹簧参数与打断状态集中在 Motion.swift，未新增依赖或配置字段。
