import AppKit
import PeerCore
import UserNotifications

/// Share the card's top/center while reserving the native title bar and small-screen margins.
struct TextPanelPlacement {
    let contentSize: NSSize
    let frame: NSRect
    init(_ screen:DropScreenMetrics, decoration:CGFloat) {
        let area = screen.visibleFrame; let card = DropPresentation(screen).card
        let width = min(560,max(1,area.width-24)); let top = min(card.maxY,area.maxY-12)
        let height = min(350,max(1,top-area.minY-12-decoration))
        contentSize = NSSize(width:width,height:height)
        let x = min(max(area.minX+12,card.midX-width/2),area.maxX-width-12)
        frame = NSRect(x:x,y:top-height-decoration,width:width,height:height+decoration)
    }
}

private final class TextPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
final class ComposerTextView: NSTextView {
    var sendCommand: (() -> Void)?
    var closeCommand: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), event.modifierFlags.contains(.command), event.keyCode == 36 { sendCommand?(); return }
        if !hasMarkedText(), event.keyCode == 53 { closeCommand?(); return }
        super.keyDown(with: event)
    }
}
func plainTextScroll(_ text: NSTextView, frame: NSRect) -> NSScrollView {
    let scroll = NSScrollView(frame: frame); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
    text.isRichText = false; text.importsGraphics = false; text.isAutomaticLinkDetectionEnabled = false
    text.isAutomaticDataDetectionEnabled = false; text.isAutomaticTextReplacementEnabled = false
    text.isAutomaticSpellingCorrectionEnabled = false; text.smartInsertDeleteEnabled = false
    text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false
    text.font = .monospacedSystemFont(ofSize: 13, weight: .regular); text.textContainerInset = NSSize(width: 10,height: 10)
    text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
    text.frame = scroll.bounds; text.textContainer?.widthTracksTextView = true; scroll.documentView = text
    return scroll
}
final class TextComposer: NSWindowController, NSWindowDelegate {
    var onSend: ((String, String) -> UUID?)?
    var onConnect: ((String) -> Void)?
    var onVisibility: ((NSScreen?) -> Void)?
    let editor = ComposerTextView()
    private let targets = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let sendButton = NSButton()
    private var peers: [DiscoveredPeer] = []
    private var pending: UUID?
    private var submitted = ""
    var selectedPeer: DiscoveredPeer? { peers.indices.contains(targets.indexOfSelectedItem) ? peers[targets.indexOfSelectedItem] : nil }
    init() {
        let panel = TextPanel(contentRect: NSRect(x:0,y:0,width:560,height:350), styleMask:[.titled,.closable], backing:.buffered,defer:false)
        panel.title = L10n.text("text.send_title"); panel.isReleasedWhenClosed = false; panel.isRestorable = false
        panel.level = .floating; panel.collectionBehavior = [.moveToActiveSpace,.fullScreenAuxiliary]
        super.init(window:panel); panel.delegate = self
        targets.frame = NSRect(x:20,y:300,width:370,height:30)
        targets.target = self; targets.action = #selector(connectTarget)
        let connect = NSButton(title:L10n.text("text.connect"),target:self,action:#selector(connectTarget))
        connect.frame = NSRect(x:400,y:300,width:140,height:30); connect.bezelStyle = .rounded
        let scroll = plainTextScroll(editor,frame:NSRect(x:20,y:110,width:520,height:180))
        status.frame = NSRect(x:20,y:65,width:520,height:40)
        status.font = .systemFont(ofSize:11); status.textColor = .secondaryLabelColor
        status.stringValue = L10n.text("text.record_hint")
        let close = NSButton(title:L10n.text("text.close"),target:self,action:#selector(closePanel))
        close.frame = NSRect(x:20,y:20,width:150,height:32); close.bezelStyle = .rounded
        sendButton.title = L10n.text("text.send_button"); sendButton.target = self; sendButton.action = #selector(sendText)
        sendButton.frame = NSRect(x:340,y:20,width:200,height:32); sendButton.bezelStyle = .rounded
        editor.sendCommand = { [weak self] in self?.sendText() }; editor.closeCommand = { [weak self] in self?.closePanel() }
        targets.autoresizingMask = [.width,.minYMargin]; connect.autoresizingMask = [.minXMargin,.minYMargin]
        scroll.autoresizingMask = [.width,.height]; status.autoresizingMask = [.width]
        sendButton.autoresizingMask = [.minXMargin]
        [targets,connect,scroll,status,close,sendButton].forEach { panel.contentView?.addSubview($0) }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }
    func updatePeers(_ value:[DiscoveredPeer], preferred:String?) {
        let selected = selectedPeer?.id ?? preferred
        peers = value.filter(\.paired); targets.removeAllItems()
        for peer in peers {
            let state = !peer.connected ? L10n.text("text.offline_short") : peer.supportsText == false ? L10n.text("text.old_peer") : L10n.text("text.online")
            targets.addItem(withTitle:L10n.text("text.target",peer.name,state))
        }
        if peers.isEmpty { targets.addItem(withTitle:L10n.text("text.no_target")) }
        if let index = peers.firstIndex(where: { $0.id == selected }) { targets.selectItem(at:index) }
    }
    func historyFailure() { status.stringValue = L10n.text("text.history_failed") }
    func present() {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let decoration = max(0,(window?.frame.height ?? 0)-(window?.contentView?.bounds.height ?? 0))
            let placement = TextPanelPlacement(DropScreenMetrics(screen),decoration:decoration)
            window?.setContentSize(placement.contentSize); window?.setFrameOrigin(placement.frame.origin)
            onVisibility?(screen)
        }
        showWindow(nil); NSApp.activate(ignoringOtherApps:true); window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(editor)
    }
    @objc private func closePanel() { window?.close() }
    func windowWillClose(_ notification:Notification) { onVisibility?(nil) }
    func windowDidMove(_ notification:Notification) { if window?.isVisible == true { onVisibility?(window?.screen) } }
    @objc private func connectTarget() {
        guard pending == nil, let peer = selectedPeer, peer.connected else { status.stringValue = L10n.text("text.offline"); return }
        if peer.supportsText == nil { status.stringValue = L10n.text("text.connecting"); onConnect?(peer.id) }
        else { status.stringValue = peer.supportsText == true ? L10n.text("text.record_hint") : L10n.text("text.upgrade") }
    }
    @objc func sendText() {
        guard pending == nil else { return }
        do {
            try TextRules.validate(editor.string)
            guard let peer = selectedPeer else { throw PeerError.localized("text.no_target",[]) }
            guard peer.connected else { throw PeerError.localized("text.offline",[]) }
            if peer.supportsText == nil { connectTarget(); return }
            guard peer.supportsText == true else { throw PeerError.localized("text.upgrade",[]) }
            submitted = editor.string
            if let id = onSend?(submitted,peer.id) {
                pending = id; editor.isEditable = false; targets.isEnabled = false; sendButton.isEnabled = false
                status.stringValue = L10n.text("text.waiting")
            }
        } catch { status.stringValue = error.localizedDescription }
    }
    func result(_ id:UUID, error:Error?) {
        guard id == pending else { return }; pending = nil
        editor.isEditable = true; targets.isEnabled = true; sendButton.isEnabled = true
        if let error { status.stringValue = error.localizedDescription }
        else { if editor.string == submitted { editor.string = "" }; status.stringValue = L10n.text("text.confirmed") }
    }
}
final class TextReader: NSWindowController {
    private let text = NSTextView()
    private let pasteboard: NSPasteboard
    init(entry:TextEntry, saved:Bool = true, pasteboard:NSPasteboard = .general) {
        self.pasteboard = pasteboard
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:400),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.contentMinSize = NSSize(width:360,height:200)
        window.title = L10n.text("text.reader_title",entry.peerName); window.isReleasedWhenClosed = false; window.isRestorable = false; window.center()
        super.init(window:window)
        text.isEditable = false; text.string = entry.text
        let scroll = plainTextScroll(text,frame:NSRect(x:20,y:saved ? 70:110,width:540,height:saved ? 310:270)); scroll.autoresizingMask = [.width,.height]
        let copy = NSButton(title:L10n.text("text.copy"),target:self,action:#selector(copyText)); copy.bezelStyle = .rounded
        copy.frame = NSRect(x:20,y:20,width:180,height:32)
        if !saved {
            let warning = NSTextField(wrappingLabelWithString:L10n.text("text.history_failed"))
            warning.frame = NSRect(x:20,y:65,width:540,height:40); warning.font = .systemFont(ofSize:11); warning.textColor = .systemOrange
            warning.autoresizingMask = [.width]; window.contentView?.addSubview(warning)
        }
        window.contentView?.addSubview(scroll); window.contentView?.addSubview(copy)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }
    @objc private func copyText() { pasteboard.clearContents(); pasteboard.setString(text.string,forType:.string) }
    func present() { showWindow(nil); NSApp.activate(ignoringOtherApps:true); window?.makeKeyAndOrderFront(nil) }
}
final class TextHistoryWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onLoad: ((Int) -> Void)?
    var onOpen: ((UUID) -> Void)?
    var onDelete: ((UUID?) -> Void)?
    private var entries:[TextEntry] = []
    private var offset = 0
    private let table = NSTableView()
    private let info = NSTextField(wrappingLabelWithString: "")
    init() {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:650,height:450),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title = L10n.text("text.history_title"); window.isReleasedWhenClosed = false; window.isRestorable = false; window.center()
        super.init(window:window)
        let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("entry")); column.width = 600; table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 54; table.delegate = self; table.dataSource = self
        table.target = self; table.doubleAction = #selector(openSelected)
        let scroll = NSScrollView(frame:NSRect(x:20,y:100,width:610,height:325)); scroll.hasVerticalScroller = true; scroll.documentView = table
        table.frame = scroll.bounds; table.autoresizingMask = [.width]
        info.frame = NSRect(x:20,y:60,width:610,height:35)
        let actions:[(String,Selector,CGFloat,CGFloat)] = [("text.view",#selector(openSelected),20,100),("text.delete",#selector(deleteSelected),130,100),("text.clear",#selector(clearAll),240,120),("text.previous",#selector(previous),370,120),("text.next",#selector(next),500,130)]
        window.contentView?.addSubview(scroll); window.contentView?.addSubview(info)
        for (key,selector,x,width) in actions { let button = NSButton(title:L10n.text(key),target:self,action:selector); button.bezelStyle = .rounded; button.frame = NSRect(x:x,y:15,width:width,height:32); window.contentView?.addSubview(button) }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }
    func present() { offset = 0; reload(); showWindow(nil); NSApp.activate(ignoringOtherApps:true); window?.makeKeyAndOrderFront(nil) }
    func reload() { onLoad?(offset) }
    func update(_ rows:[TextEntry], error:Error? = nil) {
        let selected = entries.indices.contains(table.selectedRow) ? entries[table.selectedRow].id : nil
        entries = rows; table.reloadData()
        if let selected, let index = entries.firstIndex(where: {$0.id == selected}) { table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false) }
        else { table.deselectAll(nil) }
        info.stringValue = error?.localizedDescription ?? (rows.isEmpty ? L10n.text("text.history_empty") : L10n.text("text.history_hint"))
    }
    func numberOfRows(in tableView:NSTableView) -> Int { entries.count }
    func tableView(_ tableView:NSTableView, viewFor tableColumn:NSTableColumn?, row:Int) -> NSView? {
        let entry = entries[row]; let date = DateFormatter(); date.locale = Locale(identifier:L10n.language); date.dateStyle = .short; date.timeStyle = .short
        let direction = L10n.text(entry.direction == .sent ? "text.sent" : "text.received")
        let label = NSTextField(wrappingLabelWithString:L10n.text("text.history_row",direction,entry.peerName,date.string(from:entry.date),String(entry.text.prefix(120)).components(separatedBy:.newlines).joined(separator:" ")))
        label.maximumNumberOfLines = 2; label.lineBreakMode = .byTruncatingTail; return label
    }
    @objc private func openSelected() { if entries.indices.contains(table.selectedRow) { onOpen?(entries[table.selectedRow].id) } }
    @objc private func deleteSelected() { if entries.indices.contains(table.selectedRow) { onDelete?(entries[table.selectedRow].id) } }
    @objc private func clearAll() { onDelete?(nil) }
    @objc private func previous() { offset = max(0,offset-100); reload() }
    @objc private func next() { if entries.count == 100 { offset += 100; reload() } }
}

/// Notifications expose only the sending device, never the message body.
func textNotificationContent(id: UUID, peerName: String, saved: Bool) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = L10n.text(saved ? "text.notification" : "text.notification_unsaved")
    content.body = L10n.text("text.notification_body",peerName); content.sound = .default
    content.userInfo = ["textEntry":id.uuidString]; return content
}
