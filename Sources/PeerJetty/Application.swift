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
    private var latestText: UUID?
    private var composer: TextComposer?
    private var textHistoryWindow: TextHistoryWindow?
    private var textReader: TextReader?
    private let historyQueue = DispatchQueue(label:"PeerJetty.TextHistory")
    private var history: TextHistory?
    private var volatileTexts: [UUID:TextEntry] = [:]
    private var volatileOrder: [UUID] = []
    private var updateWindow: UpdateWindow?
    private var menuBar: MenuBarController?
    private var listeningPort: UInt16?
    private var lastStatus: String?
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
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                let fallback = Configuration(name: Host.current().localizedName ?? "Mac", receivePath: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path)
                let store = try ConfigurationStore.forApplication(applicationSupport: base, fallback: fallback)
                let identity = try DeviceIdentity.load()
                DispatchQueue.main.async { self?.finishStartup(store: store, identity: identity) }
            } catch { DispatchQueue.main.async { self?.bootError = error.localizedDescription; self?.showError(error.localizedDescription) } }
        }
    }
    private func finishStartup(store: ConfigurationStore, identity: DeviceIdentity) {
        MotionPolicy.shared.enabled = store.snapshot.animationsEnabled
        self.store = store; let engine = PeerEngine(identity: identity, store: store); self.engine = engine
        historyQueue.async { [weak self] in
            do { _ = try self?.ensureHistory() } catch { DispatchQueue.main.async { self?.settings?.status(L10n.text("text.history_failed")) } }
        }
        let drop = DropPanelController(); self.drop = drop
        drop.view.onFiles = { [weak self] urls, cleanup in
            self?.promiseBusy = false
            guard let self, let peer = self.store?.snapshot.preferredPeer else {
                cleanup?(); self?.showStatus(L10n.text("application.pair_and_select_a_destination_in_settings_first")); self?.showSettings(); return
            }
            self.engine?.send(urls: urls, peerID: peer, cleanup: cleanup)
        }
        drop.view.onReceivingPromise = { [weak self] in self?.promiseBusy = true; self?.refreshBusy(); self?.drop?.show() }
        drop.view.onFailure = { [weak self] text in self?.promiseBusy = false; self?.refreshBusy(); self?.showStatus(text) }
        drop.view.onCancel = { [weak self] in if let id = self?.lastTransfer { self?.engine?.cancel(transferID: id) } }
        engine.onPeers = { [weak self] peers in
            guard let self else { return }; self.peers = peers; self.composer?.updatePeers(peers,preferred:store.snapshot.preferredPeer); self.settings?.updatePeers(peers, preferred: self.store?.snapshot.preferredPeer)
            let name = peers.first { $0.id == self.store?.snapshot.preferredPeer }?.name ?? L10n.text("dropzone.choose_a_destination")
            self.drop?.view.targetName = name
            if self.active.isEmpty { self.drop?.view.idle() }
        }
        engine.onStatus = { [weak self] text in
            guard let self else { return }; self.settings?.status(text)
            if self.active.isEmpty, !self.promiseBusy, self.preparing == 0 { self.drop?.busy = false; self.drop?.hide(after: 5) }
        }
        engine.onPreparation = { [weak self] value in
            guard let self else { return }; self.preparing = max(0, self.preparing + (value ? 1 : -1)); self.refreshBusy()
            if value { self.drop?.show(); self.drop?.view.show(title: L10n.text("application.preparing_files"), subtitle: self.drop?.view.targetName ?? "") }
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
            let enabled = store.snapshot.autoOpenReceivedFiles
            let failures = ReceivedFileActions.openCommitted(urls, enabled: enabled) { NSWorkspace.shared.open($0) }
            if !failures.isEmpty {
                self.settings?.status(L10n.text("receive.open_failures", urls.count, failures.count))
                let content = UNMutableNotificationContent()
                content.title = L10n.text("application.files_saved_some_could_not_be_opened"); content.body = L10n.text("application.view_recently_received_files_in_peerjetty")
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            } else {
                self.settings?.status(L10n.text(enabled ? "receive.saved_open" : "receive.saved", urls.count))
            }
        }
        engine.onTextReceived = { [weak self] payload, acknowledge in
            guard let self else { return }
            self.saveText(TextEntry(payload:payload,direction:.received)) { id,saved in
                self.latestText = id; self.settings?.latestTextState(true); self.notifyText(id:id,peerName:payload.peerName,saved:saved); acknowledge()
            }
        }
        engine.onTextResult = { [weak self] payload, error in
            guard let self else { return }; self.composer?.result(payload.id,error:error)
            if error == nil { self.saveText(TextEntry(payload:payload,direction:.sent)) { _,_ in } }
        }
        engine.onListening = { [weak self] port in self?.listeningPort = port; self?.updateConnectionInfo() }
        initialized = true; engine.start()
        if !store.snapshot.onboardingComplete || pendingSettings { showSettings() }
    }
    private func setupMenu() {
        let bar = MenuBarController(actions: [.pair:{ [weak self] in self?.addDevice() },
            .sendFiles:{ [weak self] in self?.chooseFiles() }, .sendText:{ [weak self] in self?.sendText() },
            .updates:{ [weak self] in self?.checkUpdates() }, .settings:{ [weak self] in self?.showSettings() },
            .quit:{ NSApp.terminate(nil) }])
        menuBar = bar
        bar.onVisibility = { [weak self] value in self?.applyMenuVisibility(value) }
        applyMenuVisibility(bar.isVisible)
    }
    private func applyMenuVisibility(_ visible: Bool) {
        let wasVisible = settings?.window?.isVisible == true
        NSApp.setActivationPolicy(MenuBarController.activationPolicy(visible:visible))
        settings?.menuBarState(visible)
        if wasVisible { settings?.window?.makeKeyAndOrderFront(nil) }
    }
    private func refreshBusy() { drop?.busy = !active.isEmpty || preparing > 0 || promiseBusy }
    private func updateConnectionInfo() {
        let text = listeningPort.map { L10n.text("connection.local_address", Self.localAddresses().joined(separator:" / "), String($0)) } ?? L10n.text("settings.connection_not_ready")
        settings?.connectionInfo(text)
    }
    @objc private func addDevice() { showSettings(); settings?.selectSection(.devices); engine?.openPairing() }
    @objc private func preview() { drop?.preview() }
    @objc private func checkUpdates() {
        if updateWindow == nil {
            updateWindow = UpdateWindow(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        }
        updateWindow?.present()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func revealReceived() { if !lastReceived.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(lastReceived) } }
    @objc private func showSettings() {
        guard let store else { pendingSettings = true; if let bootError { showError(bootError) }; return }
        if settings == nil {
            let controller = SettingsController(configuration: store.snapshot); settings = controller
            controller.onSave = { [weak self] name in
                guard let self else { return }
                let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, value.utf8.count <= 256 else { self.settings?.status(L10n.text("application.enter_a_short_nonempty_device_name")); return }
                do { try store.update { $0.name = value; $0.onboardingComplete = true }; self.engine?.refresh(); self.requestNotifications(); self.settings?.status(L10n.text("application.settings_saved_select_add_device_on_both_macs")) }
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
            controller.onMenuBar = { [weak self] visible in self?.menuBar?.setVisible(visible) }
            controller.onLatestText = { [weak self] in self?.openLatestText() }
            controller.onSendText = { [weak self] in self?.sendText() }
            controller.onTextHistory = { [weak self] in self?.showTextHistory() }
            controller.onClearTextHistory = { [weak self] in self?.deleteTextHistory(nil) }
            controller.onTextHistoryVisibility = { [weak self] value in self?.setHistoryVisible(value) }
            controller.onTextRetention = { [weak self] value in self?.setTextRetention(value) }
            controller.onUpdates = { [weak self] in self?.checkUpdates() }
            controller.onLanguage = { selection in LanguagePreferences().save(selection) }
            controller.onAnimations = { [weak self] enabled in
                do { try store.update { $0.animationsEnabled = enabled }; MotionPolicy.shared.enabled = enabled }
                catch { self?.settings?.animationState(store.snapshot.animationsEnabled); self?.showError(error.localizedDescription) }
            }
            controller.onAutoOpen = { [weak self] enabled in
                do {
                    try store.update { $0.autoOpenReceivedFiles = enabled }
                    self?.settings?.status(enabled ? L10n.text("application.opening_received_files_is_enabled") : L10n.text("application.opening_received_files_is_disabled"))
                } catch {
                    self?.settings?.autoOpenState(store.snapshot.autoOpenReceivedFiles)
                    self?.showError(error.localizedDescription)
                }
            }
            controller.onLogin = { [weak self] enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    self?.settings?.status(SMAppService.mainApp.status == .enabled ? L10n.text("application.start_at_login_is_enabled") : L10n.text("application.allow_the_background_item_in_system_settings"))
                } catch { self?.settings?.status(error.localizedDescription) }
                self?.settings?.loginState(SMAppService.mainApp.status == .enabled)
            }
            controller.onReset = { [weak self] in self?.resetIdentity() }
            controller.onQuit = { NSApp.terminate(nil) }
        }
        settings?.menuBarState(menuBar?.isVisible ?? true)
        settings?.latestTextState(latestText != nil)
        updateConnectionInfo()
        if let lastStatus { settings?.status(lastStatus) }
        settings?.updatePeers(peers, preferred: store.snapshot.preferredPeer)
        settings?.animationState(store.snapshot.animationsEnabled)
        settings?.autoOpenState(store.snapshot.autoOpenReceivedFiles)
        settings?.loginState(SMAppService.mainApp.status == .enabled)
        settings?.showWindow(nil); NSApp.activate(ignoringOtherApps: true); settings?.window?.makeKeyAndOrderFront(nil)
    }
    private func chooseFolder() {
        guard active.isEmpty else { settings?.status(L10n.text("application.wait_for_transfers_to_finish_before_changing_the")); return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("application.choose_receive_folder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            try store?.update { $0.receivePath = url.path; $0.receiveBookmark = bookmark }
            // The selected URL remains granted for this app session; persisted bookmark is restored next launch.
            settings?.folder(url.path); settings?.status(L10n.text("application.receive_folder_updated"))
        } catch { showError(error.localizedDescription) }
    }
    private func chooseFiles() {
        guard initialized else { showSettings(); return }
        guard let peer = store?.snapshot.preferredPeer else { showSettings(); settings?.selectSection(.devices); settings?.status(L10n.text("application.select_a_paired_device_as_your_default_destination")); return }
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true; panel.prompt = L10n.text("application.send")
        if panel.runModal() == .OK { engine?.send(urls: panel.urls, peerID: peer) }
    }
    private func manualConnection() {
        let alert = NSAlert(); alert.messageText = L10n.text("application.connect_manually")
        alert.informativeText = L10n.text("application.if_discovery_fails_enter_the_address_and_port")
        alert.addButton(withTitle: L10n.text("application.connect")); alert.addButton(withTitle: L10n.text("dropzone.cancel"))
        let host = NSTextField(string: ""); host.placeholderString = L10n.text("application.other_mac_s_lan_address_or_hostname")
        let port = NSTextField(string: ""); port.placeholderString = L10n.text("application.port_shown_on_the_other_mac")
        let stack = NSStackView(views: [host, port]); stack.orientation = .vertical; stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 60); host.widthAnchor.constraint(equalToConstant: 360).isActive = true
        port.widthAnchor.constraint(equalToConstant: 360).isActive = true; alert.accessoryView = stack
        if alert.runModal() == .alertFirstButtonReturn, let value = UInt16(port.stringValue), value > 0 {
            engine?.openPairing(); engine?.connect(host: host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), port: value)
        }
    }
    private func showPairing(id: UUID, name: String, code: String) {
        pairingCodes[id] = (name, code)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = L10n.text("application.confirm_pairing"); window.isReleasedWhenClosed = false; window.center()
        let label = NSTextField(labelWithString: L10n.text("application.pair_with", String(describing: name))); label.frame = NSRect(x: 28, y: 230, width: 375, height: 30)
        label.font = .systemFont(ofSize: 17, weight: .semibold); label.lineBreakMode = .byTruncatingMiddle
        let number = NSTextField(labelWithString: code); number.frame = NSRect(x: 28, y: 165, width: 375, height: 55)
        number.font = .monospacedDigitSystemFont(ofSize: 40, weight: .medium)
        let detail = NSTextField(wrappingLabelWithString: L10n.text("application.compare_the_code_on_both_macs_and_confirm")); detail.frame = NSRect(x: 28, y: 75, width: 375, height: 75)
        let yes = NSButton(title: L10n.text("application.codes_match_pair"), target: self, action: #selector(confirmPairing(_:)))
        let no = NSButton(title: L10n.text("dropzone.cancel"), target: self, action: #selector(rejectPairing(_:)))
        yes.identifier = NSUserInterfaceItemIdentifier(id.uuidString); no.identifier = yes.identifier
        yes.frame = NSRect(x: 170, y: 20, width: 230, height: 32); no.frame = NSRect(x: 25, y: 20, width: 100, height: 32)
        [label, number, detail, yes, no].forEach { window.contentView?.addSubview($0) }
        pairingWindows[id] = window; NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    @objc private func confirmPairing(_ button: NSButton) {
        guard let value = button.identifier?.rawValue, let id = UUID(uuidString: value) else { return }
        button.isEnabled = false; button.title = L10n.text("application.waiting_for_the_other_mac"); engine?.confirm(sessionID: id, approved: true)
    }
    @objc private func rejectPairing(_ button: NSButton) {
        guard let value = button.identifier?.rawValue, let id = UUID(uuidString: value) else { return }; engine?.confirm(sessionID: id, approved: false)
    }
    private func resetIdentity() {
        guard active.isEmpty else { settings?.status(L10n.text("application.wait_for_transfers_to_finish_before_resetting_identity")); return }
        let alert = NSAlert(); alert.messageText = L10n.text("application.reset_this_device_s_identity")
        alert.informativeText = L10n.text("application.this_clears_local_pairings_and_quits_peerjetty_reopen")
        alert.addButton(withTitle: L10n.text("application.reset_and_quit")); alert.addButton(withTitle: L10n.text("dropzone.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try DeviceIdentity.reset(); try store?.update { $0.peers = []; $0.preferredPeer = nil; $0.onboardingComplete = false }
            NSApp.terminate(nil)
        } catch { showError(error.localizedDescription) }
    }
    private func ensureHistory() throws -> TextHistory {
        if let history { return history }
        let base = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        let value = try TextHistory(url:base.appendingPathComponent("PeerJetty/TextHistory/history.sqlite"))
        try value.clean(retention:store?.snapshot.textRetention ?? .latest500); history = value; return value
    }
    private func saveText(_ entry:TextEntry, completion:@escaping (UUID,Bool)->Void) {
        historyQueue.async { [weak self] in
            guard let self else { return }
            do {
                let id = try self.ensureHistory().add(entry,retention:self.store?.snapshot.textRetention ?? .latest500)
                DispatchQueue.main.async { completion(id,true); self.textHistoryWindow?.reload() }
            } catch {
                DispatchQueue.main.async {
                    self.volatileTexts[entry.id] = entry; self.volatileOrder.append(entry.id)
                    if self.volatileOrder.count > 500 { self.volatileTexts.removeValue(forKey:self.volatileOrder.removeFirst()) }
                    self.settings?.status(L10n.text("text.history_failed")); self.composer?.historyFailure(); completion(entry.id,false)
                }
            }
        }
    }
    @objc private func sendText() {
        guard let store else { showSettings(); return }
        if composer == nil {
            let value = TextComposer(); composer = value
            value.onSend = { [weak self] text,peer in self?.engine?.sendText(text,peerID:peer) }
            value.onConnect = { [weak self] peer in self?.engine?.connect(peerID:peer) }
            value.onVisibility = { [weak self] screen in self?.drop?.setEditingScreen(screen) }
        }
        composer?.updatePeers(peers,preferred:store.snapshot.preferredPeer,resetSelection:true); composer?.present()
    }
    @objc private func showTextHistory() {
        guard store?.snapshot.showTextHistory == true else { settings?.status(L10n.text("text.hidden_hint")); return }
        if textHistoryWindow == nil {
            let value = TextHistoryWindow(); textHistoryWindow = value
            value.onLoad = { [weak self] offset in
                guard let self else { return }
                self.historyQueue.async {
                    do {
                        let rows = try self.ensureHistory().list(retention:self.store?.snapshot.textRetention ?? .latest500,offset:offset)
                        DispatchQueue.main.async { self.textHistoryWindow?.update(rows) }
                    } catch { DispatchQueue.main.async { self.textHistoryWindow?.update([],error:error) } }
                }
            }
            value.onOpen = { [weak self] id in self?.openText(id) }
            value.onDelete = { [weak self] id in self?.deleteTextHistory(id) }
        }
        textHistoryWindow?.present()
    }
    @objc private func openLatestText() {
        guard let id = latestText else { showError(L10n.text("text.no_received")); return }; openText(id)
    }
    private func openText(_ id:UUID) {
        if let entry = volatileTexts[id] { textReader?.close(); textReader = TextReader(entry:entry,saved:false); textReader?.present(); return }
        historyQueue.async { [weak self] in
            guard let self else { return }
            do {
                let entry = try self.ensureHistory().get(id,retention:self.store?.snapshot.textRetention ?? .latest500)
                DispatchQueue.main.async {
                    guard let entry else { self.showError(L10n.text("text.expired")); return }
                    self.textReader?.close(); self.textReader = TextReader(entry:entry); self.textReader?.present()
                }
            } catch { DispatchQueue.main.async { self.showError(error.localizedDescription) } }
        }
    }
    private func confirmTextAction(_ key:String) -> Bool {
        let alert = NSAlert(); alert.messageText = L10n.text(key)
        alert.informativeText = L10n.text("text.delete_hint"); alert.addButton(withTitle:L10n.text("text.confirm")); alert.addButton(withTitle:L10n.text("dropzone.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
    private func deleteTextHistory(_ id:UUID?, completion:(()->Void)? = nil, confirmed:Bool = false) {
        guard confirmed || confirmTextAction(id == nil ? "text.clear" : "text.delete") else { return }
        historyQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.ensureHistory().delete(id)
                DispatchQueue.main.async {
                    if let id { self.volatileTexts.removeValue(forKey:id); self.volatileOrder.removeAll { $0 == id } }
                    else { self.volatileTexts.removeAll(); self.volatileOrder.removeAll() }
                    self.textReader?.close(); self.textHistoryWindow?.reload(); completion?()
                }
            } catch { DispatchQueue.main.async { self.showError(error.localizedDescription); self.syncTextSettings() } }
        }
    }
    private func syncTextSettings() {
        if let config = store?.snapshot {
            settings?.textHistoryState(config.showTextHistory,retention:config.textRetention)
            if !config.showTextHistory { textHistoryWindow?.close() }
        }
    }
    private func setHistoryVisible(_ value:Bool) {
        let apply = { [weak self] in
            do { try self?.store?.update { $0.showTextHistory = value }; self?.syncTextSettings() }
            catch { self?.showError(error.localizedDescription); self?.syncTextSettings() }
        }
        guard !value else { apply(); return }
        let alert = NSAlert(); alert.messageText = L10n.text("text.hide_title"); alert.informativeText = L10n.text("text.hide_hint")
        for key in ["text.keep_hide","text.clear_hide","dropzone.cancel"] { alert.addButton(withTitle:L10n.text(key)) }
        switch alert.runModal() {
        case .alertFirstButtonReturn: apply()
        case .alertSecondButtonReturn: deleteTextHistory(nil,completion:apply,confirmed:true)
        default: syncTextSettings()
        }
    }
    private func setTextRetention(_ value:TextRetention) {
        guard let old = store?.snapshot.textRetention, old != value else { return }
        if value != .forever && !confirmTextAction("text.retention_confirm") { syncTextSettings(); return }
        do { try store?.update { $0.textRetention = value }; syncTextSettings() }
        catch { showError(error.localizedDescription); syncTextSettings(); return }
        historyQueue.async { [weak self] in
            do { try self?.ensureHistory().clean(retention:value); DispatchQueue.main.async { self?.textHistoryWindow?.reload() } }
            catch { DispatchQueue.main.async { self?.showError(error.localizedDescription) } }
        }
    }
    private func notifyText(id:UUID,peerName:String,saved:Bool) {
        let content = textNotificationContent(id:id,peerName:peerName,saved:saved)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:"text-"+id.uuidString,content:content,trigger:nil))
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter, didReceive response:UNNotificationResponse, withCompletionHandler completion:@escaping ()->Void) {
        if let value = response.notification.request.content.userInfo["textEntry"] as? String, let id = UUID(uuidString:value) {
            DispatchQueue.main.async { [weak self] in self?.openText(id) }
        }
        completion()
    }
    private func requestNotifications() {
        guard !notificationRequested else { return }; notificationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    private func notifyReceived(name: String, count: Int) {
        let content = UNMutableNotificationContent(); content.title = L10n.text("receive.notification_count", count); content.body = L10n.text("application.from_saved_to_your_receive_folder", String(describing: name)); content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) { completion([.banner, .sound]) }
    private func showStatus(_ text: String) {
        lastStatus = text; settings?.status(text); drop?.show(); drop?.view.show(title: L10n.text("application.see_settings"), subtitle: L10n.text("application.status_details_hint"), symbol: "exclamationmark.triangle.fill", color: .systemOrange); drop?.hide(after: 5)
    }
    private func showError(_ text: String) {
        let alert = NSAlert(); alert.messageText = "PeerJetty"; alert.informativeText = text; alert.addButton(withTitle: L10n.text("application.ok"))
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { engine?.stop() }
    private static func localAddresses() -> [String] {
        var addresses: [String] = []; var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [L10n.text("application.see_system_network_settings")] }; defer { freeifaddrs(list) }
        var node = list
        while let item = node {
            let info = item.pointee; node = info.ifa_next
            guard let address = info.ifa_addr, address.pointee.sa_family == UInt8(AF_INET), info.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 { addresses.append(String(cString: buffer)) }
        }
        return addresses.isEmpty ? [L10n.text("application.no_local_network_address_available")] : Array(Set(addresses)).sorted()
    }
}
