# Text transfer and local history / 文本传输与本机历史

Implemented for the **0.4.0 local test candidate**. This does not publish a GitHub Release or install either device. Both Macs need this feature to send text; older versions can still exchange files.

已实现于 **0.4.0 本地测试候选**；本轮不发布 GitHub、不替换两台设备上的应用。文本互传要求双方都有此功能，旧版仍可传文件。

## Use / 使用

Choose **Send Text… / 发送文本…** in the menu bar. The keyboard-focused panel opens below the menu bar and notch, using the file card’s position calculation. The initial target is the file default destination, but selecting another text target does not change that default. Only paired devices appear. If an online device has no active connection, click Connect (or Send once to connect), then send after it is ready. Offline devices and older clients produce explicit guidance.

从菜单栏选择“发送文本…”，在菜单栏／刘海下方打开可输入的面板。初始目标为文件默认发送目标，临时更换文本目标不会改动文件默认目标。只列出已配对设备；在线但尚未连接时，点击“连接”（或先点击一次“发送”建立连接），就绪后再发送。离线或旧版会明确提示。

Type or manually paste multiline plain text. Enter inserts a newline; ⌘Enter sends; Esc closes (an active input-method composition gets its normal cancellation first). Text is limited to 256 KiB in UTF-8; emoji can use several bytes each. Empty strings cannot be sent, but spaces/newlines are not trimmed. The app does not read your clipboard proactively. Closing keeps the draft for this run; quitting discards an unsent draft. The submitted editor is temporarily locked while awaiting receipt. A confirmed receipt clears that draft; failure or the 30-second deadline preserves it. “Unconfirmed” does not prove that the other device failed to receive it. Nothing is automatically resent.

支持多行手动输入、粘贴和普通复制；Enter 换行、⌘Enter 发送、Esc 关闭（输入法正在组词时先正常取消组词）。单条最大 256 KiB UTF-8，emoji 可能占多个字节；空字符串不能发送，空格与换行不裁剪。不主动读取剪贴板。关闭面板在本次运行内保留草稿，退出应用不保存未发送草稿。等待确认时临时锁定已提交输入，确认后清空；失败或 30 秒无确认保留草稿。“未确认收到”不代表对方一定没收到，不自动重发。

The receiver gets a notification with only the device name. Click to view and choose **Copy Text / 复制文本**. URLs remain plain text. No clipboard replacement, link opening or execution occurs automatically. The menu also offers **View Latest Received Text… / 查看最近收到的文本…** for the current run if system notifications are unavailable. It works even with history hidden. A deleted/expired record opens an explanatory message instead. Text uses its own protocol messages, not `.txt` files, and ignores file receive-folder/auto-open preferences. Files can continue transferring while editing; automatic file-card expansion pauses on the editor’s screen.

接收通知只显示设备名称，点击查看后可以“复制文本”；网址保持纯文本，不自动覆盖剪贴板、打开链接或执行内容。若系统通知不可用，可用菜单“查看最近收到的文本…”查看本次运行最近一条收件，隐藏历史时也可使用。已删除／过期记录会显示说明。文本使用独立消息，不生成 `.txt`，不使用文件接收目录或自动打开开关。编辑时同屏文件卡片暂停自动展开，文件传输继续。

## History and privacy / 历史与隐私

**Successful sends and receipts are always recorded locally.** “Show Text History / 显示文本历史” changes entry visibility only. Turning it off asks **Keep and Hide / 保留并隐藏**, **Clear and Hide / 清空并隐藏**, or Cancel. Turning it back on restores access to retained records. The history window lists direction, device, local time and a short preview, newest first; View opens full text and Copy, Delete removes a selected entry, and Clear requires confirmation. Settings always offers Clear, even when history is hidden.

**成功发送和接收的文本始终在本机记录。**“显示文本历史”只控制入口显示；关闭时选择“保留并隐藏 / 清空并隐藏 / 取消”，再打开可看到仍保留的记录。历史按时间倒序显示方向、设备、本机时间和预览，查看后可复制；支持单条删除及确认清空。设置中的清空在隐藏时也可用。

Retention is **Latest 500 entries / 最近 500 条** (default, send and receive combined), **Last 30 days / 最近 30 天**, or **Forever / 一直保留**. Cleaning runs at startup, insertion and viewing. Moving to a finite limit asks for confirmation before removing records outside the limit. Clearing removes existing records; new successful transfers are still recorded. Deletion affects only this Mac, does not remove the other device’s copy, and does not promise secure forensic erasure. Old notification entries expire with the underlying history.

保留方式为“最近 500 条”（默认，收发合计）、“最近 30 天”或“一直保留”；启动、新增、查看时清理，改用有限保留规则前确认删除超出限制的记录。清空只删除现有记录，新的成功收发仍记录。删除只影响本机，不删除另一台设备的历史，也不保证安全擦除；旧通知随记录删除／过期失效。

System SQLite stores message UUID, direction, authenticated device identity, displayed device name, local timestamp and the original text at:

系统 SQLite 保存消息 UUID、收发方向、已认证设备身份、显示名称、本机时间和原始正文，路径为：

`~/Library/Application Support/PeerJetty/TextHistory/history.sqlite`

The directory is 0700 and the database is 0600. This is a local database with readable text for the current macOS user, not an encrypted archive. TLS protects transit. It is outside the source project and excluded from Git/build packages; do not move it into Dropbox or include it in bug reports. Each Mac owns its own retention, visibility and deletions. The app does not sync history in the background.

目录权限 0700、数据库 0600，仅当前用户可访问；正文为本机用户可读取的数据，并非加密归档，TLS 保护网络传输。数据库在源码之外，不进入 Git 或安装包，请勿搬入 Dropbox 或反馈附件。每台 Mac 独立管理保留、隐藏和删除，不后台同步历史。

If SQLite saving fails, the receiver retains the text in memory for this run (up to 500 fallback entries), allows viewing/copying and clearly labels the notification “History Not Saved”. It acknowledges only once that temporary view is available. The sender records only after a matching receipt; sender storage failure also warns instead of claiming persistence. Memory fallback does not survive quitting and is not a substitute for successful disk storage.

若 SQLite 保存失败，接收端在本次运行内暂存文本（最多 500 条），仍可查看复制，并在通知中明确标注“历史未保存”；临时内容可查看后才确认。发送端收到匹配确认后才记录，发送端保存失败同样提示，不能伪装成已持久保存。内存暂存退出后消失，不能代替正常保存。

## Verification / 验证

`Scripts/test-text.sh` runs isolated SQLite, AppKit and loopback TLS tests using temporary files and ephemeral certificates, including the actual 30-second deadline. `--quick` skips only the longer two-engine/timeout/legacy-file suite; it still checks storage, UI and adversarial raw TLS. `--snapshots <directory>` exports input/history/reader screenshots. English and Chinese use the existing `-AppleLanguages` argument. No production Keychain, configuration or history is loaded.

自动检查使用临时 SQLite、隔离 AppKit 和 ephemeral 证书的 localhost TLS，包括实际 30 秒超时。`--quick` 只跳过较长的双引擎／超时／旧版文件联调，仍测试存储、界面和恶意协议输入；`--snapshots <目录>` 可导出输入／历史／查看窗口截图，沿用 `-AppleLanguages` 检查两种语言。检查不读取日常钥匙串、配置或历史。

Physical Air/mini acceptance remains necessary: upgrade both using one test DMG without resetting pairing; send multiline Chinese/emoji in both directions; test a real input method and keyboard shortcuts; click a notification with history hidden; copy explicitly; restart and inspect history; test clear/hide/retention confirmations, offline/old peers, an overlapping file transfer and actual small/notch/external-display placement. Check Documents/macOS management archives only on the corresponding verified machine.

实机仍需：用同一测试 DMG 更新 Air／mini，不重置配对；双向发送中文／emoji／多行，验证真实输入法和快捷键；隐藏历史后点击收件通知并主动复制；重启查看历史；检查清空／隐藏／保留确认、离线／旧版提示、文件并行和真实小屏／刘海／外接屏位置。电脑管理档案仅记录各自已验证状态。
