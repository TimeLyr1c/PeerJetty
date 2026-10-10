# PeerJetty user guide

**English** · [简体中文](TUTORIAL.zh-CN.md) · [Project home](../README.md)

This guide describes the **0.4.0 development source**. The currently published DMG is **0.3.2**. File installation/pairing basics apply to both; five-page settings, text/history, independent icon switches, startup reconnection and newer failure handling described here are 0.4.0 features. Use a matching current build on both Macs for testing. A local installer may not include later source-only fixes; check [validation records](VALIDATION.md).

## Install

You need two awake Apple Silicon Macs running macOS 15 or later, on the same local network. PeerJetty must run on both. Internet is not required for direct transfers; downloading the app and checking GitHub updates use the internet.

1. On each Mac, download the DMG from **Assets** on [Releases](https://github.com/TimeLyr1c/PeerJetty/releases/latest), or use a test DMG supplied by the maintainer.
2. Open the DMG and drag `PeerJetty.app` into **Applications**. Run the installed copy, not the one inside the image. Eject the image.
3. Open PeerJetty. New installations show a menu bar icon and no Dock icon. Choose **Settings…** from the menu.
4. In **General**, enter a recognizable name and click **Save**. In **Transfers**, choose a receiving folder. These preferences belong to each Mac separately.
5. Allow local-network access when requested. Notifications are useful for receipts but are not required for transferring files; folder access is needed to save them.

The current distributed builds are ad hoc signed, without Apple notarization. If macOS cannot verify the developer or check the app, first verify that the download came from this repository. If you trust the source and macOS offers it, try opening once, then use **System Settings → Privacy & Security → Open Anyway**. An alert about detected malware or a damaged app needs separate investigation. See [Apple's instructions](https://support.apple.com/en-us/102445).

If both icons have been hidden in 0.4.0, reopen PeerJetty from Applications or Spotlight to open Settings and temporarily recover its menu icon. See [icon preferences](#icon-preferences).

## Pair the two Macs

1. Open **Settings → Devices** on both Macs.
2. Click **Add device · 2 min** on both, within the two-minute pairing window. The menu's **Pair devices…** also opens that window locally; it does not approve a peer by itself.
3. Select the other Mac and click **Connect / Pair**.
4. Compare the six-digit code on both screens. Confirm on both only if the codes match. If they differ, cancel.
5. Select the paired device as your default file destination. Each Mac has its own destination choice.

Pairing stores trust so you do not need to repeat the code every time. It does not mean the other app is currently running. In 0.4.0, **Paired · Connected** means a usable authenticated connection; **Paired · Not connected** means trust remains but there is no usable connection.

**Connect to last device at startup** in General defaults on in 0.4.0. After a successful connection, startup discovery may reconnect to that trusted device. This is separate from the default file destination, does not wake the other Mac and does not send any content automatically. The first upgrade needs a successful connection to establish the remembered device.

## Send and receive files

### Drag into the card

1. Check the default destination in Devices.
2. Start dragging files or a folder toward the upper center of the screen, **below the menu bar**.
3. When the card appears, drag inside it and release. Do not drag to the very top edge: macOS may open Mission Control there.
4. Watch the target name and transfer state. **Saved by the other Mac** means the receiver has checked and saved the files, not just received the bytes.

The same gesture works on a display without a notch. In 0.4.0, you can click the card's **×** while a task is active to cancel that task. The × disappears when the task ends. With overlapping tasks, the card prioritizes the most recently started active task.

### Use the file picker

Choose the menu's file-sending action or **Settings → Transfers → Choose files to send…**. It uses the same default destination and transfer rules as dragging.

On the receiving Mac, files are saved into its selected folder. Same-name items receive a suffix instead of overwriting existing items. Use **Transfers → Show recent files in Finder** to find files received during the current run.

**Open after receiving** is off by default. Enable it on a receiving Mac only if you want fully saved files from trusted peers opened in their default apps; folders open in Finder. It does not apply to text or partially failed transfers.

You can send in both directions at the same time. Multiple requests are supported, but each connection handles one active sending task and one receiving task at a time; additional sends queue. There is no offline delivery queue. If a connection or transfer fails, retry explicitly; no interrupted-transfer resume is available.

### A disconnected destination or insufficient space

In the current 0.4.0 source, a discovered but disconnected target gets up to five seconds to connect. If it cannot connect, the card and Settings explain the failure. Open the other app on the same LAN, then send again. These failed requests are not sent later without your action.

If the receiver lacks space, both ends get a failure reason. Free space on the **receiving** Mac and retry. A multi-item task can leave some fully saved items if final saving fails later; the message reports how many were saved. Those items remain, unfinished temporary contents are cleaned up, and retrying may create suffixed copies. A separate reverse transfer is not cancelled by one receiving task's disk-full failure.

This disk-space refinement is currently source-only relative to build27. See [validation records](VALIDATION.md) before expecting it in a local installer.

## Send plain text — 0.4.0

1. Confirm both Macs run a text-capable version and the target is paired **and connected**. If disconnected, use **Settings → Devices → Connect / Pair** first.
2. Choose **Send Text…** from the menu bar.
3. Select the target, then type or manually paste plain text. A temporary text target does not change your default file destination.
4. Click **Send** or press **⌘Enter**. Enter inserts a newline; Esc closes the panel, after any active input-method composition is cancelled normally.

A message can contain up to **256 KiB of UTF-8 text**. Emoji may use several bytes each. Empty strings cannot be sent; spaces, line breaks and Unicode are preserved.

The submitted draft stays while awaiting confirmation. A confirmed receipt clears it; failure or no confirmation after 30 seconds preserves it. “Receipt not confirmed” means receipt is uncertain, not proof that the other Mac never received it. No automatic resend occurs. Closing the panel keeps an unsent draft for this run; quitting the app discards it.

The receiver's notification identifies the sender without showing the text body. Click it, then choose **Copy Text**. If notifications are unavailable, use **Settings → Text → View Latest Received Text…**. Text never automatically replaces the clipboard, executes commands or opens links. File auto-open does not affect it, and no `.txt` file is created.

## Text history and privacy — 0.4.0

**Successful sends and receipts are always recorded on each Mac.** There is no “stop recording” switch. **Show Text History** only shows or hides the history entry.

In **Settings → Text**, you can:

- Open history to view/copy full text, delete one entry, or clear all after confirmation.
- Hide it with **Keep and Hide**, **Clear and Hide**, or cancel.
- Choose **Latest 500 entries** (default, sending and receiving combined), **Last 30 days**, or **Forever**. Shorter retention can delete older records after confirmation.
- Clear records even while the history entry is hidden. New successful messages will still be recorded afterwards.

History is local, not a shared or encrypted archive. Deleting here does not delete the other Mac's copy and does not guarantee secure erasure. Deleted or expired notification records show an explanatory message when opened.

If saving history fails, available text is retained in memory for the current run and can still be copied; the app warns that history was not saved. Copy important content before quitting. See [text details](TEXT.md).

## Everyday settings — 0.4.0

| Page | What to use it for |
|---|---|
| General | Device name, language, menu/Dock icons, login startup, startup connection and animation toggle |
| Devices | Default destination, connection, pairing/unpairing and manual connection information |
| Transfers | Receiving folder, auto-open preference, sending files and recent receipts |
| Text | Sending/viewing text, history visibility, retention and clearing |
| About | Product version, update checking, diagnostic details and maintenance |

Changing the device name requires **Save**; switches save immediately. Language changes apply after quitting and reopening, so finish transfers first. System file pickers, permission prompts and some provider errors may still use the macOS language. Animations have one fixed pace; the app toggle and macOS Reduce Motion can disable them.

### Icon preferences

**Show menu bar icon** and **Show Dock icon** are independent. Both can be on, either can be on, or both can be off. Hiding them does not quit PeerJetty or stop transfers.

When both are hidden, manually reopening the app temporarily restores the menu icon and opens Settings. The saved menu switch remains off. Turn it on to make the icon permanent, or choose **Hide temporary icon** to hide it again. Login startup respects saved hidden choices.

Without the Dock icon, Settings may hide when another app takes focus. Reopen it from the menu or Applications; the page and unsaved name remain. Use the menu's **Quit** to actually exit the app.

## Manual connection, unpairing and replacement

Use manual connection only when automatic discovery fails:

1. On the receiving/target Mac, expand **Devices → Manual connection information**.
2. Copy an address from its active Wi-Fi/Ethernet interface and the current listening port.
3. On the other Mac, choose **Manual address…** and enter that target address and port. For a new device, open Add device on both first and still compare the codes.

“Other network addresses” lists VPN/virtual/tunnel interfaces. An address being listed does not guarantee it is reachable. The port can change after restarting the app; use the current value. Do not expose or forward this port to the internet for this LAN-only workflow.

**Unpair…** removes trust, not just the live connection. This Mac stops related transfers immediately. With supported versions and an authenticated connection, confirmation means the peer has also saved the revocation. If the other Mac is offline, too old or cannot confirm, the message says this Mac unpaired but the peer has not confirmed. Do not assume the other copy changed. To use the devices together again, open Add device on both and compare a new code. Ordinary quit/disconnection does not unpair.

For a replacement Mac, install normally and pair it as a new device; unpair the retired one on remaining devices. Do not copy the old Mac's Keychain identity or configuration. Reset identity is a maintenance operation requiring fresh pairing, not a normal reconnect fix.

## Update and troubleshoot

Choose **Check for updates…** to look for a newer stable GitHub release. The check is manual and ignores local build-number-only changes. A 0.4.0 development build may report being ahead of the public 0.3.2 release; that is expected, not a recommendation to downgrade.

For an update, finish transfers, choose **Quit**, replace the installed App using the new DMG, then reopen. Normal updates retain settings and pairing. Exit OpenOnMini before migrating and avoid running both old and new apps together. See [update details](UPDATES.md).

| What you see | What to check |
|---|---|
| No device appears | Both apps open and Macs awake; same LAN; local-network permission; guest Wi-Fi/client isolation; then try manual connection |
| Paired but not connected | Open the peer app, connect in Devices, or retry file sending; pairing itself need not be reset |
| Text unsupported | Both Macs need text support; the public 0.3.2 DMG does not include it |
| No notification | Check notification permission; look in the receive folder or Text's latest-received entry |
| Cannot save / insufficient space | Check the receiver's folder permissions and free space; open Settings' full error details |
| Unexpected Keychain prompt | Verify the app source and stable Applications path; rebuilds/signature changes can cause authorization prompts. Do not remove the identity as the first fix |
| A long error is cut off | Open Settings and use **View details…** for the complete message |

For a report, provide version/build from **About → Diagnostic details**, macOS version and reproducible steps. Redact private file paths/names, device identifiers and message bodies. Never attach device configuration, private keys or history databases. [Issues](https://github.com/TimeLyr1c/PeerJetty/issues) · [Security reporting](../SECURITY.md).

## Where your data lives

| Item | Location / ownership |
|---|---|
| Installed app | `/Applications/PeerJetty.app` |
| Received files | The receiving folder you choose on that Mac; ordinary user files |
| Settings and trust | `~/Library/Application Support/PeerJetty/` |
| Private device identity | That Mac's local Keychain |
| Text history | `~/Library/Application Support/PeerJetty/TextHistory/history.sqlite` |
| Source and local builds | Your checkout; local builds under `outputs/`, separate from app data |

Keep private app state out of Git, Dropbox and bug-report attachments. PeerJetty transfers selected content; it does not mirror folders, keep histories synchronized, preserve all macOS file metadata or act as a backup. For implementation boundaries see [protocol](PROTOCOL.md); for source management see [workflow](WORKFLOW.md).
