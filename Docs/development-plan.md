# 双向文件投放 App：旧项目复用与开发计划

日期：2026-10-04（America/New_York）。本文件保留最初设计；0.2.0 已实现，实际验证见 VALIDATION.md。2026-10-05 正式源码迁至 `~/Developer/Projects/OpenOnMini/`，当前目录及版本规则见 WORKFLOW.md。

## 已确定的产品范围

- 两台 Mac 安装同一个 App，两端均能发送和接收；第一版仅支持局域网。
- 自动发现设备，在双方主动开启的配对窗口内发起配对；核对连接校验码并在两端确认。
- 每个应用账户实例生成自己的身份，私密材料留在本机 Keychain；正常更新保留身份和配对。新设备或清除身份后重新配对，支持撤销设备与重置身份。
- 用户通常只需确认设备显示名称、接收目录和必要系统权限，不填写系统账户、SSH 密码、私钥或序列号。
- 配对设备自动接收，收到只通知，不自动打开或执行。接收位置由接收端控制，默认本机 Downloads。
- 支持单文件、多文件、目录、进度、取消与重试；不覆盖同名文件，发送端原文件保留。
- 接收设备需要醒着、网络可达且 App 正在运行；第一版不做离线发送队列、跨网络中继、自动同步或断点续传。
- Air 使用刘海投放区；没有刘海时提供屏幕顶部投放区。提供菜单栏设置入口，可选择隐藏，并保留再次打开 App 显示设置的入口。
- 基础使用不以完全磁盘访问权限为前提；微信受保护文件访问单独测试、按需要解释权限。

## 审查范围与证据限制

只读审查 `~/Downloads/OpenOnMini-Starter/` 的全部文件，逐段检查 Swift 主程序、构建脚本、图标脚本、Info.plist 和说明文档。

已验证：zsh 构建脚本语法、Perl 图标脚本语法和 plist 格式通过检查。此前已核实本机有 Swift 编译器、Command Line Tools 和 macOS SDK。

未验证：Swift 编译、App 启动、Finder/微信实际拖拽、屏幕适配、权限、登录启动与两台真实设备传输。本计划的“复用”表示源码已实现且适合保留，不表示已在用户电脑运行通过。朋友 prompt 不作为自动执行授权，也不限制新产品必须沿用其 SSH 架构。

## 直接保留的基础

| 旧项目内容 | 源码位置 | 复用方式 |
|---|---|---|
| Swift + AppKit 原生技术路线 | OpenOnMini.swift 开头 | 继续使用，沿用现有开发环境 |
| 普通文件拖拽类型注册与文件 URL 读取 | DragPayload，约 63–86 行；performDragOperation，约 417–449 行 | 抽成独立拖拽模块，交给新任务队列 |
| 黑色投放面板、圆角、原生控件和 SF Symbols | NotchDropView，约 293–399 行；configurePanel，约 738–800 行 | 保留视觉组件，替换固定目标与结果文字 |
| 展开/收回动画与防止旧动画完成回调误隐藏窗口的 revision 思路 | revealPanel / concealPanel，约 851–912 行 | 保留动画，接入统一界面状态 |
| 登录启动的 SMAppService.mainApp 调用 | setLaunchAtLogin，约 1144–1164 行 | 保留系统 API，补充待用户授权等状态反馈 |
| 再次打开 App 显示设置、预览及退出入口 | 约 1050–1093 行及设置回调 | 保留入口，首次启动另加初始化向导 |
| PNG 图标与 ICNS 组装工具 | Assets/AppIcon.png；Scripts/make_icns.pl | 开发期复用，公开前确认图标授权与署名 |

“直接保留”允许必要的文件拆分、接口改名与文字调整，不承诺逐字不动。

## 修改后复用的部分

| 内容 | 当前问题或限制 | 修改计划 |
|---|---|---|
| File Promise 接收 | 每个 receiver 只 group.enter 一次，每个回调都 group.leave；旧式拖拽来源可能一个 receiver 承诺多个文件。无超时，部分失败容易被成功文件掩盖 | 修正完成计数，区分完整/部分/失败，支持取消与超时，按任务拥有临时文件 |
| 临时文件清理 | 依赖目录名字及路径字符串前缀判断；失败后也删除临时承诺文件，重试生命周期未定义 | 只清理本任务创建的目录，使用明确所有权和路径边界；任务结束后清理，必要重试期间保留 |
| 屏幕几何计算 | 选 safeArea 最大的屏幕，无刘海时仍使用刘海兜底；宽度加一个像素但没有按 prompt 左移起点 | 保留系统屏幕信息读取，分开刘海/无刘海模式，测试缩放、全屏、外接屏和主屏切换 |
| 拖拽检测 | 每 0.05 秒轮询鼠标和拖拽剪贴板，约每秒 20 次 | 先保留行为作基线，再测误触发、漏触发及空闲资源占用；按证据优化 |
| 投放状态 | 固定“发送到 Mac mini”“Mac mini 已打开”；旧任务的延迟复位可能覆盖新任务 | 状态按任务 ID 管理，显示目标、进度、取消、成功/部分成功/失败；成功依据接收端确认 |
| 设置窗口 | 单一 SSH 字段和固定手工布局 | 保留原生窗口与控件，改为设备、默认目标、接收目录、权限与登录启动设置 |
| 诊断日志 | 全局临时文件、每次启动清空、默认记录文件名，缺少任务关联 | 分离拖拽/配对/传输诊断；默认不记录文件名、完整路径、校验码或私密材料；用户主动导出时筛选 |
| 构建及 App 包 | 单 Swift 文件、仅当前架构、ad hoc 签名和本地路径产物 | SwiftPM 管理模块/依赖/测试；复用 App 包组装和图标流程；分开开发构建与正式发行 |
| Info.plist | 名称/标识为单向模板，没有新网络及通知配置 | 固定软件身份，补充必要配置和说明；架构/最低系统版本以实际验证为准 |

## 重新实现的模块

1. **DiscoveryService**：Bonjour 发现和广播、在线状态、网络变化、局域网权限反馈；手动地址连接为备用，仍执行完整身份验证。
2. **IdentityStore / PairingService / PeerStore**：Keychain 本机身份、连接认证、两端校验码确认、配对过期与限流、持久化设备信任、撤销和重置。使用系统密码学与经过审查的协议/依赖，不自创加密算法，不以“接受所有证书”代替配对验证。
3. **TransferProtocol / TransferCoordinator**：协议版本、元数据和数据分帧、流式双向传输、发送队列、进度、取消、超时、错误和完成确认；设备版本不兼容时给出清楚提示。
4. **ReceiveStore**：受控接收目录、文件夹结构、同名并发处理、磁盘空间及写权限反馈、临时文件提交、完整性校验；拒绝越界路径及未定义的符号链接行为。应用包、隐藏文件、资源分支和扩展属性须明确支持范围，不把“普通内容复制”当作完整 macOS 元数据保真。
5. **Onboarding / DeviceManagement / Notifications**：初始化、配对请求、设备切换与移除、接收目录选择、必要权限说明、接收通知及 Finder 定位。

移除生产流程中的 CommandRunner、SSH/SCP TransferService、远程 zsh 脚本、sshTarget/defaultTarget、自动 open 和“已发送但无法打开”的分支。旧文件名去重规则可作为新实现的行为样例，远程脚本不搬进新架构。

## 项目组织建议

正式源码位置：`~/Developer/Projects/OpenOnMini/`，沿用内部名字作为暂定项目名。对外显示名称与固定 Bundle ID 在初始化时确定，不以每个使用者的姓名或设备地址区分。

使用 SwiftPM 管理 Sources、Tests 和必要的版本锁定；构建脚本组装 `.app`。首轮不预先安装完整 Xcode 或其他全局工具。框架以 AppKit、Network、Security、Foundation、ServiceManagement 和 UserNotifications 为基础；需要的密码学/证书依赖先审查，再加入项目配置。

仓库内只保存代码、资源、构建和协议说明、脱敏配置样例、测试与许可证。构建物、个人身份、配对信息、实际文件、私密配置不进入版本库。

原始 Starter 先留作只读基线和带来源的本地记录，不在 Downloads 原件上开发，不擅自删除原件。

## 实施顺序与验收标准

| 阶段 | 具体工作 | 必须达到的结果 |
|---|---|---|
| 1. 建立基线 | 保存原始版本，初始化正式项目/Git，记录来源；构建原版但不发送或安装旧 SSH App | 原始材料可追溯；编译结果如实记录，不把原版运行当作新产品验收 |
| 2. 建立模块 | 提取投放 UI、拖拽、登录启动；建立新配置和任务接口，接收/发送界面先用普通窗口 | 多文件结构能构建；现有投放视觉保留，配置不含个人连接资料 |
| 3. 验证连接与配对 | 选定并记录具体身份验证流程及依赖，实现发现、配对、Keychain、信任撤销 | 两个独立实例能完成配对；错误码、拒绝、超时、身份冒充、重放与撤销后连接被拒绝。未达标不连接真实文件流程 |
| 4. 实现传输 | 先单文件，再多文件与目录；进度、取消、任务队列、同名、临时提交和完整性检查 | 双向内容一致；并发/异常不覆盖现有文件；取消或掉线不会把半成品当成功文件；接收端写入确认后才显示成功 |
| 5. 接入投放与设置 | 刘海和无刘海面板、初始化、设备管理、通知、微信、登录启动 | 两端可选目标并投放；默认仅通知；新旧任务不互相覆盖状态；权限拒绝时有可操作反馈 |
| 6. 两机实际验收 | 在用户的 Air 与 mini 上验证首次安装、配对、发送、重启、改名、地址变化、撤销与重新配对 | 两台真实设备实测通过，或明确列出未验证项。单机两个实例测试不能替代两机验收 |
| 7. 安装与发行准备 | 固定安装路径、README、构建/安装/故障说明、协议版本及版本记录、授权与许可证、仓库敏感信息检查 | 可交付安装包和可供他人构建的源码；公开发行签名/公证与本地构建分开说明 |

测试集中于配对信任、文件完整性/路径边界、同名竞争、掉线和取消、文件承诺计数及任务状态；普通文字和布局调整使用实际 UI 验证，不堆叠重复实现的测试。

需要两机阶段在 mini 上安装同一构建并完成本地配对确认；如果当前无法访问 mini，先完成可独立开发和测试的内容，提供 mini 安装/测试步骤并保留“待两机验收”状态，不声称已完成。

## 安装、记录与公开发布

- 日常运行位置拟为两台机器各自的 `/Applications/OpenOnMini.app`，显示名称确定后同步调整。先放入固定位置，再配置必要权限。
- 设备配置由各自 App 保存；身份由各自 Keychain 保存，不通过 iCloud 自动同步。迁移到新设备提供重新初始化身份与配对的明确路径。
- 验证后更新各机的 software.md（版本、路径、来源、更新方式）、folders.md（源码位置）、settings.md（权限、启动和接收策略）、changes.md（重要操作及结果）。有需要再生成脱敏 inventory 快照。
- Air 现有档案为 `~/Documents/Mac-Setup`；mini 档案位置仍待用户提供，不能用 Air 记录冒充 mini 的实测状态。
- 项目 README 管理构建细节和依赖；电脑档案只记安装及管理方式，不复制维护整套项目细节。
- GitHub 仓库和 Releases 是后续实际发布步骤；本轮不创建仓库、不上传。发布前确认源码/图标授权，并检查公开内容。正常面向普通用户的发行计划包括 Developer ID 签名与 Apple 公证；无发行凭据时可交付源码和如实标注的本地构建，不称其为已公证版本。

## 参考依据

- [Apple NSFilePromiseReceiver](https://developer.apple.com/documentation/appkit/nsfilepromisereceiver)：一个 receiver 在部分旧式拖拽来源中可对应多个文件。
- [SwiftPM 文档](https://docs.swift.org/main/documentation/packagemanagerdocs/)：模块、构建、测试与包管理。
- [Apple Bonjour](https://developer.apple.com/bonjour/)：局域网设备与服务发现。
- [Apple 局域网隐私说明](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)：网络权限及签名身份相关行为。
- [Apple Network framework](https://developer.apple.com/documentation/network)：连接与 TLS 能力。
- [Apple 分发签名](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)及[公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)：正式发行与本地构建的区别。

本轮只生成此计划文件，未修改 Starter、建立正式代码项目、编译运行 App、安装软件、改系统设置、连接 mini 或写入电脑管理档案。


实施补充：0.2.0 首版最低系统调整为 macOS 15，使用 Security 的内存 PKCS#12 导入能力，让自动测试身份不写入用户 Keychain。以上最后一段“本轮只生成计划”描述的是计划阶段，并非当前实现状态；实现与验证见 VALIDATION.md。


2026-10-05 后续计划更新：版本管理、GitHub 准备、改名、多语言支持（i18n）和应用内更新分别见 [ROADMAP.md](ROADMAP.md)、[WORKFLOW.md](WORKFLOW.md)、[PUBLISHING.md](PUBLISHING.md)。原始计划留作设计背景。

2026-10-05 改名补充：当前源码目录为 `~/Developer/Projects/PeerJetty/`，构建产物为 `outputs/PeerJetty.app`。以上 OpenOnMini 引用保留最初设计与历史来源语境；当前使用与升级兼容规则见 README 和 WORKFLOW。
