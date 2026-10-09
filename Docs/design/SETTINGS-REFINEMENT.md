# Settings refinement / 设置排版精修

2026-10-08 local source candidate for build22; build21 installer unchanged. No version metadata bump or packaging before owner layout approval.

- Native five-category toolbar retained; resizable 720 × 580 pt default, 640 × 440 minimum, screen-aware height and vertical scrolling.
- Unified 13 pt form typography, semibold same-size headings, 20 pt About brand; semantic colors and native controls.
- 32/28 pt page insets, 28 pt between groups, 16 pt rows, 6 pt associated help; switches at trailing edge, separated destructive actions and collapsed manual/maintenance details.
- Removed animation/drop previews, their application callbacks, MotionPreviewWindow, simulated transfer replay and dedicated deliver-preview tooling. Automated motion/layout/menu checks retained. Historical ignored artifacts retained.
- Error details re-evaluate on resize; user paths retain full tooltip. Protocol, identity, data/history rules and motion timing unchanged.

验证：项目构建、中英文布局与回调／草稿检查、菜单显示／恢复及原生动画回归通过。布局覆盖浅深色、720 × 580 和 640 × 440。受限环境的图形测试不能取得原生显示图层，动画和菜单检查改在图形会话重跑通过。隔离设置窗口已打开；截图为原生视图渲染，不是双机操作验收。Air／mini 最终观感、硬件键盘与双向传输由用户实机确认；本轮不自动安装、推送或发布。

Source and screenshot review delivered first. Build22 App/DMG awaits layout approval; build21 is preserved.

## Stage two: App-style prototype / 第二阶段样稿

Owner requested the top toolbar remain. General/Devices now add a page heading and short help, lightweight grouped surfaces (10 pt corner, 18 pt inner padding, 20 pt separation), and device symbol/name presentation. Peer summary separates paired trust from active connection, follows picker/discovery updates, handles empty state, and keeps literal names/drafts. No extra connection polling, UI dependency or animations. Native semantic background and subtle edge adapt to appearance; no shadow/vibrancy. Other three pages are unchanged pending visual review.

Checks: bilingual resource coverage and native callback/draft/layout checks cover light/dark, default/minimum sizes, long names, empty peers and connected-state refresh. Screenshots are isolated rendered AppKit views; Air/mini real-device acceptance remains pending. No build22 installer produced; build21 archived installer remains unchanged.

## Accepted five-page implementation / 五页风格合入

The owner approved the prototype. General, Devices, Transfers, Text and About now share the page-header and quiet grouped-surface layout. Transfers adds a folder symbol; native callbacks, identity, history semantics and animations are unchanged. Build22 is the next local installer, not a public release. No automatic install or remote push.

用户确认样稿后统一五页；本地构建号为 22，产品版本保持 0.4.0。双机实际观感与双向传输仍需 Air／mini 验收。
