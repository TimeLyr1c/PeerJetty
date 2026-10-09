# Menu, visibility and diagnostics / 菜单、图标与诊断

## Daily actions / 日常入口

The menu contains exactly Pair devices, Send Files, Send Text, Check for Updates, Settings and Quit. Pair opens Devices and the two-minute pairing window. Send Files uses the existing default target; if none is selected, Devices opens with guidance. Send Text retains its target and draft rules.

菜单仅六项：配对、发送文件、发送文本、检查更新、设置、退出。配对打开设备页并开启两分钟配对窗口；发送文件沿用默认目标，没有目标时打开设备页提示；文本目标与草稿规则不变。

Text history and latest received text are in Text settings; hiding history still does not stop recording, and latest received text remains available for the current run. Recently received files are in Transfers; both demo entries have been removed. About and diagnostic details are in About settings.

文本历史与最近收到的文本位于文本设置，隐藏历史不停止记录，本次运行最近文本仍可查看。最近收到的文件位于传输设置；两种演示入口已移除；关于与诊断详情在关于页。

## Hide and restore / 隐藏与恢复

General has independent Show menu bar icon and Show Dock icon switches. New installations default to menu on / Dock off; all four combinations are supported. Both choices persist locally. Upgrading a legacy configuration preserves the previous native menu visibility and its corresponding Dock visibility before unlinking the switches. Hiding icons never stops transfers or closes Settings.

通用页提供独立的“显示菜单栏图标”和“显示 Dock 图标”，支持四种组合。新安装默认菜单栏开启、Dock 关闭；升级保留旧版实际组合后解除联动。隐藏不退出、不停止传输，也不关闭设置。

If both are hidden, opening PeerJetty from Applications or Spotlight temporarily shows only the menu icon and opens Settings. The saved menu switch stays off; the notice and Hide temporary icon button explain this per-run state. Turn the switch on to save permanent visibility. Normal quit clears temporary recovery; a crash cannot persist it into the next run. Login/service launch events retain saved hidden choices; unknown launch events do not independently trigger recovery.

两者都隐藏时，从 Applications／Spotlight 打开应用会临时恢复菜单栏并打开设置，Dock 仍隐藏。开关仍为关闭，旁边显示临时说明和“隐藏临时图标”；主动开启才长期保存。退出清理临时状态，异常退出后也按持久化配置恢复。登录／服务启动通过公开启动事件识别，保持隐藏；无法判定的启动事件本身不触发恢复。

The stable native autosave name preserves menu positioning, but application configuration is authoritative for visibility. Internal updates suppress visibility callbacks; external system removal saves menu-off without changing Dock. Save failures are reported: settings changes roll back, while a system removal remains effective for the run. Insufficient menu space is not an explicit removal; third-party hiding tools still require physical checks. The template arrow symbol uses an explicit 18-point medium configuration.

原生 autosaveName 保留位置，应用配置决定显示选择；内部更新不当作系统操作。系统移除只保存菜单栏关闭，不改 Dock。设置保存失败会回退并提示，系统移除保存失败仍保持本次隐藏并提示。空间不足不等于主动移除；第三方隐藏工具待实测。菜单图标使用 18 点中等字重模板双向箭头。

## Connections and complete messages / 连接与完整提示

Devices → Manual connection information starts collapsed. Active IPv4 Wi-Fi/Ethernet addresses are listed with interface labels and the listener port; other interfaces remain in a separate collapsed list. Classification uses system interface metadata, not IP prefix guesses, and does not promise reachability. Copy connection information copies the listed addresses/port. It shows Not ready yet before listening. The port is cached independently of the settings window; opening it later generates current addresses. Use these on the other device when nearby discovery fails. Pairing verification remains required.

设备 → 手动连接信息默认收起，以接口标签逐行显示当前启用的 Wi-Fi／以太网 IPv4 地址和端口；其他接口另行折叠，可复制地址。依据系统接口元数据分类，不根据 IP 前缀猜来源，也不保证可达；未监听时明确提示。端口在设置窗口之外缓存，晚打开也能看到当前地址，可在另一台电脑手动连接，仍需要核对配对码。

Warning cards use a short Open Settings for details cue. Settings retains the original message and offers View details when it exceeds the footer. Details are selectable, scrollable plain text; they do not open links or execute content. Normal version labels display only the product version. About → Diagnostic details retains the build and source commit; build identifiers remain in archives and update provenance.

警告卡片使用“打开设置查看详情”的短提示；设置保留完整原文，超出底部区域时可点查看详情。详情是可选择、可滚动的只读纯文本，不自动打开链接或执行内容。日常只显示产品版本；关于 → 诊断详情保留构建号与源码提交，归档和构建记录仍保留构建标识。

## Acceptance / 验收

See [validation](VALIDATION.md). Test the six actions, hide/show/restart, Dock reopen and system removal on both Macs. While hidden, verify bidirectional files/text and notifications. Replay card dismissal and fast reopen with motion on/off and system Reduce Motion. The isolated preview does not connect devices or read production state.

双机检查六项操作、隐藏／恢复／重启、Dock 点击与系统移除，隐藏时检查文件／文本双向传输和通知；回放收起／快速重开，检查动画开关与减少动态效果。隔离预览不连接真实设备、不读生产数据。


## Settings and transfer state / 设置与传输状态

Settings is a normal primary managed window. With Dock hidden, switching to another app hides Settings as a conservative fallback; reopening restores its page, position and in-memory draft. Attached sheets and app-modal interactions suppress that hiding. Dock preferences and background transfers do not change. Opening Settings does not automatically select the local-name field; click or Tab still edits normally. Actual Stage Manager grouping remains a real-device check.

设置使用普通主窗口；Dock 隐藏时，切换应用会隐藏设置，重开保留页面、位置和本次运行未保存输入。系统 sheet 或模态交互期间不执行此隐藏，不改 Dock 偏好或后台传输。打开设置不自动选中名称，点击或 Tab 仍正常编辑。Stage Manager 的真实分组仍需双机验收。

Transfers shows the most recently started **active** file task. Settings has no Cancel action. The drop card has a 28 pt × button with a localized cancel tooltip/accessibility label, targeting the UUID displayed on that card. Completion/failure/cancellation selects another active task or hides the × entirely. Settings opened later replays current active tasks and the latest result. The receive path is in a bordered, vertically centered field with middle truncation, full tooltip and accessibility value.

传输页仅显示状态，不再提供取消按钮。投放卡片右侧 28 点叉号按当前显示任务的 UUID 取消，带本地化提示及辅助功能名称；任务结束后切换其他活动任务，全部结束隐藏叉号。晚打开设置可恢复状态和最近结果；接收路径有轻边框、居中排列、中间省略及完整提示／辅助功能内容。

Devices separates paired/unpaired from connected/disconnected; discovery alone is not a live connection. Unpair… requires confirmation and shows a prominent device-page result/re-pair entry; when Settings is hidden a generic notification opens that page. Offline/old peers remain explicitly unconfirmed. See [protocol](PROTOCOL.md).

设备页分别呈现配对与连接，发现设备不等于已连接。“解除配对…”先确认，结果与重新配对入口放在设备页醒目位置；未显示设置时用通用系统通知引导。离线／旧版对端明确标为未确认，详见协议。


### build24 unpair result / 解除结果弹窗

A successful remote unpair event or local unpair outcome opens Devices and an app-owned result sheet, independently of system notification permission. The sheet offers OK and Re-pair; it never automatically approves pairing. Existing sheets/modal interactions finish first; the pending result is then shown. A certificate rejection by itself is still a connection failure, not proof of remote revocation. Both endpoints need build23 or newer for bilateral unpairing; use the same build for acceptance.

收到已认证的解除事件或本机解除结果后，打开设备页并展示应用自己的结果 sheet，不依赖系统通知权限；可确认或主动重新配对，不自动批准。已有 sheet／模态交互结束后再展示。证书错误不能证明远端撤销。双端同步需 build23 及以上，验收建议使用同一构建。
