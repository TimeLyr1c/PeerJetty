import AppKit
import PeerCore

enum SettingsSection: String, CaseIterable {
    case general, devices, transfers, text, about
    var title: String {
        switch self {
        case .general: return L10n.text("settings.tab_general")
        case .devices: return L10n.text("settings.tab_devices")
        case .transfers: return L10n.text("settings.tab_transfers")
        case .text: return L10n.text("settings.tab_text")
        case .about: return L10n.text("settings.tab_about")
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .devices: return "desktopcomputer"
        case .transfers: return "arrow.up.arrow.down"
        case .text: return "text.alignleft"
        case .about: return "info.circle"
        }
    }
    var identifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier("settings." + rawValue) }
}

final class SettingsController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    var onSave: ((String) -> Void)?
    var onSelect: ((String) -> Void)?
    var onPair: (() -> Void)?
    var onConnect: ((String) -> Void)?
    var onForget: ((String) -> Void)?
    var onFolder: (() -> Void)?
    var onSend: (() -> Void)?
    var onCancel: (() -> Void)?
    var onReveal: (() -> Void)?
    var onManual: (() -> Void)?
    var onPermissions: (() -> Void)?
    var onTextHistoryVisibility: ((Bool) -> Void)?
    var onTextRetention: ((TextRetention) -> Void)?
    var onTextHistory: (() -> Void)?
    var onClearTextHistory: (() -> Void)?
    var onSendText: (() -> Void)?
    var onUpdates: (() -> Void)?
    var onLanguage: ((DisplayLanguage) -> Void)?
    var onMenuBar: ((Bool) -> Void)?
    var onDock: ((Bool) -> Void)?
    var onHideTemporary: (() -> Void)?
    var onLatestText: (() -> Void)?
    var onAnimations: ((Bool) -> Void)?
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
    private let menuBarSwitch = NSSwitch()
    private let dockSwitch = NSSwitch()
    private let temporaryRow = NSStackView()
    private let connectionGroup = NSStackView()
    private let statusDetails = NSButton()
    private let latestTextButton = NSButton()
    private let animations = NSSwitch()
    private let login = NSSwitch()
    private let autoOpen = NSSwitch()
    private let historyOpen = NSButton()
    private let showHistory = NSSwitch()
    private let retention = NSPopUpButton()
    private var peers: [DiscoveredPeer] = []
    private let pageHost = NSView()
    private var pages: [SettingsSection: NSScrollView] = [:]
    private let maintenance = NSStackView()
    private(set) var selectedSection: SettingsSection = .general

    init(configuration: Configuration, displayLanguage: DisplayLanguage = LanguagePreferences().selection) {
        let height = min(580, max(440, (NSScreen.main?.visibleFrame.height ?? 900) - 130))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: height), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.text("settings.window_title"); window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        super.init(window: window)
        window.delegate = self; window.contentMinSize = NSSize(width:640,height:440)

        let toolbar = NSToolbar(identifier: "PeerJetty.Settings")
        toolbar.delegate = self; toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false; toolbar.autosavesConfiguration = false
        window.toolbar = toolbar

        language.addItems(withTitles: [L10n.text("settings.language_system"), L10n.text("settings.language_english"), L10n.text("settings.language_chinese")])
        language.selectItem(at: DisplayLanguage.allCases.firstIndex(of: displayLanguage) ?? 0)
        language.identifier = NSUserInterfaceItemIdentifier("displayLanguage")
        language.target = self; language.action = #selector(changeLanguage)
        name.stringValue = configuration.name; name.identifier = NSUserInterfaceItemIdentifier("deviceName")
        name.placeholderString = L10n.text("settings.device_name"); name.setAccessibilityLabel(L10n.text("settings.device_name"))
        folderLabel.stringValue = configuration.receivePath; folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        folderLabel.maximumNumberOfLines = 2; folderLabel.toolTip = configuration.receivePath
        devices.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        devices.identifier = NSUserInterfaceItemIdentifier("devicePicker"); devices.setAccessibilityLabel(SettingsSection.devices.title)
        devices.target = self; devices.action = #selector(selectPeer)
        connectionLabel.stringValue = L10n.text("settings.connection_not_ready")
        connectionLabel.identifier = NSUserInterfaceItemIdentifier("connectionInfo")
        menuBarSwitch.state = .on; menuBarSwitch.identifier = NSUserInterfaceItemIdentifier("menuBarVisibility")
        menuBarSwitch.target = self; menuBarSwitch.action = #selector(toggleMenuBar)
        dockSwitch.identifier = NSUserInterfaceItemIdentifier("dockVisibility")
        dockSwitch.target = self; dockSwitch.action = #selector(toggleDock)
        temporaryRow.identifier = NSUserInterfaceItemIdentifier("temporaryIconNotice")
        temporaryRow.orientation = .vertical; temporaryRow.alignment = .leading
        temporaryRow.addArrangedSubview(hint("settings.temporary_menu"))
        let hideTemporaryButton = button(L10n.text("settings.hide_temporary"), #selector(hideTemporary))
        hideTemporaryButton.identifier = NSUserInterfaceItemIdentifier("hideTemporaryIcon")
        temporaryRow.addArrangedSubview(hideTemporaryButton)
        temporaryRow.isHidden = true
        latestTextButton.title = L10n.text("text.latest"); latestTextButton.bezelStyle = .rounded
        latestTextButton.target = self; latestTextButton.action = #selector(openLatestText)
        latestTextButton.identifier = NSUserInterfaceItemIdentifier("latestTextEntry"); latestTextButton.isEnabled = false
        connectionLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        connectionLabel.textColor = .secondaryLabelColor
        animations.state = configuration.animationsEnabled ? .on : .off
        animations.identifier = NSUserInterfaceItemIdentifier("interfaceAnimations")
        animations.target = self; animations.action = #selector(toggleAnimations)
        login.target = self; login.action = #selector(toggleLogin)
        autoOpen.target = self; autoOpen.action = #selector(toggleAutoOpen)
        autoOpen.state = configuration.autoOpenReceivedFiles ? .on : .off
        historyOpen.title = L10n.text("text.history_title"); historyOpen.target = self; historyOpen.action = #selector(openTextHistory); historyOpen.bezelStyle = .rounded
        historyOpen.identifier = NSUserInterfaceItemIdentifier("textHistoryEntry")
        showHistory.identifier = NSUserInterfaceItemIdentifier("textHistoryVisibility")
        retention.identifier = NSUserInterfaceItemIdentifier("textRetention")
        historyOpen.isHidden = !configuration.showTextHistory
        showHistory.state = configuration.showTextHistory ? .on : .off
        showHistory.target = self; showHistory.action = #selector(toggleTextHistory)
        retention.addItems(withTitles: [L10n.text("text.keep500"), L10n.text("text.keep30"), L10n.text("text.keep_forever")])
        retention.selectItem(at: TextRetention.allCases.firstIndex(of: configuration.textRetention) ?? 0)
        retention.target = self; retention.action = #selector(changeRetention)

        var general: [NSView] = []
        if !configuration.onboardingComplete {
            general += [group("settings.welcome_to_peerjetty", rows:[hint("settings.install_peerjetty_on_both_macs_and_pair_them")])]
        }
        name.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        general += [group("settings.group_identity", rows: [
            setting("settings.device_name", row([name, button(L10n.text(configuration.onboardingComplete ? "settings.save_name" : "settings.save_finish_setup"), #selector(save))]))]),
            group("settings.language", rows: [setting("settings.language", language), hint("settings.language_restart")]),
            group("settings.group_presence", rows: [setting("settings.menu_bar", menuBarSwitch), setting("settings.dock_icon", dockSwitch),
                hint("settings.menu_bar_hint"), temporaryRow, setting("settings.start_at_login", login)]),
            group("settings.group_motion", rows: [setting("settings.animations", animations), hint("settings.animations_hint")])]
        connectionGroup.orientation = .vertical; connectionGroup.alignment = .leading; connectionGroup.isHidden = true
        connectionGroup.identifier = NSUserInterfaceItemIdentifier("connectionInfoGroup")
        connectionGroup.addArrangedSubview(connectionLabel)
        connectionLabel.widthAnchor.constraint(equalTo:connectionGroup.widthAnchor).isActive = true
        let connectionDisclosure = button(L10n.text("settings.connection_disclosure"), #selector(toggleConnectionInfo))
        connectionDisclosure.identifier = NSUserInterfaceItemIdentifier("connectionInfoToggle")
        connectionDisclosure.isBordered = false; connectionDisclosure.setButtonType(.pushOnPushOff)
        connectionDisclosure.image = NSImage(systemSymbolName:"chevron.right",accessibilityDescription:nil); connectionDisclosure.imagePosition = .imageLeading
        let deviceRows: [NSView] = [group("settings.tab_devices", rows: [hint("settings.devices_select_a_paired_device_as_your_default"),
            row([devices, button(L10n.text("settings.connect_pair"), #selector(connect))]),
            actions([button(L10n.text("settings.add_device_min"), #selector(pair)), button(L10n.text("settings.manual_address"), #selector(manual))])]),
            group("settings.group_trust", rows: [actions([button(L10n.text("settings.remove_trust"), #selector(forget))])]),
            group("settings.group_manual", rows: [actions([connectionDisclosure]), connectionGroup])]
        let transferRows: [NSView] = [group("settings.receive_folder", rows: [
            row([folderLabel, button(L10n.text("settings.choose_folder"), #selector(chooseFolder))]),
            setting("settings.open_after_receiving", autoOpen), hint("settings.when_enabled_saved_files_from_paired_devices_open")]),
            group("settings.drop_heading", rows: [actions([button(L10n.text("settings.choose_files_to_send"), #selector(send))])]),
            group("settings.activity_heading", rows: [progressLabel,
                actions([button(L10n.text("settings.cancel_transfer"), #selector(cancel)), button(L10n.text("settings.show_recent_files_in_finder"), #selector(reveal))])])]
        let textRows: [NSView] = [group("settings.group_text_send", rows: [actions([button(L10n.text("text.send_title"), #selector(sendText)), latestTextButton])]),
            group("settings.group_text_history", rows: [setting("text.show_history", showHistory), hint("text.history_setting_hint"),
                actions([historyOpen]), setting("text.retention", retention)]),
            group("settings.group_history_cleanup", rows: [actions([button(L10n.text("text.clear"), #selector(clearTextHistory))])])]

        let version = NSTextField(labelWithString: AppVersion.summary)
        version.textColor = .secondaryLabelColor; version.identifier = NSUserInterfaceItemIdentifier("productVersion")
        let appIcon = NSImageView()
        appIcon.image = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) } ?? NSImage(named: NSImage.applicationIconName)
        appIcon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let brand = heading("PeerJetty"); brand.font = .systemFont(ofSize:20,weight:.semibold)
        let branding = NSStackView(views: [brand, version])
        branding.orientation = .vertical; branding.alignment = .leading; branding.spacing = 6
        maintenance.orientation = .vertical; maintenance.alignment = .leading; maintenance.spacing = 12
        maintenance.detachesHiddenViews = true; maintenance.isHidden = true
        maintenance.identifier = NSUserInterfaceItemIdentifier("settingsMaintenance")
        for item in [actions([button(L10n.text("settings.local_network_access"), #selector(permissions))]),
                     actions([button(L10n.text("settings.reset_identity"), #selector(reset))])] {
            maintenance.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: maintenance.widthAnchor).isActive = true
        }
        let disclosure = button(L10n.text("settings.maintenance"), #selector(toggleMaintenance))
        disclosure.identifier = NSUserInterfaceItemIdentifier("settingsMaintenanceToggle")
        disclosure.isBordered = false; disclosure.setButtonType(.pushOnPushOff)
        disclosure.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil); disclosure.imagePosition = .imageLeading
        let aboutRows: [NSView] = [actions([row([appIcon, branding])]), hint("settings.about_hint"),
            actions([button(L10n.text("updates.title"), #selector(checkUpdates)), button(L10n.text("settings.license"), #selector(showLicense)), button(L10n.text("settings.diagnostics"), #selector(showDiagnostics))]),
            group("settings.maintenance", rows: [actions([disclosure]), maintenance]), actions([button(L10n.text("settings.quit"), #selector(quit))])]

        for control in [name, devices, language, folderLabel, progressLabel, connectionLabel, version, latestTextButton, historyOpen, retention] as [NSControl] {
            control.font = .systemFont(ofSize:13)
        }
        let content = window.contentView!
        content.addSubview(pageHost); pageHost.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor; statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.maximumNumberOfLines = 3; statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.identifier = NSUserInterfaceItemIdentifier("settingsStatus")
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for:.horizontal)
        statusDetails.title = L10n.text("settings.status_details"); statusDetails.bezelStyle = .rounded
        statusDetails.target = self; statusDetails.action = #selector(showStatusDetails); statusDetails.isHidden = true
        statusDetails.identifier = NSUserInterfaceItemIdentifier("settingsStatusDetails")
        let footer = row([statusLabel,statusDetails]); footer.detachesHiddenViews = true; footer.translatesAutoresizingMaskIntoConstraints = false
        let footerLine = separator(); footerLine.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footerLine); content.addSubview(footer)
        NSLayoutConstraint.activate([
            pageHost.leadingAnchor.constraint(equalTo: content.leadingAnchor), pageHost.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pageHost.topAnchor.constraint(equalTo: content.topAnchor), pageHost.bottomAnchor.constraint(equalTo: footerLine.topAnchor),
            footerLine.leadingAnchor.constraint(equalTo: content.leadingAnchor), footerLine.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32), footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            footer.topAnchor.constraint(equalTo: footerLine.bottomAnchor, constant: 10), footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)])
        for (section, rows) in [(SettingsSection.general, general), (.devices, deviceRows), (.transfers, transferRows), (.text, textRows), (.about, aboutRows)] {
            addPage(section, rows: rows)
        }
        window.setContentSize(NSSize(width: 720, height: height))
        selectSection(.general); window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func selectSection(_ section: SettingsSection) {
        window?.makeFirstResponder(nil)
        selectedSection = section
        for (key, page) in pages { page.isHidden = key != section }
        window?.toolbar?.selectedItemIdentifier = section.identifier
        (window?.contentView?.superview ?? window?.contentView)?.layoutSubtreeIfNeeded()
        if let page = pages[section] {
            page.contentView.scroll(to: .zero)
            page.reflectScrolledClipView(page.contentView)
        }
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { SettingsSection.allCases.map { $0.identifier } }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let section = SettingsSection.allCases.first(where: { $0.identifier == identifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = section.title; item.paletteLabel = section.title; item.toolTip = section.title
        item.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title)
        item.target = self; item.action = #selector(selectToolbarItem)
        return item
    }
    @objc private func selectToolbarItem(_ sender: NSToolbarItem) {
        if let section = SettingsSection.allCases.first(where: { $0.identifier == sender.itemIdentifier }) { selectSection(section) }
    }
    @objc private func toggleMaintenance(_ sender: NSButton) {
        maintenance.isHidden = sender.state != .on
        sender.image = NSImage(systemSymbolName: sender.state == .on ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
    }
    @objc private func showLicense() {
        let alert = NSAlert(); alert.messageText = L10n.text("settings.license")
        alert.informativeText = (Bundle.main.url(forResource: "LICENSE", withExtension: nil).flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? L10n.text("settings.license_hint")
        if let window { alert.beginSheetModal(for: window) }
    }
    private func addPage(_ section: SettingsSection, rows: [NSView]) {
        let scroll = NSScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.identifier = NSUserInterfaceItemIdentifier("settingsPage." + section.rawValue)
        let document = SettingsDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: rows); stack.orientation = .vertical; stack.alignment = .leading
        stack.spacing = 28; stack.detachesHiddenViews = true; stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.required, for: .vertical)
        scroll.documentView = document; document.addSubview(stack); pageHost.addSubview(scroll); pages[section] = scroll
        let height = document.heightAnchor.constraint(equalTo: stack.heightAnchor, constant: 56); height.priority = .fittingSizeCompression
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: pageHost.topAnchor), scroll.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor), height,
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 32), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 28), stack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -28)])
        for view in rows { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        for view in rows.dropLast() {
            let line = separator(); stack.insertArrangedSubview(line, at: stack.arrangedSubviews.firstIndex(of:view)! + 1)
            stack.setCustomSpacing(14,after:view); stack.setCustomSpacing(14,after:line)
        }
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true }
    }
    /// Native groups, without another background/card layer. Hidden disclosures collapse.
    private func group(_ key: String, rows: [NSView]) -> NSStackView {
        let group = NSStackView(views: [heading(L10n.text(key))] + rows)
        group.identifier = NSUserInterfaceItemIdentifier("settingsGroup." + key)
        group.orientation = .vertical; group.alignment = .leading; group.spacing = 16
        group.detachesHiddenViews = true; group.setHuggingPriority(.required, for: .vertical)
        for (index, view) in group.arrangedSubviews.enumerated() {
            view.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
            if index > 0, let label = view as? NSTextField, label.textColor == .secondaryLabelColor {
                group.setCustomSpacing(6, after: group.arrangedSubviews[index-1])
            }
        }
        return group
    }
    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: 13, weight: .semibold); return label
    }
    private func hint(_ key: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: L10n.text(key)); label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13); label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal); return label
    }
    private func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views); row.orientation = .horizontal; row.spacing = 10; row.alignment = .centerY
        row.setHuggingPriority(.required, for: .vertical); return row
    }
    private func spacer() -> NSView {
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true; return spacer
    }
    private func actions(_ views: [NSView]) -> NSStackView { row(views + [spacer()]) }
    private func setting(_ key: String, _ control: NSView) -> NSStackView {
        control.setAccessibilityLabel(L10n.text(key))
        let label = NSTextField(wrappingLabelWithString: L10n.text(key)); label.font = .systemFont(ofSize: 13)
        label.widthAnchor.constraint(equalToConstant: 172).isActive = true
        if control is NSSwitch { return row([label, spacer(), control]) }
        control.widthAnchor.constraint(greaterThanOrEqualToConstant:240).isActive = true
        return row([label, control, spacer()])
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded; button.font = .systemFont(ofSize:13)
        button.setContentCompressionResistancePriority(.required, for: .horizontal); return button
    }
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
    func status(_ text: String) {
        statusLabel.stringValue = text; statusLabel.toolTip = text
        let available = max(100, (window?.contentView?.bounds.width ?? 720) - 64 - statusDetails.intrinsicContentSize.width - 10)
        let font = statusLabel.font ?? .systemFont(ofSize:13)
        let measured = (text as NSString).boundingRect(with:NSSize(width:available,height:100000), options:[.usesLineFragmentOrigin,.usesFontLeading], attributes:[.font:font]).height
        let lineHeight = NSLayoutManager().defaultLineHeight(for:font)
        statusDetails.isHidden = measured <= lineHeight * 3 + 1 && text.components(separatedBy:"\n").count <= 3
    }
    func windowDidResize(_ notification: Notification) { status(statusLabel.stringValue) }
    func latestTextState(_ available:Bool) { latestTextButton.isEnabled = available }
    func iconState(menu:Bool, dock:Bool, temporary:Bool) {
        menuBarSwitch.state = menu ? .on : .off; dockSwitch.state = dock ? .on : .off
        temporaryRow.isHidden = !temporary
    }
    @objc private func toggleDock() { onDock?(dockSwitch.state == .on) }
    @objc private func hideTemporary() { onHideTemporary?() }
    @objc private func toggleMenuBar() { onMenuBar?(menuBarSwitch.state == .on) }
    @objc private func openLatestText() { onLatestText?() }
    @objc private func toggleConnectionInfo(_ sender:NSButton) {
        connectionGroup.isHidden = sender.state != .on
        sender.image = NSImage(systemSymbolName:sender.state == .on ? "chevron.down" : "chevron.right",accessibilityDescription:nil)
    }
    @objc private func showStatusDetails() { showDetails(title:L10n.text("settings.status_details"),text:statusLabel.stringValue) }
    @objc private func showDiagnostics() { showDetails(title:L10n.text("settings.diagnostics"),text:AppVersion.details) }
    private func showDetails(title:String,text:String) {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = title; alert.addButton(withTitle:L10n.text("application.ok"))
        alert.accessoryView = Self.detailContent(text)
        alert.beginSheetModal(for:window)
    }
    static func detailContent(_ text:String) -> NSScrollView {
        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:480,height:220)); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
        let body = NSTextView(frame:scroll.bounds); body.isEditable = false; body.isSelectable = true; body.isRichText = false
        body.font = .systemFont(ofSize:13); body.textContainerInset = NSSize(width:10,height:10)
        body.minSize = NSSize(width:0,height:220); body.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        body.isVerticallyResizable = true; body.isHorizontallyResizable = false; body.autoresizingMask = [.width]
        body.textContainer?.widthTracksTextView = true; body.textContainer?.containerSize = NSSize(width:480,height:CGFloat.greatestFiniteMagnitude)
        body.isAutomaticLinkDetectionEnabled = false; body.isAutomaticDataDetectionEnabled = false
        body.string = text; scroll.documentView = body; return scroll
    }
    func folder(_ path: String) { folderLabel.stringValue = path; folderLabel.toolTip = path }
    func connectionInfo(_ text: String) { connectionLabel.stringValue = text }
    func loginState(_ enabled: Bool) { login.state = enabled ? .on : .off }
    func autoOpenState(_ enabled: Bool) { autoOpen.state = enabled ? .on : .off }
    func progress(_ update: TransferUpdate) {
        let percent = update.total > 0 ? Int(Double(update.completed) / Double(update.total) * 100) : 0
        let key = update.receiving ? "settings.receiving_progress" : "settings.sending_progress"
        let detail = L10n.text(key, update.peerName, update.status)
        progressLabel.stringValue = update.finished ? detail : L10n.text("settings.progress_percent", detail, L10n.percent(percent))
    }
    func animationState(_ enabled: Bool) { animations.state = enabled ? .on : .off }

    @objc private func toggleAnimations() { onAnimations?(animations.state == .on) }
    @objc private func save() { onSave?(name.stringValue) }
    @objc private func selectPeer() { if let selected, selected.paired { onSelect?(selected.id) } }
    @objc private func connect() { if let selected { onConnect?(selected.id) } }
    @objc private func pair() { onPair?() }
    @objc private func forget() { if let selected, selected.paired { onForget?(selected.id) } }
    @objc private func chooseFolder() { onFolder?() }
    @objc private func send() { onSend?() }

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
    func textHistoryState(_ visible:Bool, retention value:TextRetention) {
        historyOpen.isHidden = !visible
        showHistory.state = visible ? .on : .off; retention.selectItem(at:TextRetention.allCases.firstIndex(of:value) ?? 0)
    }
    @objc private func toggleTextHistory() { onTextHistoryVisibility?(showHistory.state == .on) }
    @objc private func changeRetention() { if TextRetention.allCases.indices.contains(retention.indexOfSelectedItem) { onTextRetention?(TextRetention.allCases[retention.indexOfSelectedItem]) } }
    @objc private func openTextHistory() { onTextHistory?() }
    @objc private func clearTextHistory() { onClearTextHistory?() }
    @objc private func sendText() { onSendText?() }
    @objc private func checkUpdates() { onUpdates?() }
    @objc private func reset() { onReset?() }
    @objc private func quit() { onQuit?() }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
