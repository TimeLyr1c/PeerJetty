<p align="center">
  <img src="Assets/AppIcon.png" width="128" alt="PeerJetty icon">
</p>

# PeerJetty

File handoff between your Macs. Pair your devices once, choose a default destination, and drag files to the top of the screen to send them across your local network.

**English** · [简体中文](README.zh-CN.md)

## Features

- Bidirectional transfers using the same native app on both Macs.
- Nearby discovery and pairing confirmed with a matching six-digit code on both screens.
- Send files and folders through drag and drop or a file picker.
- Trusted devices receive automatically. Notifications are the default; opening received files is an optional setting on each receiving Mac.
- Direct TLS 1.3 transfers with integrity checks and collision-safe filenames. Existing files are never overwritten.

PeerJetty is designed for frequent handoffs between paired work devices. It does not claim to outperform AirDrop.

## Install

The current installer supports **Apple Silicon Macs running macOS 15 or later**. PeerJetty 0.3.2 supports English and Simplified Chinese, with an in-app Language choice: Follow system, English or 简体中文. Quit and reopen the app after changing it.

1. Open [Releases](https://github.com/TimeLyr1c/PeerJetty/releases/latest) and download the DMG from **Assets**.
2. Open the DMG, drag `PeerJetty.app` into `Applications`, then eject the image.
3. Launch PeerJetty on both Macs. It runs from the menu bar and does not show a Dock icon.

The current app is ad hoc signed and **not Apple-notarized**. macOS may block its first launch. Confirm the download source before using the opening option offered in System Settings → Privacy & Security.

To update, quit PeerJetty, replace the app in Applications, and reopen it. Normal updates retain pairing and settings. When upgrading from OpenOnMini, quit the old app first and avoid running both apps together.

## Pair and send

1. Connect both Macs to the same local network and keep both apps running.
2. Set a device name and a receiving folder on each Mac, then save the initial setup. Allow local network access when macOS requests it.
3. On both Macs, select **添加设备 · 2 分钟** (Add device · 2 minutes). Select the other device and choose **连接 / 配对** (Connect / Pair).
4. Compare the six-digit code on both screens and confirm on both devices only if it matches.
5. Set the paired Mac as your default sending destination. Drag files to the screen-top drop zone or use the file picker.

Wait for the confirmation that the other Mac has saved the files. Receiving is automatic for trusted peers; **收到后自动打开** (Open after receiving) is off by default and can be enabled separately on each receiver. Completed files open in their default apps; folders open in Finder.

If discovery fails, check network permissions and Wi-Fi client isolation. The settings window also provides an address and port for manual connection, with the same pairing checks. A new device must be paired again; remove the old device's trust when replacing it. Never copy or sync private device identities.

## Text (0.4.0 source/test build)

The menu bar’s **Send Text…** opens a multiline input panel. Pick a paired device, type or paste, then press ⌘Enter. Received text opens for viewing and explicit copying; it never replaces the clipboard or opens links automatically. Both devices need text support; older versions still transfer files.

Successful text sends and receipts are **always saved on each Mac**. Settings can hide the history entry, but hiding does not stop recording. Retention defaults to the latest 500 entries, with 30-day and forever options. See [text usage and privacy](Docs/TEXT.md). The current public 0.3.2 installer does not include this feature; 0.4.0 is a local test candidate.

The 0.4.0 local candidate also includes categorized native settings, redesigned text windows, and a native glass drop card on macOS 26+ (system frosted material on macOS 15). General → **Enable interface animations** applies immediately; system Reduce Motion takes priority. Actual drag targets appear immediately and stay fixed. Choose **Fast / Natural / Relaxed** (default Natural) and **Preview animation** in General. The glass card springs quickly toward its final shape and slows to settle; the file ring smoothly follows real byte targets with a visual speed limit; confirmed success draws a check and stays visible before dismissal. See [appearance and motion](Docs/APPEARANCE.md).

In the 0.4.0 candidate, the menu has six daily actions. **General → Show menu bar icon / Show Dock icon** saves independent choices. When both are hidden, reopening the app temporarily restores the menu icon and opens Settings. History is in Text settings, previews in Transfers, and build details in About. See [menu and diagnostics](Docs/MENU.md).

## Settings (0.4.0 source/test build)

Settings uses a native five-category toolbar: General, Devices, Transfers, Text and About. Choose a category to see its options; compact screens scroll vertically. Device names still require Save, while switches keep their existing save behavior. Switching categories keeps unsaved name edits.

## Scope and privacy

- Local network only; both devices must be online and awake. No cloud relay, SSH, account, or hardcoded device credentials.
- PeerJetty includes manual Check for updates in Settings and the menu bar; see [update instructions](Docs/UPDATES.md). No Windows client, automatic installation, offline queue, or resumable transfers yet. Retry interrupted transfers from the start.
- The app opens a stationary rounded card when files approach the upper center below the menu bar, on both notch and non-notch screens. There is no need to touch the physical screen edge. See the [display design and validation checklist](Docs/DISPLAY-PLAN.md).
- Settings stay in `~/Library/Application Support/PeerJetty/`; private identity is stored in the local Keychain. Do not share these through Git or cloud sync.
- Text history lives at `~/Library/Application Support/PeerJetty/TextHistory/history.sqlite` (current-user access only). It is separate from source and installers; do not sync it with Dropbox or Git.
- Pairing uses this project's own protocol and has not undergone an independent security audit. See the [protocol documentation](Docs/PROTOCOL.md).

## Build from source

Requires macOS 15+, Command Line Tools or Xcode with Swift 5.9+ and the macOS 15+ SDK, Python 3, and system OpenSSL. There are no third-party Swift package dependencies or Homebrew runtime requirements.

```sh
git clone https://github.com/TimeLyr1c/PeerJetty.git
cd PeerJetty
./build.sh
```

The app is generated at `outputs/PeerJetty.app`. Builds follow the host architecture; the script does not produce a universal binary. Intel builds are not physically validated.

## Contribute

Bug reports and feature suggestions are welcome. Include the app version, macOS version, and reproduction steps, with private information removed.

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Roadmap](Docs/ROADMAP.md) · [Changelog](CHANGELOG.md)

README and release notes are available in English and Simplified Chinese. The app supports both languages. Other engineering documents may currently be Chinese-only. See the [localization guide](Docs/LOCALIZATION.md) for language selection and translation contributions.

## License and credits

[MIT](LICENSE). PeerJetty grew from the OpenOnMini Starter supplied by the project founder's roommate. The original source baseline is preserved in `Original/`; PeerJetty's bidirectional LAN implementation lives in `Sources/`. See [license and source notes](LICENSE-NOTES.md).
