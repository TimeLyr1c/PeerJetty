# Menu, visibility and diagnostics / 菜单、图标与诊断

## Daily actions / 日常入口

The menu contains exactly Pair devices, Send Files, Send Text, Check for Updates, Settings and Quit. Pair opens Devices and the two-minute pairing window. Send Files uses the existing default target; if none is selected, Devices opens with guidance. Send Text retains its target and draft rules.

菜单仅六项：配对、发送文件、发送文本、检查更新、设置、退出。配对打开设备页并开启两分钟配对窗口；发送文件沿用默认目标，没有目标时打开设备页提示；文本目标与草稿规则不变。

Text history and latest received text are in Text settings; hiding history still does not stop recording, and latest received text remains available for the current run. Drop preview and recently received files are in Transfers. About and diagnostic details are in About settings.

文本历史与最近收到的文本位于文本设置，隐藏历史不停止记录，本次运行最近文本仍可查看。投放预览和最近收到的文件位于传输设置；关于与诊断详情在关于页。

## Hide and restore / 隐藏与恢复

General → Show menu bar icon defaults on for installations without a saved native visibility state. Turn it off to hide the icon and show PeerJetty in the Dock. Click the Dock icon to reopen Settings; turn the switch on to restore the menu icon and return to the usual menu-bar-only mode. Settings remains open when toggling. Reopening PeerJetty does not force the icon to reappear. Hiding never quits the app or stops paired transfers.

通用 → 显示菜单栏图标：无保存状态时默认开启。关闭后图标从菜单栏消失、Dock 出现 PeerJetty，点击即可打开设置；重新开启后恢复菜单栏图标，Dock 图标隐藏。切换时设置窗口保留；再次打开应用不强行恢复图标。隐藏不退出应用、不停止传输。

`NSStatusItem.autosaveName` is stable (`PeerJetty.MainStatusItem`); native `isVisible` persists and restores. Native removal is allowed without termination; visibility observation synchronizes the switch and Dock, with duplicate notifications suppressed. No private defaults are read and no startup force-show overrides native restoration. Insufficient menu-bar space is not user removal: AppKit can report visible even when physically obscured. OS menu-bar management and third-party hiding tools still need physical acceptance; the app cannot guarantee compatibility with every tool. Previously hidden icons had no persisted choice, so that old action cannot be migrated.

使用稳定 autosaveName 与原生 isVisible 保存／恢复，允许系统移除图标且不退出；观察可见性同步开关与 Dock，去重重复通知，不读取私有设置，也不在启动时强行显示。菜单栏空间不足不等于主动隐藏，系统可能仍报告可见。系统菜单栏管理及第三方隐藏工具需实机确认，不保证所有工具兼容。旧版隐藏没有保存，无法迁移那次临时选择。

## Connections and complete messages / 连接与完整提示

Devices → Manual connection information starts collapsed, displays this Mac’s local addresses and listener port, and shows Not ready yet before listening. The port is cached independently of the settings window; opening it later generates current addresses. Use these on the other device when nearby discovery fails. Pairing verification remains required.

设备 → 手动连接信息默认收起，显示本机地址与监听端口；服务未就绪时明确提示。端口在设置窗口之外缓存，晚打开也能看到当前地址，可在另一台电脑手动连接，仍需要核对配对码。

Warning cards use a short Open Settings for details cue. Settings retains the original message and offers View details when it exceeds the footer. Details are selectable, scrollable plain text; they do not open links or execute content. Normal version labels display only the product version. About → Diagnostic details retains the build and source commit; build identifiers remain in archives and update provenance.

警告卡片使用“打开设置查看详情”的短提示；设置保留完整原文，超出底部区域时可点查看详情。详情是可选择、可滚动的只读纯文本，不自动打开链接或执行内容。日常只显示产品版本；关于 → 诊断详情保留构建号与源码提交，归档和构建记录仍保留构建标识。

## Acceptance / 验收

See [validation](VALIDATION.md). Test the six actions, hide/show/restart, Dock reopen and system removal on both Macs. While hidden, verify bidirectional files/text and notifications. Replay card dismissal and fast reopen with motion on/off and system Reduce Motion. The isolated preview does not connect devices or read production state.

双机检查六项操作、隐藏／恢复／重启、Dock 点击与系统移除，隐藏时检查文件／文本双向传输和通知；回放收起／快速重开，检查动画开关与减少动态效果。隔离预览不连接真实设备、不读生产数据。
