<p align="center">
  <img src="Assets/AppIcon.png" width="128" alt="PeerJetty 图标">
</p>

# PeerJetty

**给两台 Mac 之间的文件交接，一个熟悉的目的地。**

配对工作设备，选好默认目标，之后把文件拖入屏幕上方的卡片即可发送。PeerJetty 通过局域网直接传输，已配对设备自动接收，保存到你选择的目录。

[English](README.md) · **简体中文**

[版本下载](https://github.com/TimeLyr1c/PeerJetty/releases/latest) · [使用教程](Docs/TUTORIAL.zh-CN.md) · [更新计划](Docs/ROADMAP.md)

## 为什么用 PeerJetty？

PeerJetty 面向经常在笔记本和桌面 Mac 之间切换的人。记住发送目标、提供便捷的拖拽入口、固定接收位置，让反复交接文件更顺手。有刘海和普通显示器都可以使用。

AirDrop 适合偶尔的附近分享，LocalSend 等工具覆盖更广的跨平台需求。PeerJetty 专注于已配对的 Mac 工作设备，不宣称速度更快，也不宣称通过了独立安全审计。

## 能做什么

- **配对一次：** 自动发现局域网设备，在两台屏幕上核对六位校验码。
- **双向传输：** 拖拽或选择文件发送文件与文件夹，发送和接收可以同时进行。
- **接收可预期：** 已配对设备自动接收；指定目录，可选择完整接收后自动打开。自动打开默认关闭。
- **保护传输：** 直接使用 TLS 1.3，保存前校验文件完整性，同名文件改名保存，不覆盖已有文件。
- **原生体验：** Swift 和 AppKit 实现，支持中英文，应用内可单独选择语言。

### 正式版与开发版

| | 公开正式版：0.3.2 | 当前源码：0.4.0 开发版 |
|---|---|---|
| 配对后的局域网文件／文件夹传输 | 已提供 | 已提供 |
| 中英文与手动检查更新 | 已提供 | 已提供 |
| 纯文本传输与本机历史 | 不包含 | 已实现 |
| 五页设置、独立 Dock／菜单栏开关 | 不包含 | 已实现 |
| 启动重连、改进的连接状态和磁盘不足反馈 | 不包含新教程描述的改进 | 已实现 |

**0.4.0 源码尚未公开发布为正式 Release。**[使用教程](Docs/TUTORIAL.zh-CN.md)以此开发版为准，并标注新增功能。下载当前公开 DMG，并不包含源码分支的所有功能；本地测试安装包也可能落后于源码，详见[验证记录](Docs/VALIDATION.md)。

## 安装与开始使用

公开安装包要求 **Apple Silicon（M 系列）Mac，macOS 15 或更高版本**。暂未验证或提供 Intel 安装包。

1. 在[最新正式版](https://github.com/TimeLyr1c/PeerJetty/releases/latest)的 **Assets** 中下载 DMG。
2. 打开镜像，把 `PeerJetty.app` 拖入 **Applications（应用程序）**，再推出镜像。
3. 在两台 Mac 上打开 PeerJetty，系统询问时允许局域网访问。
4. 设置各自的名称和接收目录。两端开启“添加设备”，连接另一台 Mac，仅在六位校验码一致时双方确认。
5. 选择默认发送设备。把文件拖向**菜单栏下方、屏幕上方中央**，卡片出现后拖进去松开。

两端应用需保持运行，电脑保持唤醒并连接同一局域网。等待“对方已保存”才表示发送完成；关闭设置不等于退出应用。

当前安装包采用 ad hoc 签名，**尚未经过 Apple 公证**。遇到首次启动验证提示，请核对下载来源并参照 [Apple 官方说明](https://support.apple.com/en-us/102445)处理。详细安装与排查步骤见[教程](Docs/TUTORIAL.zh-CN.md#安装)。

## 支持范围与隐私

- 仅 Mac 之间的局域网传输，无传输账号、云端中转或 SSH。尚不支持 Windows、跨网络、离线投递或断点续传。
- 传输文件内容、名称、目录结构和基本权限，不保留 Finder 标签、ACL、扩展属性或资源分支。它不是备份或持续同步工具。发送前先保存文件；需要保留特殊元数据时，应先使用合适的归档方式。
- 0.4.0 中成功收发的文本**始终在本机记录**，隐藏历史不会停止记录。不自动粘贴、执行正文或打开链接，详见[文本隐私说明](Docs/TEXT.md#history-and-privacy--历史与隐私)。
- 配置在 `~/Library/Application Support/PeerJetty/`，私有设备身份在本机钥匙串。不要通过 Git 或 Dropbox 同步身份、信任配置或文本历史；文本数据库未由应用加密。
- 手动检查更新时才访问 GitHub，安装仍需手动完成。配对协议尚未经过独立安全审计，详见[协议与限制](Docs/PROTOCOL.md)及[安全反馈](SECURITY.md)。

## 从源码构建

使用带有 **macOS 26 或更新 SDK** 的当前 Xcode 或 Command Line Tools，以编译原生玻璃接口；应用最低运行版本仍为 macOS 15。另需 Python 3 和系统 OpenSSL。没有第三方 Swift 包依赖或 Web 运行时。

```sh
git clone https://github.com/TimeLyr1c/PeerJetty.git
cd PeerJetty
./build.sh
```

产物为 `outputs/PeerJetty.app`；构建不会安装或发布。脚本按本机架构构建，不生成通用二进制。源码、构建、归档与测试方法见[开发工作流](Docs/WORKFLOW.md)和[贡献指南](CONTRIBUTING.md)。

## 反馈与参与

反馈问题时提供应用版本／构建号（0.4.0：关于 → 诊断详情）、macOS 版本、复现步骤、预期与实际结果。附件先移除私人路径、文件名、设备标识和文本。普通问题与建议可提交到 [Issues](https://github.com/TimeLyr1c/PeerJetty/issues)，安全问题请按 [SECURITY.md](SECURITY.md)处理。

[中文教程](Docs/TUTORIAL.zh-CN.md) · [English guide](Docs/TUTORIAL.md) · [贡献指南](CONTRIBUTING.md) · [国际化](Docs/LOCALIZATION.md) · [设计规范](Docs/design/DESIGN_SYSTEM.md) · [变更记录](CHANGELOG.md)

## 许可证与来源

[MIT](LICENSE)。PeerJetty 起源于项目发起者室友提供的 OpenOnMini Starter；`Original/` 保留源码基线，`Sources/` 是当前局域网实现。署名与素材说明见[许可证及来源说明](LICENSE-NOTES.md)。
