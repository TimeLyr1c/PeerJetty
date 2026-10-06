# 开发、构建与版本工作流

更新：2026-10-05。

## 当前状态

- 正式源码：`~/Developer/Projects/PeerJetty`。
- Air 已安装 App：`/Applications/OpenOnMini.app`，仍为 0.2.0 / 构建 2。
- 当前源码准备 PeerJetty 0.2.4 / 构建 6（可选收到后自动打开），本地测试候选，未安装、未公开发行。
- 新版配置：`~/Library/Application Support/PeerJetty/configuration.json`；首次启动复制经校验的旧配置，保留旧文件；身份在 Keychain。
- 0.2.0 安装包与源码包已逐字节核对；本地标签 v0.2.0 对应原实现提交 47f5254。
- Air 历史包归档：`~/Dropbox/90_开发资料/OpenOnMini/安装包/0.2.0-build2/`。本地写入不代表其他电脑已同步完成。
- 尚无 GitHub 远程仓库；mini、Windows 完整路径待核实。

## 文件分工

Sources/ 是源码；Tests/ 是验证；Assets/ 是资源；Scripts/ 与 build.sh 是工具；Package.swift 管理 SwiftPM 配置；Info.plist 是产品版本与构建号的唯一来源。
README.md 是使用入口；Docs/ 是技术和操作说明；CHANGELOG.md 是版本变化；LICENSE-NOTES.md 记录授权状态；Original/ 保留 Starter 基线。
.git/ 保存源码历史。.build/、.module-cache/ 是本机缓存；outputs/ 是最新构建与本地候选，均不进 Git。

## 普通开发构建

```sh
./build.sh           # release 配置
./build.sh debug     # debug 配置
./Scripts/test.sh
python3 -m unittest discover -s Tests/ReleaseTools -v
```

两种构建配置目前都输出到 outputs/PeerJetty.app，下一次构建会替换该位置。不会自动安装 App，也不会自动增加版本号。
构建使用 Python 3 标准库生成来源记录；此机 Command Line Tools 已提供 /usr/bin/python3，无第三方 Python 包。
App 的设置窗口显示产品版本和构建号；菜单“关于”及版本文字提示可查看源码提交和构建配置。
资源内 build-info.json 包含完整提交、未提交修改标记、时间、架构和工具链版本。带未提交修改的普通构建会如实标记，不得把它当作固定提交的交付包。

## 准备新的交付候选

```sh
python3 Scripts/release.py show
# 示例：只有准备下一份交付时执行，不要对当前已交付构建重复使用
python3 Scripts/release.py set 0.2.4 --build 7
```

set 要求版本格式为三个数字，产品版本不能倒退，构建号必须增加。它修改 Info.plist，不自动提交、不自动发布。
准备工作分支，检查修改、测试并提交后，再打包。未完成进度可保存为 WIP 提交；交付候选仍需明确记录验收状态。

## 自动归档

```sh
python3 Scripts/release.py package
# 默认 outputs/releases/<版本>-build<构建号>/
# 也可显式指定自己电脑已核实的归档根目录：
python3 Scripts/release.py package --destination "$HOME/Dropbox/90_开发资料/PeerJetty/安装包"
```

工具要求仓库干净；未提交修改或未跟踪的新源码会阻止打包。它重新构建 release 配置，核对源码和版本未在构建中变化，验证签名，并生成：
- 带产品版本、构建号和架构的 ZIP。
- SHA256SUMS.txt。
- build-info.json 与脱敏 signature.txt。
- release-info.md，明确编译/签名校验与未完成的双机验收。

已有同版本/构建号目录会拒绝覆盖；需要增加构建号。普通编译不都归档。
打包不创建 GitHub Release，不自动上传，不自动公证，不自动安装，不改变本机配对配置。

## 历史与发布

提交是源码进度；分支是工作线；标签指向选定源码；安装包是具体二进制。已分发的安装包保留原样，源码通过 Git 历史回看，不复制“最终版”源码文件夹。
正式发布时更新 CHANGELOG、完成验收、确认授权，选定提交和版本标签，再上传对应源码与安装包。0.2.0 的本地历史标签不代表已公开发布。
其他机器先保存并上传工作分支，接收机器下载同一分支继续；未保存、未提交、未上传或只在本地 stash 的修改不会自动过去。

## 迁移和兼容性

2026-10-05 源码从 Documents/Codex 迁到本地 Developer，完整保留 Git 与 Original，重新生成旧路径缓存。本次版本工具不替换安装的 App，也不更换设备身份。
通信协议版本另见 PROTOCOL.md；不要直接用产品版本代替协议版本。
2026-10-05 产品及源码目录改名 PeerJetty，保留 Git 历史、Original 和旧安装包路径。内部身份与协议标识保持兼容；新 App 安装目标为 `/Applications/PeerJetty.app`，尚未替换 Air 旧 App。新归档可使用 `~/Dropbox/90_开发资料/PeerJetty/安装包`，此目录尚未创建；上述旧归档仍在 OpenOnMini 路径。

每项完成并验证的修改保存为独立本地 Git 提交；最终报告提交 ID。上传仍是独立步骤。未完成工作若需要中断，做明确标记的 WIP 检查点，不把它冒充通过验收的版本。
国际化等后续计划见 ROADMAP.md。

## 首次公开安装包

2026-10-05：0.2.4/build6 已发布为 GitHub Pre-release，标签 v0.2.4 固定至源码 ef49e67。下载页：
https://github.com/TimeLyr1c/PeerJetty/releases/tag/v0.2.4

本机原归档仍在 outputs/releases/0.2.4-build6；本次未移动到 Dropbox，也未替换已安装 App。后续修改先保存提交和测试，再交付新版本/构建号，不能覆盖此次安装包。

## DMG 安装镜像

2026-10-05 同一 0.2.4/build6 App 新增 DMG 容器，未重新编译、未改变源码来源、未覆盖已发布 ZIP。DMG 包含 App、Applications 安装链接及安装文字，校验单独保存在 SHA256SUMS-DMG.txt。README 首页提供直接下载入口。

今后 package 同时生成 ZIP 和 DMG；为已有 ZIP 归档补建 DMG，可执行：
```sh
python3 Scripts/release.py dmg outputs/releases/0.2.4-build6
```
该命令校验原 ZIP 与 App 来源，不重新构建；同名 DMG 或校验文件已存在时拒绝覆盖。容器格式改变不代表程序行为改变，也不会自动获得 Developer ID 签名或 Apple 公证。

## 当前公开发行约定（2026-10-05）

0.2.4/build6 已转为正式版并设为 Latest，原标签与 DMG 内容保持不变。以上预发布、源码待上传及首页直接下载入口的描述属于历史记录，以本节为当前约定。

公开上传的 Release 附件只保留 DMG；ZIP、JSON、签名记录和校验文件保留在本地 outputs/releases 归档中，用于追溯，不作为用户下载附件。GitHub 自动生成的 Source code ZIP/tar.gz 属于平台功能，不是项目上传的安装包。

README 默认英文，README.zh-CN.md 为中文入口，两版同步维护；发布说明提供英文与简体中文，首页使用普通 Releases 链接，不添加大型下载标题。应用界面多语言另行实现，文档双语不代表应用已经支持英文。经验证可用的版本按正式版发布并设为 Latest；未经验收的试用构建标为 Pre-release。不要修改已经分发的二进制或移动已有版本标签。

## 0.2.5 顶部投放测试候选

2026-10-05：0.2.5/build7 加入有／无刘海屏幕的顶边触发圆角卡片。源码按项目规则保存提交，归档目标为 outputs/releases/0.2.5-build7；实际生成结果以文件存在和校验为准。公开正式版仍为 0.2.4，后续先在 Air 与 mini 安装同一候选并核对版本、完成 DISPLAY-PLAN.md 的实机验收，再决定发布。配置与身份不参与双机文件同步。
