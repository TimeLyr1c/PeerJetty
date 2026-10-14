# In-app updates / 应用内更新（1.1.0 candidate）

Current source uses official Sparkle **2.10.0**, pinned by SwiftPM/Package.resolved. The public 1.0.0 installer has no updater: install the first updater-enabled release manually once. Future updates use the same installed application path and preserve runtime data outside the App.

当前源码候选接入官方 Sparkle 2.10.0；公开 1.0.0 没有该更新器，首次需手动安装含此功能的版本。之后检查、下载、确认安装并重启在 App 内完成。不会改变身份、配对、设置或历史。

## User flow / 用户流程

Check manually → review notes → download and verify → Install and Relaunch. Later/cancel does not opt into automatic installation on ordinary quit; a later check can resume/re-download as Sparkle permits. Automatic checks, downloads, installs and profiling are disabled.

手动检查、确认下载，再点击安装并重启。取消／稍后不允许正常退出时静默安装；以后重新检查再继续。等待已接受文件、文本、准备和确认完成，期间拒绝新任务。可取消等待恢复收发。未发送文本草稿先确认是否放弃。

Ordinary quit is blocked while an update session needs a decision; finish or cancel from the update UI first. A confirmed installation may terminate the application.

Only installed copies under /Applications or ~/Applications are eligible. Read-only DMG, temporary builds and translocated copies show installation instructions. OS authorization and Keychain prompts may still occur with ad hoc signing; this is not notarization.

仅应用程序目录内安装副本可更新；开发目录、镜像或隔离路径明确提示先安装。当前 ad hoc 签名不保证无系统或钥匙串提示，不代表 Apple 公证。

## Publishing / 发布

- Stable signed feed: `Updates/appcast.xml`, served from `https://raw.githubusercontent.com/TimeLyr1c/PeerJetty/main/Updates/appcast.xml`.
- Feed is currently empty and is **not pushed by this task**. A missing remote feed is not proof of a working production update channel; local signed fixtures cover the installer.
- Packages remain GitHub Release DMGs only. Development builds must never enter stable feed. CFBundleVersion increases monotonically; product version labels accompany it.
- Update archives are Ed25519 signed; feed and release notes are signed. Verify before extraction; never fall back to unsigned feed after a failure.
- Generate feed in an ignored staging folder with pinned Sparkle tools, `--account PeerJetty.Release --maximum-deltas 0 --download-url-prefix https://github.com/TimeLyr1c/PeerJetty/releases/download/vVERSION/`. Copy only the generated signed XML into Updates after verifying published installer URL and signature. Signing XML or notes again is mandatory after editing.
- Validate source commit, installer checksum, nested code signatures and privacy scan. Publish verified stable DMG first, then publish its signed feed. Existing release tags/archives remain immutable.

稳定清单现在为空，本轮不推送；只有正式验收并发布后才放入清单。发布前验证 DMG URL、签名、大小、版本和说明，不将开发构建暴露给普通用户。公开附件只有 DMG，清单与说明是仓库文档。

## Signing key / 更新密钥

Release account: `PeerJetty.Release` in the login Keychain, generated once with official `generate_keys --account PeerJetty.Release`. Only its public key is embedded in Info.plist. This key is separate from device pairing identities and Apple code-signing certificates.

私钥只在本机登录钥匙串，与设备身份和 Apple 签名证书不同。不要删除／重建它来解决普通签名错误。若丢失且没有 Developer ID 的轮换路径，既有用户可能需要手动升级。

Before relying on this update channel, export an **independent encrypted backup** using official `generate_keys --account PeerJetty.Release -x <secure-private-path>` into a controlled location outside repo/Downloads/Dropbox. The exported file is a secret even though it is base64. Store encrypted/offline, restrict permissions, verify restore in a controlled environment, then remove unencrypted temporary copies. This task does not export a private key or claim a backup exists.

正式依赖更新渠道前，需独立加密／离线备份并验证恢复。导出文件不能入 Git、安装包、聊天、普通共享目录或反馈附件；本轮未导出私钥，也未声称已有备份。

## Evidence / 验证范围

`Scripts/test-in-app-update.py` creates disposable Apps in ~/Applications/PeerJetty-Isolated-Updater, with a fresh ephemeral signing seed removed afterwards. It uses signed feed and archive over loopback HTTP only, with ATS exceptions only in fixture Info.plist. Production feed/download uses HTTPS with no such exception.

The fixture tests actual Sparkle download, extraction, replacement, restart and preservation of an adjacent fake data file; it does not access production Keychain or claim a real two-Mac upgrade. `--corrupt` mutates the signed archive and checks the old app remains. Native UI and real Air/mini acceptance are separately required.
