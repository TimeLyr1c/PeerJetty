# PeerJetty — 双向局域网文件投放

同一个原生 macOS App 安装在两台 Mac 上。选择文件或把文件拖到屏幕顶部的投放区，发送到默认配对设备。可信设备自动接收，默认只提示收到；可在接收端设置中开启“收到后自动打开”。

## 安装与初始化

本版本需要 macOS 15 或更新系统。历史 OpenOnMini 0.2.0 安装包为 Apple Silicon（arm64）本地构建，未做 Developer ID 签名或 Apple 公证。它不是面向公众的正式发行包；Intel Mac 需自行构建。

1. 从源码构建 PeerJetty，将生成的 `outputs/PeerJetty.app` 放到 `/Applications/PeerJetty.app`，然后打开。当前候选未公开发布。升级旧版时先退出 OpenOnMini，不要同时运行两个版本；确认新版配置和配对正常后再移除旧 App。不要长期从 Downloads 运行。
2. 两台电脑各设置本机名称及接收目录，点击“保存 / 完成初始化”。名称只是方便辨认，不是账号或身份凭据。
3. 允许系统请求的局域网访问。通知权限可选；不需要 SSH、远程登录、管理员密码或 Apple 账号。
4. 两台电脑都点击“添加设备 · 2 分钟”，在一台电脑设备列表中选择另一台，点击“连接 / 配对”。
5. 两台屏幕核对同一个六位校验码；双方都确认才保存信任。代码不同请取消。一次只处理一组新配对。
6. 选中已配对设备，将其设为默认发送目标。之后可以双向发送，每台电脑可选不同接收目录。

当前本地签名包转移到另一台 Mac 后，系统可能阻止首次运行。先核对来源，再按系统“隐私与安全性”提供的打开方式操作；不要关闭 Gatekeeper 或全局清除安全设置。正式公开发行需签名、公证与完整实机验收。

## 日常操作与设备更换

- 普通文件、多选、文件夹、中文名、隐藏文件、空文件支持传输；目录内相对符号链接需留在同一根目录。顶层符号链接、特殊文件、越界或循环链接会拒绝。
- 同名文件自动添加 `(1)` 等后缀，已有文件不覆盖。进度后仍需等“对方已保存”，才表示接收端完成校验并提交。
- 同一连接支持同时收发；每个方向串行处理任务。取消/掉线清理未提交数据，重试需重新投放；暂不提供断点续传或离线发送。
- 默认收到文件只有通知，设置里的 Finder 按钮可查看。自动打开开关关闭时不会打开文件；开启后，完整保存成功的文件或文件夹交给系统默认应用打开。
- 不带刘海的显示器也有屏幕顶部投放区。菜单栏可隐藏；重新打开 App 可找回设置。登录启动由用户主动开启。
- 更换设备：新 Mac 安装 App、建立新身份并重新配对；旧 Mac 的授权在保留设备上移除。改名或局域网 IP 改变不需要重新配对。
- 恢复整机备份可能同时恢复 Keychain 身份。若旧机继续使用，请在其中一台 App 内“重置身份”，退出后重开，并在另一端移除旧授权再配对。不要手工复制或同步身份文件。

## 存放与隐私

源码建议放项目目录，例如 `~/Developer/Projects/PeerJetty`；App 放 Applications；配置在 `~/Library/Application Support/PeerJetty/configuration.json`；首次运行时若新配置不存在，会校验并复制旧 OpenOnMini 配置，原文件保留，新配置存在时绝不以旧配置覆盖它；私有身份在本机 Keychain 的 `app.openonmini.identity.v1` 项目。不上传 Keychain、配置、实际传输文件或设备信任记录。

Bonjour 广播服务标识及公开证书指纹；显示名只在开启配对窗口时广播。文件内容使用系统 TLS 1.3 加密，不经云服务器。配对码流程是本项目实现的协议，尚未独立安全审计，不能将其视为已认证的成熟配对标准。详见 [协议说明](Docs/PROTOCOL.md)。

## 本地测试候选

当前源码为 **0.2.4 / 构建 6**：新增收到后自动打开开关，默认关闭，旧配置同样保持关闭；只在完整保存后打开，打开失败不影响已保存文件。0.2.3 / 构建 5：替换为用户提供的 PeerJetty 图标，投放面板逻辑尚未改变。0.2.2 / 构建 4：产品与构建改名为 PeerJetty，迁移旧配置，安装包附 MIT 声明；0.2.1 增加版本显示、构建来源和归档工具；此前安装的 0.2.0 / 构建 2 继续保留。用户已反馈 0.2.2 在 Air / mini 上双机试用正常，0.2.3 新图标也正常；详见验证记录，这不代表全部边界场景已逐项覆盖。构建脚本不会自动替换已安装 App。

## 从源码构建

需要 Apple Command Line Tools 或 Xcode，Swift 5.9+，macOS 15+ SDK；系统 `/usr/bin/openssl` 用于首次生成本机证书。构建来源记录使用 Python 3 标准库，本机 Command Line Tools 已提供 `/usr/bin/python3`。无第三方 Swift 包、无 Homebrew 依赖。

```sh
cd /path/to/PeerJetty
./build.sh
# 产物：outputs/PeerJetty.app
./Scripts/test.sh
```

测试脚本执行核心断言与两个独立身份的 localhost TLS 联调；不读生产配置或生产 Keychain，临时密钥只在测试内存和权限受限的临时目录存在。自动测试不能代替两台实体 Mac 的 Bonjour、系统授权、Finder/微信拖拽、登录启动与睡眠恢复测试。部分受限执行环境需要允许 localhost 网络。

构建默认使用本地 ad hoc 签名。具备自己的 Developer ID 后，可通过 `PEERJETTY_SIGNING_IDENTITY`（兼容旧的 `OPENONMINI_SIGNING_IDENTITY`） 指定签名；Apple 公证为后续单独发行步骤。架构遵循构建机器，当前脚本不自动产出 universal binary。

## 故障处理

发现不到：确认同一局域网、两端 App 正在运行、两端配对窗口开启；检查局域网权限及访客 Wi-Fi/AP 隔离。仍无法发现，可使用对方设置窗口显示的地址与端口手动连接，仍需 TLS 和双方校验码确认。

发送失败：检查接收目录可写、剩余空间、文件是否仍在改变；有权限限制时先使用文件选择器。微信拖拽兼容普通 URL 与文件承诺，但实际微信版本尚待实测。只有系统实际阻止读取时才考虑额外文件访问授权，不要求所有用户开启完全磁盘访问。

配置损坏时显示错误，不静默覆盖；先备份并检查本机配置。更新 App 时先退出、替换同一路径，然后重开，正常更新保留配对。

## 发布状态与来源

0.2.0 是首个双向开发版本。原始单向 SSH Starter 保留在 `Original/`，新传输代码位于 `Sources/`，没有复用 SSH 连接或自动打开逻辑。[开发计划](Docs/development-plan.md)、[验证与验收](Docs/VALIDATION.md)、[来源及授权](LICENSE-NOTES.md) 记录范围与限制。

本项目采用 [MIT 许可证](LICENSE)，用户与提供 Starter 的室友已约定采用 MIT。原始来源及现有图标尚待核实的素材授权见 [来源及授权](LICENSE-NOTES.md)。源码仓库为 [TimeLyr1c/PeerJetty](https://github.com/TimeLyr1c/PeerJetty)；目前未发布 Release。所有个人配置均在运行时生成，不需要编辑源码填设备信息。

## 开发目录与版本管理

正式开发目录为 `~/Developer/Projects/PeerJetty`。源码历史由 Git 保存，构建结果在 `outputs/`，已安装 App 位于 Applications；这三者分别管理。详见 [开发工作流](Docs/WORKFLOW.md)。

[后续计划（含多语言与更新）](Docs/ROADMAP.md)、[GitHub 发布准备](Docs/PUBLISHING.md)、[许可证比较](Docs/LICENSING.md)、[产品定位与名称候选](Docs/POSITIONING.md)。

## 改名兼容性

用户界面、SwiftPM 主目标、可执行文件、App、源码目录和新安装包名称已改为 PeerJetty。Bundle ID `app.openonmini.desktop`、Keychain 服务 `app.openonmini.identity.v1`、Bonjour 和协议 v1 标识保留，避免现有身份失效并保持与旧版本通信。它们是稳定的内部兼容标识，不是用户需要填写的配置。Original 基线、旧安装包名称与过去验收记录保持原样；当前图标已替换，旧图标已从公开历史排除，原始记录仅保留在本地私有备份，详见 [历史整理](Docs/HISTORY.md)。首次升级仍需在两台实体 Mac 上验证配对、权限和登录启动。

## 参与与来源

初始 OpenOnMini-Starter 由项目发起者的室友提供；PeerJetty 在其原生界面基础上开发双向局域网配对传输。双方约定采用 MIT，公开个人署名待提供。保留 Original 便于追溯。贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)，安全问题反馈见 [SECURITY.md](SECURITY.md)。

首次公开历史整理与旧安装包源码编号对应见 [HISTORY.md](Docs/HISTORY.md)。源码公开不代表已提供正式安装包；发布状态以 GitHub Releases 为准。

自动打开是每台接收电脑各自的设置，发送方不能远程开启。开启后可能切换到默认应用；仅对信任的配对设备启用。关闭会立即影响之后处理的收件，不会关闭已经打开的窗口。设置重启后保留。
