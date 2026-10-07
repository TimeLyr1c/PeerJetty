# 检查更新 / Check for updates

## 使用方法

从 PeerJetty 菜单栏或设置页点击“检查更新…”。应用主动访问 GitHub 的公开 Latest Release 接口，显示检查结果及 Release 正文；有新版时打开该版本的 GitHub 页面。在 Assets 下载 DMG，完成传输并退出旧 App，将新 App 替换到 Applications，重新打开即可。关闭设置窗口不等于退出应用。

0.3.2/build11 已于 2026-10-07 公开发布，是首次包含此入口的正式版。旧版用户需要先手动安装支持检查更新的版本，之后才能使用此功能。安装 0.3.2 后检查当前 Latest 会显示没有更新的正式版。

## 原理及边界

1. 本机产品版本来自 Info.plist 的 CFBundleShortVersionString。
2. 点击时请求 `https://api.github.com/repos/TimeLyr1c/PeerJetty/releases/latest`，使用公开接口，无登录令牌。GitHub 的 Latest 正式 Release 排除草稿和预发布，应用也复核这些标志。
3. 解析 `v主版本.次版本.修订版本`（也接受没有 v 的三个数字），按三个数字比较；0.3.10 高于 0.3.2。当前只支持这种正式版本格式，不接受 beta 等后缀。
4. 高于本机才提示新版；相同提示没有更新，本机更高则明确说明本地版本领先，不推荐降级。仅增加 build 而不增加产品版本，不会触发更新提示。
5. Release 页面必须属于 HTTPS 的 TimeLyr1c/PeerJetty 仓库且对应版本标签。只有已上传、匹配该标签及产品版本的 Apple Silicon DMG 才被认为安装包就绪；缺包会说明等待，不冒充可安装更新。

请求只在点击时发生，无后台轮询；不读取或上传设备信任、私钥、配置或真实文件。使用临时网络会话，不持久保存 cookie/cache。断网、超时、接口限流或错误响应会显示失败，可重新检查；404 表示暂无正式 Release。响应解析限 1 MiB，正文最多显示 20,000 字符。

Release 正文作为纯文本显示，不执行 HTML、脚本或命令，也不自动翻译。此阶段只打开经过校验的 GitHub 发布页面，不下载、验证或执行安装包。自动安装、更新包签名验证、恢复/回滚及测试渠道属于后续工作；HTTPS 页面检查不等于安装包的密码学验证。

参考：[GitHub Release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)。

## 项目维护者如何让用户看到新版

1. 把一组改动集中验收，为下一次公开交付确定产品版本、更新 CHANGELOG 和中英文发布说明。开发提交不逐次增加产品版本；同版本的测试安装包只增加构建号。
2. 保存干净的源码提交，使用项目打包工具生成对应 DMG；按两台 Mac 的验收结果决定是否正式发布。
3. 把选定源码推送到仓库，让对应 `v0.3.2` 之类的标签指向安装包记录的实际源码提交，不能把文档提交冒充构建来源。
4. 创建正式 Release，上传该版本 DMG，填写中英文变化，设为 Latest。不要勾选 Pre-release；未经验收的候选仍应标为预发布，这时正式检查不会发现它。
5. 从上一版执行检查更新，核对版本、说明、目标页面和实际安装包。已发布标签与二进制不覆盖；以后发布更高版本。

仅推送代码或创建标签不会产生可供此功能读取的 Release。用户不需要 GitHub CLI；维护者的 GitHub 授权只用于发布，不进入 App。当前不需要另上传 JSON 或校验附件，公开附件仍只放 DMG。

## English

Choose Check for updates from the menu bar or Settings. The app makes an unauthenticated request to GitHub's latest stable release endpoint only when asked. It compares three numeric version components, displays plain-text release notes, and opens the validated release page when a newer version is available. Download the Apple Silicon DMG from Assets, quit the old app, replace it in Applications and reopen it. Existing pairing/settings are not reset by this checker.

A local candidate ahead of the public release is reported explicitly and never offered a downgrade. Drafts/prereleases and unsupported version tags are rejected. Missing installer assets, network failures and rate limits are handled separately. There is no automatic download or installation, package signature verification, polling or preview channel yet. First install 0.3.2 or later manually to obtain the check feature. See the steps above for publishing a stable, Latest release with a matching version tag and DMG.

## Verification

```sh
./Scripts/test-updates.sh -AppleLanguages '(en)'
./Scripts/test-updates.sh -AppleLanguages '(zh-Hans)'
# Optional read-only check against the public GitHub endpoint:
./Scripts/test-updates.sh -AppleLanguages '(en)' --live
```

Default checks use isolated URLProtocol fixtures and do not contact GitHub or production identity/configuration. Builds share the SwiftPM cache: run sequentially. A real old-to-new installation still requires release/device acceptance.
