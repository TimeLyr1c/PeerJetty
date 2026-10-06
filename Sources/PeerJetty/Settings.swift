import AppKit
import PeerCore

final class SettingsController: NSWindowController {
    var onSave: ((String) -> Void)?
    var onSelect: ((String) -> Void)?
    var onPair: (() -> Void)?
    var onConnect: ((String) -> Void)?
    var onForget: ((String) -> Void)?
    var onFolder: (() -> Void)?
    var onSend: (() -> Void)?
    var onPreview: (() -> Void)?
    var onCancel: (() -> Void)?
    var onReveal: (() -> Void)?
    var onManual: (() -> Void)?
    var onPermissions: (() -> Void)?
    var onUpdates: (() -> Void)?
    var onLanguage: ((DisplayLanguage) -> Void)?
    var onAutoOpen: ((Bool) -> Void)?
    var onLogin: ((Bool) -> Void)?
    var onReset: (() -> Void)?
    var onQuit: (() -> Void)?
    private let name = NSTextField()
    private let devices = NSPopUpButton()
    private let language = NSPopUpButton()
    private let folderLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: L10n.text("settings.preparing_to_connect"))
    private let progressLabel = NSTextField(wrappingLabelWithString: L10n.text("settings.no_transfers_yet"))
    private let connectionLabel = NSTextField(wrappingLabelWithString: "")
    private let login = NSSwitch()
    private let autoOpen = NSSwitch()
    private var peers: [DiscoveredPeer] = []
    init(configuration: Configuration, displayLanguage: DisplayLanguage = LanguagePreferences().selection) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: min(810, (NSScreen.main?.visibleFrame.height ?? 900) - 70)), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = L10n.text("settings.peerjetty_file_handoff"); window.isReleasedWhenClosed = false; window.center()
        super.init(window: window)
        language.addItems(withTitles: [L10n.text("settings.language_system"), L10n.text("settings.language_english"), L10n.text("settings.language_chinese")])
        language.selectItem(at: DisplayLanguage.allCases.firstIndex(of: displayLanguage) ?? 0)
        language.identifier = NSUserInterfaceItemIdentifier("displayLanguage")
        language.target = self; language.action = #selector(changeLanguage)
        name.stringValue = configuration.name; folderLabel.stringValue = configuration.receivePath
        let title = NSTextField(labelWithString: configuration.onboardingComplete ? L10n.text("settings.devices_settings") : L10n.text("settings.welcome_to_peerjetty"))
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let intro = NSTextField(wrappingLabelWithString: L10n.text("settings.install_peerjetty_on_both_macs_and_pair_them"))
        intro.textColor = .secondaryLabelColor
        let version = NSTextField(labelWithString: AppVersion.summary)
        version.font = .systemFont(ofSize: 11); version.textColor = .secondaryLabelColor
        version.toolTip = AppVersion.details
        name.widthAnchor.constraint(greaterThanOrEqualToConstant: 290).isActive = true
        devices.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        devices.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        folderLabel.lineBreakMode = .byTruncatingMiddle; folderLabel.maximumNumberOfLines = 2
        connectionLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular); connectionLabel.textColor = .secondaryLabelColor
        devices.target = self; devices.action = #selector(selectPeer)
        login.target = self; login.action = #selector(toggleLogin)
        autoOpen.target = self; autoOpen.action = #selector(toggleAutoOpen)
        autoOpen.state = configuration.autoOpenReceivedFiles ? .on : .off
        let openHint = NSTextField(wrappingLabelWithString: L10n.text("settings.when_enabled_saved_files_from_paired_devices_open"))
        openHint.font = .systemFont(ofSize: 11); openHint.textColor = .secondaryLabelColor
        let languageHint = NSTextField(wrappingLabelWithString: L10n.text("settings.language_restart"))
        languageHint.font = .systemFont(ofSize: 11); languageHint.textColor = .secondaryLabelColor
        let rows: [NSView] = [title, intro,
            row([NSTextField(labelWithString: L10n.text("settings.language")), language]), languageHint,
            row([NSTextField(labelWithString: L10n.text("settings.device_name")), name, button(L10n.text("settings.save_finish_setup"), #selector(save))]),
            row([NSTextField(labelWithString: L10n.text("settings.receive_folder")), button(L10n.text("settings.choose_folder"), #selector(chooseFolder))]), folderLabel,
            separator(), NSTextField(wrappingLabelWithString: L10n.text("settings.devices_select_a_paired_device_as_your_default")),
            row([devices, button(L10n.text("settings.connect_pair"), #selector(connect))]),
            row([button(L10n.text("settings.add_device_min"), #selector(pair)), button(L10n.text("settings.manual_address"), #selector(manual)), button(L10n.text("settings.remove_trust"), #selector(forget))]),
            connectionLabel, separator(),
            NSTextField(wrappingLabelWithString: L10n.text("settings.drag_toward_the_upper_center_below_the_menu")),
            row([button(L10n.text("settings.choose_files_to_send"), #selector(send)), button(L10n.text("settings.preview_drop_card"), #selector(preview)), button(L10n.text("settings.cancel_transfer"), #selector(cancel))]),
            progressLabel, button(L10n.text("settings.show_recent_files_in_finder"), #selector(reveal)), separator(),
            row([NSTextField(labelWithString: L10n.text("settings.open_after_receiving")), autoOpen]), openHint,
            row([NSTextField(labelWithString: L10n.text("settings.start_at_login")), login, button(L10n.text("settings.local_network_access"), #selector(permissions))]),
            row([button(L10n.text("updates.title"), #selector(checkUpdates)), button(L10n.text("settings.reset_identity"), #selector(reset)), button(L10n.text("settings.quit"), #selector(quit))]),
            statusLabel, version]
        let stack = NSStackView(views: rows); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        let scroll = NSScrollView(frame: content.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let document = SettingsDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document; content.addSubview(scroll); document.addSubview(stack)
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                                     document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
                                     stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
                                     stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
                                     stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 25),
                                     stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)])
        for label in [intro, openHint, folderLabel, statusLabel, progressLabel, connectionLabel] { label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        for view in rows {
            if view is NSStackView { view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true }
            if let label = view as? NSTextField { label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        }
        for box in rows.compactMap({ $0 as? NSBox }) { box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        statusLabel.textColor = .secondaryLabelColor; statusLabel.maximumNumberOfLines = 3
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    private func row(_ views: [NSView]) -> NSStackView { let row = NSStackView(views: views); row.orientation = .horizontal; row.spacing = 10; row.alignment = .centerY; return row }
    private func button(_ title: String, _ action: Selector) -> NSButton { let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded; return button }
    private func separator() -> NSView { let box = NSBox(); box.boxType = .separator; return box }
    func updatePeers(_ peers: [DiscoveredPeer], preferred: String?) {
        let selected = devices.indexOfSelectedItem >= 0 && self.peers.indices.contains(devices.indexOfSelectedItem) ? self.peers[devices.indexOfSelectedItem].id : preferred
        self.peers = peers; devices.removeAllItems()
        for peer in peers {
            let state = peer.paired ? (peer.connected ? L10n.text("settings.paired_online") : L10n.text("settings.paired_offline")) : L10n.text("settings.available_to_pair")
            devices.addItem(withTitle: L10n.text("settings.peer_entry", peer.name, state, String(peer.id.prefix(6))))
        }
        if peers.isEmpty { devices.addItem(withTitle: L10n.text("settings.select_add_device_on_both_macs")) }
        if let id = selected ?? preferred, let index = peers.firstIndex(where: { $0.id == id }) { devices.selectItem(at: index) }
    }
    private var selected: DiscoveredPeer? { peers.indices.contains(devices.indexOfSelectedItem) ? peers[devices.indexOfSelectedItem] : nil }
    func status(_ text: String) { statusLabel.stringValue = text }
    func folder(_ path: String) { folderLabel.stringValue = path }
    func connectionInfo(_ text: String) { connectionLabel.stringValue = text }
    func loginState(_ enabled: Bool) { login.state = enabled ? .on : .off }
    func autoOpenState(_ enabled: Bool) { autoOpen.state = enabled ? .on : .off }
    func progress(_ update: TransferUpdate) {
        let percent = update.total > 0 ? Int(Double(update.completed) / Double(update.total) * 100) : 0
        let key = update.receiving ? "settings.receiving_progress" : "settings.sending_progress"
        let detail = L10n.text(key, update.peerName, update.status)
        progressLabel.stringValue = update.finished ? detail : L10n.text("settings.progress_percent", detail, L10n.percent(percent))
    }
    @objc private func save() { onSave?(name.stringValue) }
    @objc private func selectPeer() { if let selected, selected.paired { onSelect?(selected.id) } }
    @objc private func connect() { if let selected { onConnect?(selected.id) } }
    @objc private func pair() { onPair?() }
    @objc private func forget() { if let selected, selected.paired { onForget?(selected.id) } }
    @objc private func chooseFolder() { onFolder?() }
    @objc private func send() { onSend?() }
    @objc private func preview() { onPreview?() }
    @objc private func cancel() { onCancel?() }
    @objc private func reveal() { onReveal?() }
    @objc private func manual() { onManual?() }
    @objc private func permissions() { onPermissions?() }
    @objc private func changeLanguage() {
        guard DisplayLanguage.allCases.indices.contains(language.indexOfSelectedItem) else { return }
        onLanguage?(DisplayLanguage.allCases[language.indexOfSelectedItem])
        status(L10n.text("settings.language_restart"))
    }
    @objc private func toggleAutoOpen() { onAutoOpen?(autoOpen.state == .on) }
    @objc private func toggleLogin() { onLogin?(login.state == .on) }
    @objc private func checkUpdates() { onUpdates?() }
    @objc private func reset() { onReset?() }
    @objc private func quit() { onQuit?() }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
