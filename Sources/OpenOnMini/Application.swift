import AppKit
import PeerCore
import ServiceManagement
import UserNotifications
import Darwin

@main
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var store: ConfigurationStore?
    private var engine: PeerEngine?
    private var drop: DropPanelController?
    private var settings: SettingsController?
    private var menuItem: NSStatusItem?
    private var peers: [DiscoveredPeer] = []
    private var active: Set<UUID> = []
    private var lastTransfer: UUID?
    private var pairingWindows: [UUID: NSWindow] = [:]
    private var pairingCodes: [UUID: (name: String, code: String)] = [:]
    private var lastReceived: [URL] = []
    private var initialized = false
    private var notificationRequested = false
    private var pendingSettings = false
    private var bootError: String?
    private var preparing = 0
    private var promiseBusy = false

    static func main() {
        let app = NSApplication.shared; let delegate = AppDelegate()
        app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu(); UNUserNotificationCenter.current().delegate = self
        // Certificate generation and Keychain access must not block the UI run loop.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OpenOnMini")
                let fallback = Configuration(name: Host.current().localizedName ?? "Mac", receivePath: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path)
                let store = try ConfigurationStore(url: base.appendingPathComponent("configuration.json"), fallback: fallback)
                let identity = try DeviceIdentity.load()
                DispatchQueue.main.async { self?.finishStartup(store: store, identity: identity) }
            } catch { DispatchQueue.main.async { self?.bootError = error.localizedDescription; self?.showError(error.localizedDescription) } }
        }
    }
    private func finishStartup(store: ConfigurationStore, identity: DeviceIdentity) {
        self.store = store; let engine = PeerEngine(identity: identity, store: store); self.engine = engine
        let drop = DropPanelController(); self.drop = drop
        drop.view.onFiles = { [weak self] urls, cleanup in
            self?.promiseBusy = false
            guard let self, let peer = self.store?.snapshot.preferredPeer else {
                cleanup?(); self?.showStatus("请先在设置中配对并选择发送设备"); self?.showSettings(); return
            }
            self.engine?.send(urls: urls, peerID: peer, cleanup: cleanup)
        }
        drop.view.onReceivingPromise = { [weak self] in self?.promiseBusy = true; self?.refreshBusy(); self?.drop?.show() }
        drop.view.onFailure = { [weak self] text in self?.promiseBusy = false; self?.refreshBusy(); self?.showStatus(text) }
        drop.view.onCancel = { [weak self] in if let id = self?.lastTransfer { self?.engine?.cancel(transferID: id) } }
        engine.onPeers = { [weak self] peers in
            guard let self else { return }; self.peers = peers; self.settings?.updatePeers(peers, preferred: self.store?.snapshot.preferredPeer)
            let name = peers.first { $0.id == self.store?.snapshot.preferredPeer }?.name ?? "请选择发送设备"
            self.drop?.view.targetName = name
            if self.active.isEmpty { self.drop?.view.idle() }
        }
        engine.onStatus = { [weak self] text in
            guard let self else { return }; self.settings?.status(text)
            if self.active.isEmpty, !self.promiseBusy, self.preparing == 0 { self.drop?.busy = false; self.drop?.hide(after: 5) }
        }
        engine.onPreparation = { [weak self] value in
            guard let self else { return }; self.preparing = max(0, self.preparing + (value ? 1 : -1)); self.refreshBusy()
            if value { self.drop?.show(); self.drop?.view.show(title: "正在准备文件", subtitle: self.drop?.view.targetName ?? "") }
        }
        engine.onPairing = { [weak self] id, name, code in self?.showPairing(id: id, name: name, code: code) }
        engine.onPairingEnded = { [weak self] id in
            self?.pairingWindows.removeValue(forKey: id)?.close(); self?.pairingCodes.removeValue(forKey: id)
        }
        engine.onTransfer = { [weak self] update in
            guard let self else { return }
            if update.finished { self.active.remove(update.id) } else { self.active.insert(update.id); self.lastTransfer = update.id }
            self.refreshBusy(); self.drop?.show(); self.drop?.view.transfer(update)
            self.settings?.progress(update)
            if update.finished, self.active.isEmpty { self.lastTransfer = nil; self.drop?.hide(after: update.succeeded ? 1.5 : 5) }
        }
        engine.onReceived = { [weak self] name, urls in
            guard let self else { return }; self.lastReceived = urls; self.notifyReceived(name: name, count: urls.count)
            self.settings?.received(urls)
        }
        engine.onListening = { [weak self] port in self?.settings?.connectionInfo("本机连接地址：\(Self.localAddresses().joined(separator: " / "))    端口：\(port)") }
        initialized = true; engine.start()
        if !store.snapshot.onboardingComplete || pendingSettings { showSettings() }
    }
    private func setupMenu() {
        menuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menuItem?.button?.image = NSImage(systemSymbolName: "arrow.up.arrow.down.square", accessibilityDescription: "双向文件投放")
        let menu = NSMenu()
        for (title, action) in [("设备与设置…", #selector(showSettings)), ("添加设备（2 分钟）", #selector(addDevice)),
                                ("显示投放区", #selector(preview)), ("显示最近收到的文件", #selector(revealReceived)),
                                ("隐藏菜单栏图标", #selector(hideMenu)), ("退出", #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menuItem?.menu = menu
    }
    private func refreshBusy() { drop?.busy = !active.isEmpty || preparing > 0 || promiseBusy }
    @objc private func hideMenu() {
        if let menuItem { NSStatusBar.system.removeStatusItem(menuItem) }; menuItem = nil
        showStatus("再次打开 Applications 中的 App 可以显示设置")
    }
    @objc private func addDevice() { showSettings(); engine?.openPairing() }
    @objc private func preview() { drop?.preview() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func revealReceived() { if !lastReceived.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(lastReceived) } }
    @objc private func showSettings() {
        guard let store else { pendingSettings = true; if let bootError { showError(bootError) }; return }
        if settings == nil {
            let controller = SettingsController(configuration: store.snapshot); settings = controller
            controller.onSave = { [weak self] name in
                guard let self else { return }
                let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, value.utf8.count <= 256 else { self.settings?.status("设备名需为 1–64 个普通字符"); return }
                do { try store.update { $0.name = value; $0.onboardingComplete = true }; self.engine?.refresh(); self.requestNotifications(); self.settings?.status("设置已保存；请在两台设备上点击添加设备") }
                catch { self.showError(error.localizedDescription) }
            }
            controller.onSelect = { [weak self] id in
                guard let self else { return }
                do { try store.update { $0.preferredPeer = id }; self.engine?.refresh() } catch { self.showError(error.localizedDescription) }
            }
            controller.onPair = { [weak self] in self?.engine?.openPairing() }
            controller.onConnect = { [weak self] id in self?.engine?.connect(peerID: id) }
            controller.onForget = { [weak self] id in self?.engine?.forget(id) }
            controller.onFolder = { [weak self] in self?.chooseFolder() }
            controller.onSend = { [weak self] in self?.chooseFiles() }
            controller.onPreview = { [weak self] in self?.drop?.preview() }
            controller.onCancel = { [weak self] in if let id = self?.lastTransfer { self?.engine?.cancel(transferID: id) } }
            controller.onReveal = { [weak self] in self?.revealReceived() }
            controller.onManual = { [weak self] in self?.manualConnection() }
            controller.onPermissions = {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!)
            }
            controller.onDiskAccess = {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            controller.onLogin = { [weak self] enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    self?.settings?.status(SMAppService.mainApp.status == .enabled ? "已启用登录启动" : "请在系统设置中确认后台项目授权")
                } catch { self?.settings?.status(error.localizedDescription) }
                self?.settings?.loginState(SMAppService.mainApp.status == .enabled)
            }
            controller.onReset = { [weak self] in self?.resetIdentity() }
            controller.onQuit = { NSApp.terminate(nil) }
        }
        settings?.updatePeers(peers, preferred: store.snapshot.preferredPeer)
        settings?.loginState(SMAppService.mainApp.status == .enabled)
        settings?.showWindow(nil); NSApp.activate(ignoringOtherApps: true); settings?.window?.makeKeyAndOrderFront(nil)
    }
    private func chooseFolder() {
        guard active.isEmpty else { settings?.status("请等传输结束后再更换接收目录"); return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "选择接收目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            try store?.update { $0.receivePath = url.path; $0.receiveBookmark = bookmark }
            // The selected URL remains granted for this app session; persisted bookmark is restored next launch.
            settings?.folder(url.path); settings?.status("接收目录已更新")
        } catch { showError(error.localizedDescription) }
    }
    private func chooseFiles() {
        guard let peer = store?.snapshot.preferredPeer else { settings?.status("请先选择已配对的默认发送设备"); return }
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true; panel.prompt = "发送"
        if panel.runModal() == .OK { engine?.send(urls: panel.urls, peerID: peer) }
    }
    private func manualConnection() {
        let alert = NSAlert(); alert.messageText = "手动连接设备"
        alert.informativeText = "自动发现失败时，可输入另一台设备设置窗口显示的地址与端口。两端先开启添加设备；仍需核对校验码。"
        alert.addButton(withTitle: "连接"); alert.addButton(withTitle: "取消")
        let host = NSTextField(string: ""); host.placeholderString = "对方局域网 IP 或主机名"
        let port = NSTextField(string: ""); port.placeholderString = "对方显示的端口"
        let stack = NSStackView(views: [host, port]); stack.orientation = .vertical; stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 60); host.widthAnchor.constraint(equalToConstant: 360).isActive = true
        port.widthAnchor.constraint(equalToConstant: 360).isActive = true; alert.accessoryView = stack
        if alert.runModal() == .alertFirstButtonReturn, let value = UInt16(port.stringValue), value > 0 {
            engine?.openPairing(); engine?.connect(host: host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), port: value)
        }
    }
    private func showPairing(id: UUID, name: String, code: String) {
        pairingCodes[id] = (name, code)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "确认配对"; window.isReleasedWhenClosed = false; window.center()
        let label = NSTextField(labelWithString: "与「\(name)」配对"); label.frame = NSRect(x: 28, y: 175, width: 375, height: 30)
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        let number = NSTextField(labelWithString: code); number.frame = NSRect(x: 28, y: 110, width: 375, height: 55)
        number.font = .monospacedDigitSystemFont(ofSize: 40, weight: .medium)
        let detail = NSTextField(wrappingLabelWithString: "确认两台电脑显示的数字完全一致，并在两端分别确认。数字不同请取消。"); detail.frame = NSRect(x: 28, y: 65, width: 375, height: 40)
        let yes = NSButton(title: "数字一致，确认配对", target: self, action: #selector(confirmPairing(_:)))
        let no = NSButton(title: "取消", target: self, action: #selector(rejectPairing(_:)))
        yes.identifier = NSUserInterfaceItemIdentifier(id.uuidString); no.identifier = yes.identifier
        yes.frame = NSRect(x: 170, y: 20, width: 230, height: 32); no.frame = NSRect(x: 25, y: 20, width: 100, height: 32)
        [label, number, detail, yes, no].forEach { window.contentView?.addSubview($0) }
        pairingWindows[id] = window; NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    @objc private func confirmPairing(_ button: NSButton) {
        guard let value = button.identifier?.rawValue, let id = UUID(uuidString: value) else { return }
        button.isEnabled = false; button.title = "等待对方确认…"; engine?.confirm(sessionID: id, approved: true)
    }
    @objc private func rejectPairing(_ button: NSButton) {
        guard let value = button.identifier?.rawValue, let id = UUID(uuidString: value) else { return }; engine?.confirm(sessionID: id, approved: false)
    }
    private func resetIdentity() {
        guard active.isEmpty else { settings?.status("请等传输结束后重置身份"); return }
        let alert = NSAlert(); alert.messageText = "重置本机身份？"
        alert.informativeText = "会清除本机配对记录并退出 App。重新打开后，需与所有设备重新配对。已收到的文件保留。"
        alert.addButton(withTitle: "重置并退出"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try DeviceIdentity.reset(); try store?.update { $0.peers = []; $0.preferredPeer = nil; $0.onboardingComplete = false }
            NSApp.terminate(nil)
        } catch { showError(error.localizedDescription) }
    }
    private func requestNotifications() {
        guard !notificationRequested else { return }; notificationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    private func notifyReceived(name: String, count: Int) {
        let content = UNMutableNotificationContent(); content.title = "收到 \(count) 项文件"; content.body = "来自 \(name)，已保存到接收目录"; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) { completion([.banner, .sound]) }
    private func showStatus(_ text: String) {
        settings?.status(text); drop?.show(); drop?.view.show(title: "请查看设置", subtitle: text, symbol: "exclamationmark.triangle.fill", color: .systemOrange); drop?.hide(after: 5)
    }
    private func showError(_ text: String) {
        let alert = NSAlert(); alert.messageText = "OpenOnMini"; alert.informativeText = text; alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { engine?.stop() }
    private static func localAddresses() -> [String] {
        var addresses: [String] = []; var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return ["查看系统网络设置"] }; defer { freeifaddrs(list) }
        var node = list
        while let item = node {
            let info = item.pointee; node = info.ifa_next
            guard let address = info.ifa_addr, address.pointee.sa_family == UInt8(AF_INET), info.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 { addresses.append(String(cString: buffer)) }
        }
        return addresses.isEmpty ? ["无可用局域网地址"] : Array(Set(addresses)).sorted()
    }
}
