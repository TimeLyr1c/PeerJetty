# PeerJetty design system / 设计系统

## Scope and authority / 范围与依据

PeerJetty is a native macOS LAN transfer app for paired devices, with bidirectional files and explicit text delivery. Swift/AppKit, Auto Layout, SF Symbols and Core Animation are the current UI stack; SwiftPM has no external package dependencies. Minimum macOS 15; glass is availability-gated at macOS 26. This is a development contract, not a redesign or a new runtime framework.

PeerJetty 是已配对设备之间的局域网双向投递应用。当前为 Swift/AppKit 原生 UI，不是 React、SwiftUI、Tauri 或 Electron；没有第三方 SwiftPM 依赖。最低 macOS 15，玻璃接口仅在 macOS 26+ 使用。本规范不重做稳定界面。

Root [AGENTS.md](../../AGENTS.md) contains stable agent rules. This directory explains application and reuse. [APPEARANCE.md](../APPEARANCE.md) owns current measured appearance/timing parameters; feature documents own behavior, [VALIDATION.md](../VALIDATION.md) owns evidence. Do not duplicate mutable timing tables here or replace old feature specifications with a visual preference.

AGENTS 保存每次应遵循的规则；本目录负责应用方法、组件与参考。具体数值沿用 APPEARANCE，功能规则和测试证据分别留在功能文档与 VALIDATION。

## Design language / 设计语言

Minimal · native · restrained · modern · calm · precise.

Priority: information hierarchy → space/layout → typography/readability → state feedback → motion → decoration.

优先让用户知道“给谁／来自谁、是否在线、正在做什么、是否真正完成、失败后怎么办”。设备之间的方向和关系应清楚，但不需要把每个窗口都画成两台电脑。拒绝过度渐变、发光、玻璃、大圆角卡片、装饰动画、网页落地页布局及通用 AI 仪表盘风格。

## Foundations / 基础

| Area / 项目 | Rule / 规则 |
|---|---|
| Typography / 字体 | System font, native control sizing. Text bodies retain 14 pt. Settings forms use 13 pt labels, hints and controls with 13 pt semibold group headings. Other surfaces retain their existing role-specific typography. Drop card keeps its accepted 15/13 pt pair. Smaller text is secondary only. These are reuse baselines, not a forced global restyle. / 复用现有字号，重要内容不降级成小字。 |
| Color / 颜色 | labelColor, secondaryLabelColor, textColor, textBackgroundColor, separatorColor, controlAccentColor; semantic success/warning/error plus icon and text. Resolve custom layer colors on appearance change. / 语义颜色，状态不只靠红绿。 |
| Layout / 布局 | Auto Layout and native intrinsic sizes for ordinary windows; reuse 20 pt content inset, 12 pt section spacing, 10 pt row spacing where already established. Geometry-owned drop/placement code remains separate. / 普通窗口优先约束布局，投放几何不混入样式辅助类。 |
| Surfaces / 材质 | Native window backgrounds; opaque readable text. Existing drop card alone uses one native glass/frosted layer and static shadow, without extra glow/borders. / 不把投放玻璃扩散到整个应用。 |
| Actions / 操作 | One clear primary action, native buttons, distinct destructive action with existing confirmation; native popups/toolbar/table/tooltips. / 保持键盘焦点、快捷键及原生选择行为。 |
| Content / 内容 | L10n keys in both resource sets; user text/name copied unchanged. Wrapping/detail views for essential messages; tooltip only supplemental. / 错误必须可完整查看。 |
| Accessibility / 辅助功能 | Native keyboard focus and accessible labels/values; reduced motion/transparency and contrast. Don't move hit targets with decorative transforms. / 有无动画均可操作。 |

## State vocabulary / 状态词汇

Paired is trust, online is reachability, selected is an explicit destination: do not conflate them. Ready → preparing → sending/receiving → waiting for confirmation → completed, or failed/cancelled. Unknown totals have no fabricated percent. Final success is driven by engine confirmation, not a timer or animation end. Connection failures offer an actionable explanation; sensitive received text stays out of notifications.

配对、在线和默认目标是不同概念；字节传完仍可能等待接收确认。失败／取消不用成功反馈，状态展示不能改变协议含义或自动打开策略。

## Official reference access / 官方文档接入

Checked 2026-10-08. Consult current official pages before adopting APIs; no downloaded documentation snapshot or third-party MCP is treated as authority.

- [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/) and [AppKit](https://developer.apple.com/documentation/appkit): platform behavior first.
- [HeroUI documentation index](https://heroui.com/llms.txt), [components](https://heroui.com/docs/react/components), [official MCP](https://heroui.com/docs/react/getting-started/mcp-server): reference anatomy, states, labeling, dialogs, selection and keyboard interaction. React v3 requires React 19+ and Tailwind v4; its official MCP exposes React documentation over stdio and requires Node 22+. It is not an AppKit component provider.
- [Motion docs](https://motion.dev/docs/), [transitions](https://motion.dev/docs/react-transitions), [accessibility](https://motion.dev/docs/react-accessibility): reference enter/exit, continuity, springs and accessibility; implement in our native layer.

Decision: **no UI dependency and no MCP installation**. Codex can consult the official links above with its existing browsing tools; the root rules make this the project entry point. A React-specific documentation process adds little for native work and would require Node/npx without enabling native implementation. There is no new .codex/config.toml or machine-wide configuration. Reconsider only for an approved supported web surface; recheck official package/version/compatibility and verify connection before recording an MCP as usable.

决定：不安装 HeroUI/Motion，不引入 Web，也不注册 React 文档 MCP。已把官方入口接到项目规则中，按需查阅即可；不是宣称已经连接了 MCP。以后若明确开发 Web 界面，再独立评估。

## Change workflow / 修改流程

1. Read the relevant component/feature spec; identify existing reuse point and actual state source.
2. Make the smallest change; keep engine, identities, history and visual geometry boundaries intact.
3. Check relevant bilingual/accessibility/interruption states using existing scripts and isolated previews.
4. Record what was actually verified, update ownership docs, make a focused local commit. Package/release only at the agreed cadence.

先复用、再小改；不为“统一”同时迁移所有窗口，也不把本轮规范配置当作需要发布的新版本。

Settings-specific spacing: 32 pt horizontal/28 pt vertical insets, 28 pt between groups, 16 pt between rows, 6 pt before associated help. Do not spread these values to the geometry-owned drop card. / 设置留白不改变投放卡片几何。
