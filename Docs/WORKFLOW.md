# 开发、构建与版本工作流

更新：2026-10-06。

## 当前状态

- 正式源码：`~/Developer/Projects/PeerJetty`，远程仓库：https://github.com/TimeLyr1c/PeerJetty。
- 最新已归档测试包：0.3.2/build11；App 安装目标 `/Applications/PeerJetty.app`。各机器的实际安装版本以各自检查为准。
- 公开安装包与源码上传分别管理；当前公开正式 Release 是 0.2.4/build6，新源码推送不会自动改变它。
- 配置：`~/Library/Application Support/PeerJetty/configuration.json`；身份在本机 Keychain，语言选择在本机应用偏好中。
- 历史安装包保留在已核实的归档位置；本地 `outputs/releases/` 按版本/构建号保存，均不进 Git。旧 Dropbox 归档路径是历史记录，不推断其他机器已同步。
- mini 和 Windows 的开发目录完整路径尚待各自核实。

## 交付节奏（2026-10-06 起）

用户已决定把小改动合并交付，区分四种操作：

1. Git 提交：完成有意义且验证过的修改就保存，不要求每次增加版本或生成安装包。
2. 本地编译：开发中随时编译，版本号保持不变；不为每次编译归档。
3. 测试安装包：一组改动完成、需要双机验证时生成。为下一次公开交付确定产品版本；测试迭代沿用同一产品版本，只增加构建号，不覆盖既有归档。
4. GitHub Release：将一组验收通过的改动集中发布。已公开产品版本不复用、不覆盖包或移动标签；后续更新增加产品版本。严重故障或安全问题可及时单独修复发布。

例如下一轮候选可以是 `0.3.3/build12`，复测修改后生成 `0.3.3/build13`，最终只公开验收通过的构建。这里是工作流示例，不代表已经设置版本或生成这两个包。

检查更新比较产品版本，不比较构建号。因此新公开更新必须增加产品版本；同产品版本不同构建用于发布前测试。已生成的 0.2.x/0.3.x 历史包保留，本次不重编号、不重新编译、不批量发布这些候选。

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

## 0.2.6 顶边手势冲突调整

0.2.5 实机反馈：拖到顶边可能先触发 macOS 调度中心。0.2.6/build8 将入口下移至菜单栏下方，静止卡片提前出现；保留原候选归档，不改系统设置。当前本地候选为 0.2.6，归档目标 outputs/releases/0.2.6-build8，公开正式版仍为 0.2.4。实机确认后再决定发布。

## 0.3.0 国际化测试候选（2026-10-06）

用户报告 0.2.6 使用正常。当前源码为 0.3.0/build9，中英文跟随系统或单应用语言偏好；验收见 VALIDATION.md，翻译维护见 LOCALIZATION.md。本地归档目标为 `outputs/releases/0.3.0-build9`，App 安装目标仍为 `/Applications/PeerJetty.app`。此轮不自动安装、公开上传或修改电脑管理档案。

GitHub 远程仓库为 https://github.com/TimeLyr1c/PeerJetty，当前公开 Latest 仍是 0.2.4/build6。文档开头的未创建远程仓库和旧安装位置是早期记录，不代表当前实机安装已重新核实；两台电脑现有安装位置/版本应以各自实际检查为准。测试通过后再决定是否发布新版本，保留既有安装包及标签。

## 0.3.1 应用内语言选择（2026-10-06）

0.3.1/build10 为本地测试候选，归档路径 `outputs/releases/0.3.1-build10`。语言在应用设置里选择，自动保存在本机 UserDefaults；退出重开生效。该偏好不进入配对或传输配置，不更换设备身份。删除“微信文件访问权限”系统跳转按钮；不撤销用户先前在系统授予的权限。未自动安装或公开发布。

## 0.3.2 手动检查更新（2026-10-06）

本地候选 0.3.2/build11，归档 `outputs/releases/0.3.2-build11`。菜单和设置提供手动检查，公开更新源固定为 TimeLyr1c/PeerJetty 的 Latest 正式 Release。仅推送源码或增加本地版本不触发公开更新；发布流程与用户操作见 UPDATES.md。本轮不自动安装、不推送源码或创建公开 Release。
