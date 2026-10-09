# 0.2.0 验证记录

## 2026-10-08: subtle ring angle/stroke/pacing refinement, build21 preview

- PASS: final production build and native motion suite. Ring X tilts +0.45/-0.85 radians, opposing Z twist ±0.70; stroke increases from 12.5% to 14.5% of radius while check centerline geometry and spacing remain stable across square/rectangular sizes.
- PASS: one-and-a-half-turn flip lengthens 620→720ms; tests verify gentler first/last 100ms, monotonic ninth-order motion and finite cleanup. Companion entry/exit uses ease-in/ease-out. Pre-check pause shortens 200→170ms; check remains 600ms. Native pause state, progress caps, acknowledgement, interruption, cancellation, parallel tasks and accessibility passed.
- PASS: isolated 550191a/current previews rebuilt and strict signatures verified; CUA opened and played the candidate. No identity, protocol, configuration preference or card reveal change; no production metadata bump, installation, DMG, push or release. Actual Air/mini appearance remains pending owner review. Existing nonfatal CLT warnings remain.

双环倾角、略粗线条、更柔和起止与更短暂停通过原生检查，保持上轮对勾比例和卡片弹出。

## 2026-10-08: screenshot check and two tilted green rings, build21 preview

- PASS: production build and final native motion suite. Check angle ~72.35°, sampled endpoint clearances and 12.5%-radius stroke remain proportional at 30×30, 60×30 and 60×60. Continuous drawing, inset geometry and native rendering passed. Screenshot estimates are not a claim of pixel-perfect Apple geometry.
- PASS: exactly two rings total (main + one green companion), distinct tilted planes and opposing one-and-a-half-turn motion, finite fade and cleanup. Color reaches green before flipping. Existing 620ms flip / 200ms pause / 600ms check, true progress, confirmation, cancellation, parallel/new task, reduced motion/transparency and spring interruption regressions passed.
- PASS: isolated e7b7af9/current previews rebuilt; retired preference bridge removed because both sides now use fixed timing. No production identity, install, metadata bump, DMG, dependency, push or release. Strict preview signatures verified; full-resolution Air/mini visual acceptance still pending.

参考图对勾与双绿环候选通过原生检查，实际外观供用户预览确认；静态截图无法提供原动画精确轨迹。

## 2026-10-08: fixed timing and one-and-a-half-turn completion, build21 preview

- PASS: production build and final sequential native motion suite. Fixed profile asserts 1220ms relaxed card calibration, 620ms flip, 200ms pause, 600ms check and 1800ms hold. One-and-a-half turns are monotonic with smooth endpoints; true progress, acknowledgement, green-ring pause, trails, cancellation, parallel/new tasks, native spring interruption and accessibility passed.
- PASS: legacy fast/natural/relaxed/unknown speed fields decode successfully and disappear on encoding. Animation toggle write-failure fallback retained; no production configuration or identity accessed.
- PASS: 329 bilingual entries and native categorized settings/layout/callback checks. Settings and animation preview no longer expose a speed selector. CUA reopened the actual candidate and started its fixed preview. Air/mini final visual acceptance remains pending.
- PASS: isolated 74c822a/current previews rebuilt. Before has a preview-only legacy speed type bridge and baseline strings, never part of the production app; strict signatures checked. No metadata bump, installation, DMG, push or release.
- Initial parallel test builds conflicted on shared SwiftPM objects; the final motion suite ran sequentially and passed. Existing nonfatal CLT warnings remain.

固定节奏和一圈半翻转已通过原生检查；设置与预览速度控件均移除，旧速度配置兼容，实际观感待用户确认。

## 2026-10-08: 5% card overshoot and one-turn completion, build21 preview

- PASS: production build and full native motion suite after narrowing the native peak-join sampling interval to measure continuity rather than total return travel. Height overshoot >4.9% and <5.5%; stronger return frequency x1.75 / damping ratio 0.65 keeps secondary undershoot below 0.5%. Native stage join, interruption, stationary target and finite cleanup passed.
- PASS: exactly one forward Y-axis turn, symmetric ninth-order slow/fast/slow curve; rotation 340/620/860ms and existing pause 180/250/320ms. Actual pause displays front-facing green ring, no trails and no check. Progress caps, confirmation, cancellation, parallel transfer and accessibility passed.
- PASS: 5c6d6b6/current isolated previews rebuilt and strict signatures verified. Candidate opened in CUA on Natural. Full-resolution Air/mini visual acceptance remains pending.
- No production version/build metadata, installed app, identity, dependency or installer archive changed. No installation, push or release; existing nonfatal CLT warnings remain.

卡片过冲约 5%、更快且更稳定的返回，以及稍长的一圈翻转均通过原生检查；预览已打开，最终观感待实机确认。

## 2026-10-08: steeper rotation and stronger rebound, build21 preview

- PASS: production build and full native motion suite. Ninth-order smootherstep has symmetric monotonic rotation, flatter endpoints, and a sharper middle velocity peak; explicit derivative checks reject the previous flatter curve. Flip/color/trail synchronization retained.
- PASS: pre-check pause is 180/250/320ms; actual native pause still shows final green front-facing ring, invisible trails and zero check stroke. Confirmation, real-progress cap, hold, cancellation, parallel tasks, reduced motion/transparency and text focus/draft regressions passed.
- PASS: damping 0.53 yields roughly 3% card overshoot (test requires >2.9%, below 3.5%). Return frequency gain is 55%, stiffness x2.4025, applied once. Position/velocity continuity, native peak join, stationary center/targets, interrupted reopen and finite cleanup passed. SDK 27 conservative cleanup estimates are 481/795/1128ms.
- PASS: 3396b22/current isolated previews rebuilt. CUA reopened the candidate and its Natural animation window; this is not claimed as full-resolution or Air/mini final visual acceptance. No production identity/connection, new dependency or continuous task added.
- No product/build metadata, installed app or installer archive changed. Preview-only planned build21; no installation, push or release. Existing nonfatal CLT warnings remain.

更陡旋转、约 3% 过冲、更快返回及延长暂停均通过原生回归；预览已更新并打开，待用户确认实际观感后再生成 build21 安装包。

## 2026-10-08: completion pause and stronger return, build21 preview

- PASS: production build and final full native motion suite. Rotation is monotonic, symmetric, fastest at midpoint with smooth endpoints. Flip/pause durations are 280/500/700ms and 100/150/200ms; continuous check drawing is unchanged.
- PASS: native pause assertions show the ring front-facing and fully green, trails invisible and check strokeEnd zero. Real progress, acknowledgement, cancellation, accessibility, hold, parallel tasks and text focus/draft regressions passed.
- PASS: original outbound trajectory and first peak retained. Two native spring stages join at zero velocity; return frequency x1.35, stiffness x1.8225, damping ratio 0.58. Return is faster, peak below 103.5%, reopening does not compound strength. Native peak presentation does not snap to identity; center and hit area remain fixed.
- SDK 27 conservative two-stage cleanup estimates are 550/910/1291ms, including the native return tail. Return movement is faster without truncating settlement. Finite keyed animation groups replace the single stage; no frame loop or continuous task added.
- PASS: isolated 95ac75a/current preview compilation, both strict signature checks, script syntax and diff whitespace. No engine/identity/dependency/configuration changes. CUA opened the rebuilt Natural preview; screenshot output was again a perspective thumbnail, not full-resolution curve/material acceptance. Air/mini live review remains pending.
- Updated a floating-point duration assertion and moved the old active-rotation accessibility assertion before the newly introduced pause. Native pause/color/stage tests all pass. Existing CLT search-path warnings remain nonfatal.
- Preview-only build21 candidate; product metadata, production installation and archived packages unchanged. No installer generation, push or release.

原生回归通过：中点旋转最快，暂停时绿色圆环完整、对勾与拖影隐藏；峰值交接无跳变，返回加力一次，重开不叠加。预览截图仍为缩略合成，用户实机确认后才生成 build21 App／DMG。

2026-10-04，开发机器 MacBook Air、Apple Silicon arm64、macOS 27.0.1，Apple Command Line Tools / Swift 6.4。最低系统要求 macOS 15；未实测旧系统或 Intel。

自动测试使用独立随机身份及临时目录，不读生产 Keychain/配置。核心测试以可执行断言套件运行，不依赖 XCTest（本机仅有 Command Line Tools）。本机双实例经真实 Network.framework TLS 连接 127.0.0.1，不是模拟网络。

- 核心：配对码对称与 TLS 绑定、错误 commitment、路径遍历、链接父目录与组合链接越界/循环、恶意权限位、超长 UTF-8 同名、损坏/重复清单、文件承诺多次回调与部分失败、损坏文件拒绝、取消清理、同名保留与空文件。
- 联调：两个身份双方确认配对；A→B 中文多层目录/隐藏/空文件/相对链接及同名保护；B→A 文件完整性；双方发送成功必须收到保存确认；128 MiB 传输中取消后清理；可信身份免配对重连；撤销后拒绝未知第三身份。
- 构建与安装：release 构建成功，arm64、最低系统 15.0；本地签名严格校验通过。安装到 Air 的 `/Applications/OpenOnMini.app` 后启动，真实设置窗口可操作，接收服务进入 ready；登录启动开关显示关闭。默认接收目录为 Downloads，仍待用户完成初始化。预览投放区按钮已触发，但未取得可核对的面板截图，实际拖放验收仍待两机阶段。测试报告仅含测试对象及检查结果。

尚待 Air + mini 实机验收：跨设备 Bonjour、首次局域网授权、防火墙/Wi-Fi 隔离、屏幕刘海/外接显示器、Finder 和真实微信文件承诺、多任务投放、重启、地址变化、登录启动、通知点击行为、睡眠断开与恢复、磁盘空间不足。真实 mini 未连接之前，不记为通过。

## 两机验收顺序

1. 两台安装同一版本，设置名称和接收目录，允许局域网访问。
2. 两台开启添加设备，一端发起，比较相同校验码并各自确认。
3. Air 发送中文文件、多选与含空文件目录；mini 核对内容。反向发送一个文件。
4. 已有同名文件再发送，确认原件未覆盖。发送较大文件中取消，确认不产生可见半成品。
5. 退出重开 App，确认无需再次配对。改名、换局域网地址后再发现发送。
6. 撤销授权，确认不能直接发送；重新开启配对并双方确认恢复。
7. 实测 Finder/微信拖拽与两种屏幕投放区，再决定是否启用登录启动和额外文件访问权限。
8. 只在各台实际通过后更新该台电脑的管理档案。


## 2026-10-05：0.2.1 / 构建 3 的本地候选

- release 配置编译与签名校验通过。
- Python 归档保护测试：4 项通过（版本设置、非法/倒退版本、未提交源码阻止打包、拒绝覆盖既有归档）。
- 现有自动验证：7 组核心断言与 7 项 localhost TLS 联调通过；隔离于日常配对配置。
- 版本来源记录和归档工具不修改传输协议或设备身份。
- 新候选尚未安装；设置/关于窗口的实际显示、两台实体 Mac 的新包验收仍待执行。
- 0.2.0 的两机使用正常是用户报告，不能作为新候选的实机验收。

## 2026-10-05 PeerJetty 改名候选 0.2.2 / 构建 4

- 主目标、可执行文件、App、用户界面、源码目录及新安装包文件名统一为 PeerJetty；Original 与历史安装包不改写。
- 核心测试 8 组通过，包括临时目录内的旧配置迁移：保留信任记录、默认目标、接收路径和 bookmark；保留旧文件；新配置优先；新旧损坏配置明确失败；无旧配置时正常初始化。未读取生产配置或生产 Keychain。
- 独立临时身份 localhost TLS 联调 7 项通过；版本工具 4 项通过。
- release 编译与严格本地签名校验通过；核对 App 显示名称、可执行文件、0.2.2/build4、稳定 Bundle ID 和内附 MIT LICENSE。
- Bundle ID、Keychain service、Bonjour、ALPN、SAS domain 与 exporter label 保持原值；真正的旧版/新版双机互通、生产 Keychain 授权、通知、登录启动及首次升级仍待实机验收。
- 没有替换已安装的 OpenOnMini.app，也没有迁移生产配置、修改电脑管理档案、改动 Dropbox 历史归档或上传 GitHub。

## 2026-10-05 用户反馈：0.2.2 双机试用

用户表示“0.2.2 很完美，没什么问题”。记录为用户在其 MacBook Air / Mac mini 上的整体使用反馈，不等同于逐项完成全部边界测试或独立安全审计。用户未提供此次两台设备的系统版本和逐项验收记录，不作推断。本次未由助手远程操作或检查 mini。

## 2026-10-05 图标候选 0.2.3 / build5

用户提供 PeerJetty.png（1254×1254，含透明通道），原样复制到 Assets/AppIcon.png，逐字节核对一致。release 构建与严格签名验证通过；核对 App 版本与 ICNS 的八个尺寸条目。此轮只改图标、版本与文档，不改变投放/配对/传输代码，因此不重复运行既有传输测试。没有安装或操作生产配置，实体 Mac 上的 Dock/Finder 图标显示尚待确认。

mini 无刘海显示器的顶边间隙和自动展开反馈已记录；源码原因与下一步方案见 DISPLAY-PLAN.md。该界面调整尚未实现。

## 2026-10-05 收到后自动打开候选 0.2.4 / build6

- 用户明确要求增加接收端自动打开开关；默认关闭，升级旧配置也关闭，发送方不能更改该设置。
- 核心 9 组测试通过：旧 JSON 解码默认关闭、开关持久化/关闭后重读、关闭时不调用打开、打开失败返回失败项、空列表不调用打开。使用注入回调，不实际启动默认应用。
- 原有隔离身份 localhost TLS 联调 7 项通过。onReceived 仍仅在 incoming.finish() 成功并提交根路径后触发，取消或失败不触发自动打开。
- 真实 SettingsController 的隔离窗口检查通过：600 点高窗口中有两个有效开关（登录启动与收件打开），内容可滚动，未启动网络服务或读取生产身份。
- release 构建与严格 ad hoc 签名验证通过，App 版本与构建号一致。
- 待实机验收：开启后用默认应用打开文档、文件夹的 Finder 行为、关闭后只通知、重启保持及不同默认应用的打开失败反馈；未自动替换用户已安装 App。

## 2026-10-05 DMG 安装容器

- 为已发布 0.2.4/build6 新增 DMG，保持原 App、ZIP、校验及源码提交不变。
- hdiutil 镜像校验通过；只读挂载后 App 全部文件、权限与链接同原 ZIP 一致，严格签名校验通过，Applications 链接正确指向 /Applications；挂载验证后已卸载。
- 版本工具共 6 项测试通过，新增损坏 ZIP 校验阻止解包、已有 DMG 不覆盖的检查。
- 本次未改动应用功能，不重复运行传输测试；图形拖拽安装和另一台设备的首次运行仍由用户/试用者确认。

## 0.2.5 / build7：顶部投放适配，2026-10-05

- 使用 Command Line Tools 成功编译；无 XCTest 的独立 AppKit 检查通过：四组屏幕几何、拖拽会话（陈旧剪贴板／文本／移动距离／释放复位）、隔离剪贴板文件类型，以及控件布局和完整圆角裁切。生成并查看离屏卡片 PNG，文字及控件位于卡片内。
- 本机 AppKit 实际读取：safeAreaInsets.top 为 33.5 点，左右辅助区域间隙为 185 点；此数据只用于验证自动识别，不写成产品常量。未改变显示缩放或其他系统设置。
- 核心 9 组检查、隔离 localhost TLS 集成 7 项、版本／归档工具 6 项通过。首次 localhost 与剪贴板检查受沙箱限制，允许相应本地服务后通过，不是协议或文件类型代码故障。
- 未运行生产传输引擎或访问生产配置／钥匙串，未替换已安装 App。
- 几何与离屏快照不代表实际 Finder 拖拽、mini 显示效果、原生 Split View／Space、自动隐藏菜单栏、多屏热插拔及文件承诺全部通过；实机清单见 DISPLAY-PLAN.md。0.2.5 是本地测试候选，0.2.4 仍是公开正式版。

## 0.2.6 / build8：避开系统顶边手势，2026-10-05

- 5 组屏幕几何／模拟接近路径、拖拽会话、隔离剪贴板类型和 AppKit 控件布局检查通过。覆盖无刘海、有刘海和不同顶部安全高度、负坐标、自动隐藏菜单栏；真实顶边不属于触发区，模拟向上路径先进入卡片下方接近区。测试路径不代表真实高速拖动或系统事件时序已通过验收。
- 本机实际屏幕读取：顶部安全高度 33.5 点、刘海宽度 185 点；卡片为 (695, 967, 320, 76) 点。卡片位于最终位置直接显示，文件触发不执行从顶边滑落动画。
- 未修改系统手势设置、安装状态、生产配置、身份或协议；只调整投放显示、触发区域与使用提示。
- mini 和 Air 上的 Mission Control 冲突效果、Finder／聊天软件实际拖拽、快速拖动、全屏及 Space 等待用户复测。继续拖到真实顶边仍可能触发系统手势，程序不承诺拦截 macOS 行为。

## 2026-10-06：0.3.0 / build9 中英文国际化

- 用户报告 0.2.6 测试没有问题；作为使用反馈记录，未推断其已逐项验证全部显示/系统边界。
- 资源检查通过：196 个中英文文本/数量条目，key、格式参数、复数规则、源码引用及远端诊断白名单一致。
- 显式英文及简体中文检查通过：地区语言匹配、不支持语言回退、缺失翻译回退英文、英文单复数、双数量变量、位置参数、设备名中的中文/百分号/emoji 原样显示。
- 可选拒收诊断中英文渲染、错误参数数目、超长字段和不允许的格式 key 回退检查通过；新消息可由旧结构解码，旧消息可由新结构解码。
- 两种语言设置页在 650×600 的隔离 AppKit 检查通过；截图人工检查文字换行与控件布局。没有启动生产 AppDelegate、读取日常配置或 Keychain。
- release App 构建、严格签名校验通过；将测试可执行文件与实际 App 资源复制到独立临时 App，在中英文下运行检查通过，证实不依赖 SwiftPM 构建资源目录。原生 Bundle 本地化权限说明与数量格式加载通过；这不等于实际 macOS 权限弹窗已人工验证。
- `Scripts/test.sh` 分别在英文和简体中文进程下通过 9 组核心断言、7 项隔离 localhost TLS 联调；不把同进程模拟设备当成两台实体设备。
- 英文投放卡片回归通过：5 组屏幕几何/拖动路径、拖拽会话、隔离粘贴板文件类型及卡片控件/裁切检查。顶边触发逻辑保持 0.2.6 实现。
- 下一步实机验收：Air 中文、mini 英文，检查菜单/配对说明/通知及双向单文件、多文件、文件夹、同名文件；切换自动打开并确认其仍为接收端设置。检查原有配对保留、拒收提示及真实权限对话框。真实旧版/新版互通也待单独验收。
- 本轮没有自动安装或上传 GitHub，没有修改系统语言、生产配置或电脑管理档案；公开 Latest 仍为 0.2.4/build6。

## 2026-10-06：0.3.1 / build10 应用内语言设置

- 设置新增本机语言选择；保存后退出重开生效，不自动终止或重启传输。旧安装没有自定义值时跟随系统；选择系统清除自身覆盖，非法值安全回退。UserDefaults 与配对/接收配置分离。
- 中英文资源检查通过（200 个文本/数量条目）；两种语言的 650×600 设置布局、选择器预选状态与真实 action 回调检查通过。隔离偏好 suite 验证保存/重新读取、覆盖相反系统语言、切回系统及未知值回退。中英文截图人工检查通过。
- 移除微信权限按钮、事件和翻译资源；源码核实原按钮只跳转完全磁盘访问页面，不实现独立权限或微信传输。File Promise 和文件 URL 接收代码不变。没有撤销用户已授予的系统权限。
- 本轮未改传输/配对实现，不重复全部 TLS 联调；已有国际化诊断/旧 JSON 兼容检查仍通过。实体设备上的退出重开、完整菜单/通知语言、微信实际拖拽仍待人工验收；系统弹窗不由此应用内语言偏好控制。

## 2026-10-06：0.3.2 / build11 手动检查更新

- 更新解析和状态检查通过：数字版本比较（含 0.3.10 > 0.3.2）、非法/溢出版本、正式/草稿/预发布判定、页面仓库/标签/HTTPS 边界、缺 DMG、不可信安装包链接、正文截断、响应体限制和异常状态码。
- 隔离 URLProtocol 检查通过：成功、404、限流、超时及主运行循环回调；请求只指向配置的公开接口，不带登录令牌。
- 英文下真实只读请求 GitHub Latest 接口通过，返回 0.2.4。没有为了测试制造虚假公开版本，也未上传任何 Release。
- 中英文更新窗口布局与状态检查通过：有新版显示页面入口，同版/本地领先不提供降级入口，失败清理旧入口，无正式版可查看仓库 Releases。两种语言截图人工检查通过，说明作为纯文本显示。
- 中英文设置页布局、语言偏好/诊断兼容检查通过；资源检查通过，216 个文本/数量条目。
- 不改变配对、传输、文件保存或身份，不重复全部 TLS 联调。真实菜单操作、旧版升级到未来公开新版和各设备网络环境仍需验收。此阶段只有主动检查和手动安装引导，无自动下载/安装、包签名验证或后台轮询。

## 2026-10-07：0.3.2 正式发布验核

- 用户表示当前无问题并要求 Release，记录为整体试用反馈，不推断全部设备/网络/显示边界逐项通过。
- 发布前原 ZIP/DMG 校验通过，ZIP 内 App 版本 0.3.2/build11、干净源码提交和严格签名验证一致；未重新编译。
- 发布后确认 v0.3.2 为正式 Latest，标签指向 `a5316f42c45122107cac2ad3843a443f05578cb5`，唯一上传附件是 DMG，GitHub 资产 SHA256 与本地归档一致。没有远程安装、操作实体 mini 或发送消息给室友。


## 2026-10-07：0.4.0 / build13 文本与本机历史候选

- 新的 `Scripts/test-text.sh` 完整套件通过：UTF-8 256 KiB 边界（含 emoji）、Unicode／空格／CRLF／NUL 原样 JSON 与 TLS、空串拒绝、可选 hello 字段的旧解码兼容、256 条去重缓存、同 ID 不同正文拒绝。
- 双 ephemeral 身份的 localhost TLS 通过：未授权本地发送拒绝、接收端可查看后才确认、发送方确认前不成功、双向文本、1 MiB 文件与文本并行、1 条活动＋20 条等待、实际 30 秒无确认、迟到确认不误确认下一条、不自动重发。旧能力字段缺失的连接拒绝文本且仍可传文件。
- 原始 TLS 对端检查通过：只有 TLS、尚未完成应用授权时提前发文本被拒绝；完全相同的重发仅重复确认、不重复交付；冲突正文、超限正文、无关 UUID 确认关闭连接；最大 UTF-8 正文可正常接收。
- SQLite 隔离检查通过：目录 0700／数据库 0600、含 NUL 的正文重开后完整、重连重复记录对应固定本机 ID、过期重发重新可查看、收发合计 500 条／30 天查看清理／永久保留、单删／清空／通知目标过期、隐藏不停止保存、旧配置的默认值、实际 SQL 写入失败及事务回滚、数据库符号链接拒绝。
- AppKit 中英文检查通过：顶部输入可接焦点、Enter 换行／⌘Enter 发送／Esc 关闭、失败和关闭后保留草稿／确认后清空、输入法 marked-text 防误发送、450×300 面板控件及小屏／刘海／外接屏几何、私有测试剪贴板的主动复制与原文保留、通知正文仅设备名称、未保存提示；设置控件默认、隐藏和保留预选状态验证通过。
- 检查并修正编辑与活动文件进度卡片的遮挡：同屏进度卡片也暂时收起，后续进度更新尊重编辑状态，关闭面板后恢复活动进度；网络文件任务继续。隔离界面检查通过。
- 英文核心回归通过（9 组）及既有文件 TLS 联调通过（7 项）；文件投放卡片 5 组几何／路径、文件粘贴板类型及卡片布局通过；手动更新解析、隔离响应与英文窗口回归通过。
- 两种语言资源审查通过，271 个文本／数量条目；两种语言的设置页 650×600 布局通过，截图检视顶部输入、历史及设置下半页，未见文字或控件越界。日期按应用语言格式化，用户设备名称和正文不翻译。
- 实机未代验：Air／mini 双向与 Bonjour、通知点击授权、真实中文输入法、小屏／不同缩放／刘海／无刘海／Space，以及安装后重新打开的历史、隐藏／清空／保留确认。测试不操作日常身份、配置或历史；未安装或公开发布。实机清单见 TEXT.md。

- 最终键盘验核确认：裸菜单栏应用没有标准 Edit 菜单时，原生 NSTextView 不处理 ⌘A；文本视图明确分发 ⌘C／⌘V／⌘X／⌘A／撤销／重做到原生编辑动作，⌘Enter 同时覆盖原生 key-equivalent 分发。隔离快捷键检查通过；无草稿时默认跟随当前文件目标，有草稿时保留临时目标。
- build12 仅为内部归档，保留但不作为本次交付；最终候选为 build13，产品版本同为 0.4.0。

- 交付验核通过：`outputs/releases/0.4.0-build13/PeerJetty-0.4.0-build13-arm64.dmg`，只读挂载后确认 App 为 0.4.0/build13、ARM64、干净源码 `18ffe6bf5c88259f559f8e1eec8313516f6ca6f8`、旧 Bundle ID 保持；严格签名与归档校验通过，中英文资源齐备，无私有身份、配置或 SQLite 数据。镜像已退出。SHA256：`0f4be36f756d44b8298a1aed358d256fe9a954895e8e0a5546cf38f53955b9c7`。
- 使用测试可执行文件及最终 App 的真实资源组成临时隔离 App，中英文两次均通过；脱离构建资源目录后可正确加载界面、数量和原生权限说明。此过程没有启动实际 AppDelegate，安装后操作仍待实机验收。

## 投放卡片文字与居中调整 — 2026-10-07

保留卡片 76 点高度、宽度计算、屏幕位置和触发逻辑。提示改为 15 点半粗体，设备名改为 13 点中等字重、85% 白色；两行整体居中，传输时为底部进度条留空间，取消按钮 12 点并与第一行对齐。长名称仍在中间省略，悬停可看完整内容。

- `Scripts/test-drop-presentation.sh`：应用构建、原有拖拽与五组屏幕几何检查通过；新增中英文、320/364 点宽度、待投放/拖入/读取/传输/成功/失败共 24 组布局检查，验证文字高度、居中、控件间距及完整名称提示。
- 独立 AppKit 视图截图保存在忽略目录 `outputs/validation/drop-typography/`，已检查两种语言六种状态。测试不运行生产网络、身份或配置；使用独立测试剪贴板。初次受沙箱限制的文件 URL 检查失败，获准访问图形会话后完整检查通过。
- 待用户确认 Air 与 mini 的实际阅读效果。未安装、未生成新安装包、未改变产品版本或发布 GitHub Release。

## 分类设置窗口 — 2026-10-07

原生 NSToolbar 偏好设置窗口，顶部通用／设备／传输／文本／关于五个分类；初始内容区 650 × 520 点，小屏幕降低高度，各页独立滚动，底部共享状态。沿用操作回调、配对与配置，不添加动画功能。首次设置在通用页；菜单栏添加设备切到设备页；切换分类保留名称编辑。关于页提供版本来源、MIT 条款、检查更新及折叠维护操作。

- `Scripts/test-localization.sh`：中英文各 20 组分类／深浅色／520 与 340 点高度布局；检查真实内容高度、横向边界、按钮文字、页面显示及滚动起点。语言、设备离线显示、历史隐藏与保留、登录／自动打开、全部既有按钮操作回调、原生文本字段焦点及切换后草稿均通过隔离检查。测试不启动生产 App，不调用真实配对、清空、退出或系统设置操作。
- 视图截图位于忽略目录 `outputs/validation/settings-tabs/`；确认分类内容紧凑并贴近顶部。修正了内容纵向拉伸和偏好高度约束导致窗口尺寸不符的问题；测试等待 AppKit 绘制周期再捕获。
- 中英文打包资源与搬迁后的测试 App 检查通过：从 App 内读取语言、权限说明和图标，不依赖源码构建缓存。
- 应用重新构建为 `outputs/PeerJetty.app`；普通开发构建仍沿用 0.4.0/build13。历史 DMG 不覆盖，不安装、不发布；构建来源请查看关于页／build-info.json。
- Air／mini 的实际观感与输入法、真实操作验收待用户完成。文本发送面板样式和可选动画仍是后续工作。

## 2026-10-07 文本界面统一（本地开发）

- 改动限定于文本窗口布局、双语文案和隔离测试；协议、数据库、配对身份未更改。
- 发送默认 560 × 350 点并检查 450 × 300；查看默认 580 × 400、最小 360 × 200（包括英文保存失败警告换行）；历史默认 650 × 450、最小 500 × 350，支持缩放和 64 点原生列表。
- 中英文、深浅色、长设备名、Unicode 多行、空占位、长正文原样复制、焦点、输入法组合、Enter／⌘Enter／Esc、草稿成功／失败、复制反馈、历史按消息 ID 保持选择、分页与删除／清空回调通过隔离检查；确认仍由原控制器处理。
- 完整文本套件通过：私有 SQLite 保留／清理／隐藏／保存失败、双向临时 TLS、授权和确认、防重复、文件并行、队列上限、实际 30 秒超时及旧版无能力字段的文件兼容。最终源码通过英文完整套件与简体中文快速套件，未改变传输逻辑。
- 截图位于忽略的 `outputs/previews/text-ui/en` 与 `outputs/previews/text-ui/zh`；不包含生产数据。App 构建目标为 `outputs/PeerJetty.app`，沿用 0.4.0/build13；历史 build13 DMG 保留，动画完成后再集中生成下一份安装包。
- Air／mini 真实输入法、通知点击、历史隐藏与确认、不同显示器观感和真实双机收发仍待用户验收。本轮不安装、不推送、不发布。

## 2026-10-08：原生玻璃与轻微弹性动画，0.4.0/build14 本地候选

- macOS 26+ 标准 NSGlassEffectView，macOS 15 NSVisualEffectView 兼容路径；保留 76 点卡片、原几何和触发判定，正文不使用玻璃。通过在新系统上强制兼容分支的隔离检查；没有 macOS 15 实机证据。
- 动画默认开启，旧配置解码与关闭后的保存／重新读取通过；系统 Reduce Motion 的可注入策略覆盖且保留选择。设置开关默认、回调、恢复，以及两种语言各 20 组浅／深色／小窗口布局通过。
- 原生 AppKit 动态检查通过：立即投放且窗口几何不变、短反馈替换而不堆积、结束后移除、成功 ID 去重、失败无成功反馈、收起后重开不被旧回调隐藏、动画中途关闭立即收稳；文本焦点立即可用、关闭保留草稿。
- 投放回归通过：5 组屏幕／路径、拖拽会话、文件 URL 与非文件粘贴板判定、24 组双语居中／长名称／进度与取消布局。原生玻璃内容容器与兼容圆角检查通过。
- 本轮完整英文文本套件与中文快速套件通过：Unicode／换行、大小边界、临时 SQLite、隐藏／保留／错误、输入法／快捷键／复制／草稿、临时双向真实 TLS、授权／确认／防重复、20 条队列、实际 30 秒超时、文件并行及旧版兼容。核心 9 组与临时双实例文件联调 7 项通过；发布工具 6 项通过；297 条双语文案检查通过。测试不读取日常身份或历史。
- 一轮短时 UI 进程对比：旧卡片 1 秒空闲 CPU 0.0034 秒、30 次状态切换 CPU 0.0826 秒、隐藏 1 秒 CPU 0.0002 秒、峰值 RSS 59.6 MiB；新卡片分别 0.0027／0.0880／0.0005 秒、61.1 MiB；两者收稳后自定义动画均为 0。采样小、非统计基准，未含 WindowServer／GPU或完整应用已有轮询，不据此承诺零成本。代码没有新增持续任务／自定义逐帧循环。
- 隔离预览：`outputs/GlassMotionPreview.app`，由 `Scripts/test-motion.sh --deliver-preview` 生成，提供回放、进度／结果、立即投放、浅深色、动画开关、文本输入和退出；无真实设备连接、发送或日常数据访问。原生界面自动化服务两次返回 timeoutReached，无法抓取真实合成画面，因此不宣称已目测玻璃效果。
- 待实机：Air／mini、刘海／普通显示器、复杂背景可读性、快速操作与真实拖放、文本焦点／输入法／复制／确认；开启／关闭系统减少动态效果、减少透明度、增强对比度和玻璃偏好。未修改系统偏好；玻璃偏好滑块对该控件的影响尚未核实。也未采集双机长时间资源／GPU数据。
- build14 仅本地候选，打包工具要求干净源码、固定提交、签名校验及不可覆盖归档；build13 保留。不安装、不推送、不发布 GitHub Release。

## 2026-10-08：菜单、设置与收起问题，0.4.0/build15 本地候选

- 菜单严格六项及全部回调通过独立原生检查。随机隔离 App 标识下，第一进程默认显示、关闭并保存，第二进程成功恢复隐藏；可见性 KVO、重复通知去重、系统可移除但不退出、显示／隐藏对应 accessory／regular 的 Dock 策略检查通过。未读取或写入生产可见性偏好。
- 通用菜单栏开关的默认值、回调、系统状态同步；文本历史／最近文本入口；手动连接信息折叠与“尚未就绪”；长状态详情可用性、完整 Unicode 原文、只读纯文本与滚动通过。AppDelegate 在设置窗口之外缓存监听端口，创建窗口后再次计算地址；启动前点击发送文件会打开设置，无默认目标会打开设备页。
- 英文与简体中文各 20 组浅／深色／小高度设置布局通过。307 条双语文案及格式字段检查通过。正常版本使用产品版本，构建号仍在诊断、Info.plist 与归档中。
- 动画检查通过：完成收起时，隐藏回调读到 alpha=0，回调隐藏窗口后恢复 alpha=1；关闭动画时完成待关闭操作、快速重开取消旧关闭、文本焦点与草稿仍正确。卡片几何／拖放会话／粘贴板及 24 组原排版回归通过。
- 英文完整文本套件通过，包含真实临时双端 TLS、Unicode/大小、SQLite/隐藏/保留/失败、焦点/快捷键/草稿、确认/防重复、文件并行、队列20、实际30秒超时、旧版兼容。核心9组、文件双实例7项及发布工具6项通过。可见性逻辑不操作引擎或身份，隐藏不设置退出行为；隐藏期间的真实双机收发仍列为实机验收项。
- 隔离原生预览已重新生成；界面自动化请求返回 timeoutReached，未能录制真实合成画面。末帧顺序有原生窗口自动断言证据，但不宣称已在两个物理显示器上目测消除所有闪烁。设置布局截图位于忽略的 outputs/previews/menu-ui。
- 待 Air／mini：Dock 点击恢复与保留设置窗口、退出重开隐藏状态、系统菜单栏禁用／移除的实际路径、隐藏时双向文件和文本、通知打开、收起无闪回与快速重开。未修改系统偏好或安装生产 App。
- 仅本地 build15 候选；保留 build13、build14，不推送或发布。后续外观与 1.0.0 另行安排。

## Floating glass and independent icons / 悬浮玻璃与独立图标 — 2026-10-08, build16

- `Scripts/test-menu.sh`: six actions, template image, native autosave across processes, internal KVO suppression, all four saved menu/Dock combinations, legacy migration, JSON roundtrip, temporary recovery/hide, crash-style restart, configuration save failure, external removal with failed persistence, public manual/login/service event classification pass. No production configuration or identities are accessed.
- `Scripts/test-localization.sh -AppleLanguages '(en)'` and `'(zh-Hans)'`: 310 bilingual keys; 20 light/dark/short-window layouts per language, independent Dock callback, temporary notice with both saved switches off, temporary hide action and rollback pass.
- `Scripts/test-motion.sh --deliver-preview --static-checks`: native glass and forced macOS15 frosted fallback, original 320×76 card with 32pt margins, noninteractive padding, static radius16/down6 shadow with .24/.38 opacity pass. `outputs/GlassMotionPreview.app` is an isolated interactive renderer, with no production network, identity or history. Interactive previews now start directly; checks run separately.
- Drop/presentation checks pass: five screen geometry groups and 24 bilingual card layouts. Text checks pass: UTF-8/JSON/legacy compatibility, SQLite retention and permissions/failure, input/focus/drafts, two ephemeral TLS peers with bidirectional text, parallel file transfer, duplicate/unauthorized handling and real 30-second unconfirmed timeout. Core checks: nine groups and seven integration checks pass. Six release-tool tests pass.
- **Full animated rendering is unverified in this session.** The unmodified build15 tests and original animation code also fail the feedback-settlement assertion; with bounded diagnostic cleanup, the window-fade completion likewise fails. The diagnostic animation edits were backed up and removed; production `Motion.swift` remains unchanged. The native UI tool reports this Mac is locked and cannot automatically unlock it. Static layer/state checks are not proof of real composition, motion, GPU cost or edge click-through.
- Physical acceptance remains: unlock Air and inspect light/dark/complex backgrounds, Reduce Transparency/Increase Contrast, unclipped shadows and no dismissal flash. Mini/macOS15, ordinary/Retina icon clarity, exact border click-through and file drag across screens, login/manual cold launches, system removal and hidden bidirectional transfer require device checks. The existing 50ms sampler controls mouse passthrough; verify edge handoff latency physically.
- Build16 is a local test candidate, not a public Release. Preserve build13/14/15 archives; no installation, push or identity change.

菜单、配置迁移、四种组合、临时恢复、保存失败及公开启动事件分类通过隔离检查；中英文各 20 组布局、310 项文案、临时说明与隐藏按钮通过。静态投影参数和透明边距命中通过，原有拖放、文件和文本隔离回归通过。

**真实动画与合成未验收**：当前 Mac 锁屏，原始 build15 动画实现／测试也不能正常结束；本轮用于诊断的动画改动已撤回，产品动画保持不变。需解锁后及在 mini 上检查真实投影、辅助显示、边缘点透、跨屏和无闪回，并验证登录／手动启动和隐藏时双向收发。仅交付本地 build16，不安装、推送或公开发布。


## Relaxed motion and confirmed ring / 从容动画与确认圆环 — 2026-10-08, build17

- Full `test-motion.sh` passed in the unlocked graphical session: exact speed table, legacy/unknown fallback, persistence and failed writes, constant spring damping, monotonic real progress, unknown/preparation and waiting-for-confirmation states, confirmed two-stroke success, disabled/Reduce Motion settlement, captured timing, hold protection, duplicate/parallel/new-transfer interruption and stale callback protection.
- Native window tests passed: immediate fixed drag geometry, bounded effect cleanup, order-out before opacity reset, rapid reopen and toggle mid-dismissal; text focus, draft and close/reopen remain correct. Preview refuses registered file-drop types and uses a private policy without production identity/network/history access.
- `test-drop-presentation.sh` passed five geometry groups and 24 bilingual layouts; `test-localization.sh` passed 320 synchronized keys and 20 light/dark/small-window groups per language, including speed callbacks/rollback and preview controls.
- `test-text.sh` passed Unicode/JSON framing, SQLite retention/failure, AppKit input/draft, hostile TLS cases, ephemeral two-peer text and parallel-file transfer, real 30-second timeout and old-peer compatibility. `test.sh` passed nine core groups and seven integration groups. Tests use isolated identities/data.
- Native captures in ignored `outputs/previews/motion-build17/`: Fast 50 frames (~5.0 s), Natural 60 (~5.9 s), Relaxed 65 (~6.5 s), encoded using capture timestamps. Contact sheets visibly show real glass, byte ring, check and disappearance; no obvious clipping. Captures are low resolution (~192 × 194) and ~10 fps: they do not prove full-resolution readability, exact spring curves or absence of a one-frame flash. Native callback/order tests cover the dismissal invariant. Physical Air/mini checks remain pending.
- Short isolated process comparison against build16 `52a3415`: baseline idle CPU 0.0035 s / 1 s, 30 updates 0.0614 s, hidden CPU 0.0004 s / 1 s, peak RSS 61.3 MiB; current 0.0036 / 0.0470 / 0.0003 s, 59.5 MiB. Both settled with zero custom animations. This is a small sample, excludes WindowServer/GPU/full app polling and does not establish a performance improvement; no new continuous task or frame loop was introduced.

完整动画测试已在解锁图形会话通过，覆盖配置、三档精确时长、阻尼、真实进度、确认／失败、停留、去重、并行与中断。中英文、布局、文本及文件隔离回归通过；真实截帧可见玻璃、圆环、对勾与收起，但低分辨率约 10fps，不据此宣称全分辨率观感或单帧无闪烁。短时独立进程开销与 build16 接近，不含系统合成／GPU，不作性能提升承诺。Air／mini 实机及辅助显示、跨屏、边缘点透、实际手感仍待用户确认。保留旧归档，仅交付本地 build17，不自动安装、推送或发布。


## Jelly reveal and inset check / 果冻弹出与对勾留白 — 2026-10-08, build18

- Read-only Apple completion references are linked in APPEARANCE.md. They establish the confirmed-completion/check/dismiss sequence, not exact geometry or timing; our path/curve is original.
- `test-motion.sh --deliver-preview` passed after the desktop was unlocked: legacy speed/persistence tests, monotonic progress, confirmation, hold, duplicate/parallel/new-transfer callbacks, window dismissal ordering, reopening, animation-off/Reduce Motion and text focus/drafts. An earlier locked-session attempt failed the native dismissal check; it is superseded by the successful unlocked run, not silently treated as passing.
- New focused checks passed: buffered initial velocity, 86%/62% unequal-axis start, height overshoot bounded between 104–105%, peak near the timeline midpoint, smooth identity endpoint, compensated AppKit anchor with fixed visual center, unchanged hit area/transparent padding, finite 61-sample animation cleanup. Check elbow measured ~75.7°; conservative stroke clearance exceeds 2.5 points, and short-stroke boundary uses actual path lengths.
- `test-drop-presentation.sh` passed five screen groups, isolated pasteboard checks and 24 bilingual card/control layouts. Both language runs of `test-localization.sh` passed 320 keys and 20 appearance/short-window layouts each. No protocol, identities, database or transfer-engine change.
- Final native preview captured 60 real frames (~6.3 s) in ignored `outputs/previews/motion-build18/natural.gif`, with timestamps/contact sheets. Real glass, progress, inset check and disappearance are visible. UI capture is low-resolution and ~10 fps; action/capture latency can miss the beginning of the reveal, so this does not establish exact subjective spring feel or single-frame absence of flash. Native ordering/curve checks cover objective invariants; full-resolution Air/mini acceptance remains pending.

已解锁会话完整动画测试通过，包含新的形变缓冲、固定中心与命中、对勾留白检查，以及确认／停留／中断／减少动态效果回归。中英文和布局通过；原生低分辨率截帧可见玻璃与新对勾，但采样可能错过展开起始，不能替代用户在 Air／mini 的实际观感确认。保留 build17，生成独立本地 build18；不自动安装、推送或公开发布。


## Spring momentum and capped ring / 弹簧初速度与限速圆环 — 2026-10-08, build19

- `test-motion.sh --deliver-preview` passed: nonlinear near/far speed contrast, finite centered shape, real progress targets, confirmation/hold, duplicate/parallel/new-transfer protection, native dismissal/reopen ordering, animation-off/Reduce Motion and text focus/draft regression.
- Added 14,472 sampled trajectory checks (3 rates × 6 delta sizes × 4 initial velocities × 201 points) for monotonicity, never leading actual targets and derivative bounded by cap. 100 successive updates per rate preserve position/velocity; finite final catch-up settles with zero velocity. Immediate success can extend the fill; native tests verify nominal deadlines cannot hide it and hold starts after actual completion.
- An initial duplicate-success assertion still waited the old nominal duration; it failed while the new valid extended fill was running. The test now waits actual glyph success duration; the subsequent complete run passed.
- `test-drop-presentation.sh` passed five geometry groups and 24 bilingual card layouts; English and Chinese `test-localization.sh` passed 320 keys and 20 native appearance/small-window layouts each. No engine, protocol, pairing, database or acknowledgement changes.
- Native Natural preview captured 75 real frames (~7.9 s), saved with timestamps in ignored `outputs/previews/motion-build19/`. Contact sheets show real material, ring fill, delayed check and eventual disappearance. Capture remains low-resolution/~10 fps and can miss the first spring frames; it is not proof of exact subjective feel or single-frame flash absence. Air/mini full-resolution acceptance remains pending.

完整动画及双语／几何回归通过；新增 14,472 个轨迹采样检查，覆盖限速、单调、不超真实进度和频繁更新连续性，实测瞬间成功的延长补齐及停留保护。原生低分辨率回放可见更慢的圆环／对勾；Air／mini 实际手感仍待用户确认。仅本地 build19，保留 build18，不安装、推送或发布。


## Success ring flip experiment / 成功圆环翻转试验 — 2026-10-08, build20

- Full `test-motion.sh --deliver-preview` passed on the unlocked desktop, including existing spring/rate/hold/native window/text checks and new two-turn/color/trail tests. 404 angle samples are forward-only and end at 4π; ring and all three lagged ghosts end facing forward. Color transition shares the flip interval; check begins only after the rotation ends.
- Fixed six shape layers (track, three ghosts, arc, tick), at most 14 custom effects for this sequence. Gray stationary track is hidden during success. Models retain identity transforms and zero ghost opacity; every keyed effect is finite. Live Reduce Transparency/Increase Contrast removes ghost effects without cancelling success; disabling motion settles once; new progress invalidates old flip/ghost/completion callbacks.
- `test-drop-presentation.sh` passed five geometry groups and 24 bilingual layouts; both `test-localization.sh` language runs passed 320 keys and 20 native layout/appearance groups each. No protocol, database, identity, actual transfer or text success change.
- Captured 90 native preview frames (~9.3 s) with timestamps in ignored `outputs/previews/motion-build20/natural.gif`. Contact sheets visibly show the circle becoming edge-on/front-facing, blue-to-green progression, then the check. Capture remains low-resolution/~10 fps: faint trails and precise curvature still require full-resolution Air/mini acceptance. No long-run GPU benchmark is claimed; no continuous task, particle emitter or custom display loop was added.

两圈翻转、三层渐淡拖影、颜色区间与对勾开始顺序检查通过，并回归了限速、停留、取消、新任务、系统辅助显示和原生窗口行为。真实低分辨率截帧可见圆环侧转、蓝绿变化与随后对勾；细微拖影及主观观感仍需 Air／mini 全分辨率试用。仅交付 build20 本地视觉试验包，保留 build19，不安装、推送或发布。


## 2026-10-08：UI 与动画长期规范 / UI and motion development rules

- Inspected the current SwiftPM manifest, native UI controllers, shared text helpers, motion policy/profile/effects, screen geometry and existing rules. No external package dependencies; no React/SwiftUI runtime or web UI was found in the current application targets.
- Integrated concise rules into root AGENTS.md; added Docs/design/{DESIGN_SYSTEM,COMPONENTS,MOTION}.md and linked them from both READMEs, CONTRIBUTING and APPEARANCE. Existing behavior, compatibility and release rules retained.
- Checked current official HeroUI documentation/MCP scope and Motion references. Both remain design references. Official HeroUI links are the documentation access path; no MCP process, UI package, Node runtime, global Codex configuration or third-party source was added.
- PASS: `Scripts/swift.sh build --product PeerJetty`; `swift package --disable-sandbox describe --type json` confirms zero external dependencies. Build emitted existing Command Line Tools search-path warnings and completed successfully.
- PASS: local Markdown links resolve; `git diff --check` clean. No production UI/configuration, protocol, identity, version metadata or archived package changed. No new GUI/device acceptance is claimed for this documentation/rule task; component findings are source-based.

已完成原生技术栈与组件清单核查、项目规则整合及官方参考入口接入。没有安装不适用的 Web 依赖或 MCP；构建与文档链接检查通过。本轮不改运行中的界面、版本和安装包，不声称新增双机视觉验收。build20 翻转拖影继续标为待验收实验，普通新动画采用克制的 150–300 毫秒基准，现有明确选择的慢速弹簧／成功反馈保留例外。

## 2026-10-08：分组设置与平滑完成序列，build21 前置预览

- PASS: SwiftPM build and full native motion suite: 92%/82% card start, rebound below 102%, fixed geometry, finite effects, rate-limited progress, extended hold, confirmation/deduplication/parallel transfers, cancel/reopen, mid-effect disable, Reduce Motion and optional-trail suppression. New timeline, flip endpoint and check-continuity assertions passed. Effects share a captured epoch.
- PASS: English/Chinese localization checks, 334 keys, original callbacks/drafts/history/icon switches/disclosures/details, intended group counts and 20 light/dark/short-screen layouts per language. English native snapshots generated in ignored outputs.
- PASS: drop checks: five geometry/path groups, isolated pasteboard discrimination and 24 bilingual card layouts. No physical target change.
- PASS: preview-design.sh separately compiles Before (19e5343/build20) and After (current source). Native UI observed all five new settings pages and successful switch into old settings. Harness constructs view controllers and sample values only: no engine/store/production identity/real transfers. No dependencies added.
- CUA replay: Fast 55 frames/6.07s, Natural 75/8.12s, Relaxed 100/10.76s. Some captures show a perspective window thumbnail rather than full-size foreground composition. They supplement state/timing checks, NOT full-resolution material/curve acceptance or proof of no single-frame artifact. Use native Before/After for owner acceptance.
- A restricted-session motion attempt failed the visible-card assertion without the required native window environment; the complete graph-session rerun passed. No product behavior was changed to accommodate the environment. Existing Command Line Tools search-path warnings remain nonfatal.
- No continuous animation tasks/layers/particles added; no new GPU/WindowServer benchmark claim. Air/mini full-resolution appearance and actual bidirectional transfers remain pending.
- Version metadata, production installation and release archives unchanged. build21 App/DMG awaits owner preview confirmation. build20 DMG remains present: SHA256 4f0edca6900d094fd0ff3e84602fce351cf8eeb79e0d45a1a17bbeb2a594bbf7.

已完成分组设置、减轻压缩、统一序列时钟与两笔衔接，通过隔离原生回归。旧新版模拟预览已可用；录制受窗口缩略合成影响，不能替代双机全分辨率验收。用户确认预览后再打 build21，不自动安装、推送或发布。

## 2026-10-08：共享原生物理弹簧，仍为 build21 前置候选

- PASS: SwiftPM production executable build; full `Scripts/test-motion.sh` native graph-session run after final code. New checks cover mass/damping, native 380/620/880ms settling estimates, 92%/82% initial shape, rebound below 102%, analytical position/velocity continuity, native early presentation bounds and stationary visual center, repeated reveal without restart, dismissal/reopen without reset or stale hide, finite cleanup. Existing real-progress cap, confirmation, parallel/deduplication, flip/trails/check stages, hold, accessibility and text draft/focus checks passed.
- Shared SpringParameters uses native settlingDuration rather than a fixed cutoff. Feedback retargeting uses stored analytical state when a repeated trigger precedes the presentation commit; this fixes a discovered test failure where reading the model's final scale caused an excessively long replacement spring. No test requirement was weakened. Text retains its own 97% scale/timing and file success retains its captured stage sequence.
- PASS: `Scripts/test-drop-presentation.sh`: five geometry/path groups, isolated file/text pasteboard checks and 24 bilingual card layouts. Actual hit geometry, shadow margins, cancel and placement unchanged.
- PASS: separately compiled/signed Before (911df2d previous refinement) / After (current physical spring) previews; strict signature verification and native switching in both directions. No engine/store/Keychain identity or real connection is constructed. Native views use current production components.
- Visible CUA captures are full native 1040×704 window images, rather than perspective thumbnails: Natural 70 frames / 3.456s, Relaxed 190 / 8.934s, Fast 115 / 5.676s. Sending, waiting, ring-to-green/check strokes and dismissal are visible. CUA click latency misses part of the first reveal, and Natural capture does not cover its full hold/dismiss: these are supplementary evidence, not initial-frame/final single-frame or two-machine acceptance. Native early transform checks complement them; owner live Before/After acceptance remains required.
- No new layers, continuous rendering loop, polling task, dependencies or settings. Four finite native springs replace sampled card transforms; keyed cleanup/revisions remain bounded. No new GPU/WindowServer performance claim.
- PASS: script syntax and diff whitespace. Existing CLT search-path warnings are nonfatal. Product metadata/production installation unchanged; build21 App/DMG still awaits preview approval. build20 DMG SHA256 is still 4f0edca6900d094fd0ff3e84602fce351cf8eeb79e0d45a1a17bbeb2a594bbf7. No push/release.

原生弹簧与打断模型、三档收稳、固定视觉中心和命中区域、文本焦点及完成序列回归通过。完整原生窗口预览已可观察，录制未覆盖展开第一瞬间，不冒充 Air／mini 最终验收；用户确认预览后才生成同一组 build21 App／DMG。

## 2026-10-08：展开更柔和、成功更利落，build21 节奏后续

- PASS: production SwiftPM build and full isolated native `Scripts/test-motion.sh`. Three card settling times are 520/860/1220ms; mass 1 and card damping 0.58 give about 2.4% height rebound (tests require >2.3%, bounded below 3.5%). Text/success springs retain damping 0.72. Native early-frame bounds/center, interrupted reveal continuity, duplicate reveal, stale dismissal, accessibility, real progress limits, parallel/acknowledged completion, captured holds and text focus/draft regressions passed.
- File rotation uses success/3 (about 217/400/583ms), while drawing uses success×0.5 (325/600/875ms). A single finite CABasicAnimation strokeEnd easing traverses both check segments; no second curve restarts at the elbow. Color/trail phase and confirmation/hold ownership stay unchanged.
- PASS: isolated Before/After preview compilation (04cfade/current), strict After signature check, script syntax and whitespace checks. No external library, protocol/configuration/identity changes or continuous tasks.
- CUA reopened the rebuilt preview and selected Natural. A 130-frame / 13.391s recording includes the sending/green/check states, but returned perspective window thumbnails this session even after the exposed Raise action. It is not full-resolution material or curve acceptance; early motion/rendering invariants are checked natively, and owner Air/mini live visual acceptance is pending. Preview screenshots remain ignored.
- Existing nonfatal CLT search-path warnings remain. No test installer, product metadata, installed app or archive changed. Still the planned build21 preview candidate, no push or public release.

三档展开放慢约四成，仅卡片增加回弹；成功翻转提速约 63%、对勾提速约 17%，折角采用同一条连续缓动。原生回归及预览编译通过，本轮录制只有系统缩略合成，不作为最终视觉验收；待用户实际确认后再打 build21。
