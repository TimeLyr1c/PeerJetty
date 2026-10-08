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
    lazy var motion = WindowMotion(self)
    override var canBecomeKey: Bool { true }
    override func close() { motion.dismiss { [weak self] in self?.closeNow() } }
    private func closeNow() { super.close() }
}
private final class TextReaderWindow: NSWindow {
    lazy var motion = WindowMotion(self)
    override func close() { motion.dismiss { [weak self] in self?.closeNow() } }
    private func closeNow() { super.close() }
}
/// Menu-bar apps have no standard Edit menu to dispatch these key equivalents.
/// Delegate to native text actions only after an explicit user shortcut.
class PlainTextView: NSTextView {
    var placeholder: String? { didSet { needsDisplay = true } }
    override var string: String { didSet { needsDisplay = true } }
    override func didChangeText() { super.didChangeText(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, !hasMarkedText(), let placeholder {
            let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.placeholderTextColor]
            (placeholder as NSString).draw(in: NSRect(x: textContainerInset.width, y: textContainerInset.height, width: max(0, bounds.width - 2 * textContainerInset.width), height: 24), withAttributes: attributes)
        }
    }
    private func editShortcut(_ event:NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control) else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a": selectAll(nil)
        case "c": copy(nil)
        case "x": if isEditable { cut(nil) }
        case "v": if isEditable { pasteAsPlainText(nil) }
        case "z":
            if isEditable {
                if event.modifierFlags.contains(.shift) { if undoManager?.canRedo == true { undoManager?.redo() } }
                else if undoManager?.canUndo == true { undoManager?.undo() }
            }
        default: return false
        }
        return true
    }
    override func performKeyEquivalent(with event:NSEvent) -> Bool { editShortcut(event) || super.performKeyEquivalent(with:event) }
    override func keyDown(with event:NSEvent) { if !editShortcut(event) { super.keyDown(with:event) } }
}
final class ComposerTextView: PlainTextView {
    var sendCommand: (() -> Void)?
    var closeCommand: (() -> Void)?
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.keyCode == 36 {
            guard !hasMarkedText() else { return false }
            sendCommand?(); return true
        }
        return super.performKeyEquivalent(with:event)
    }
    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), event.modifierFlags.contains(.command), event.keyCode == 36 { sendCommand?(); return }
        if !hasMarkedText(), event.keyCode == 53 { closeCommand?(); return }
        super.keyDown(with: event)
    }
}
func plainTextScroll(_ text: NSTextView, frame: NSRect) -> NSScrollView {
    let scroll = TextSurfaceScroll(frame: frame); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
    scroll.borderType = .noBorder; scroll.drawsBackground = false; scroll.wantsLayer = true
    scroll.layer?.cornerRadius = 8; scroll.layer?.masksToBounds = true; scroll.layer?.borderWidth = 0
    text.allowsUndo = true; text.isRichText = false; text.importsGraphics = false; text.isAutomaticLinkDetectionEnabled = false
    text.isAutomaticDataDetectionEnabled = false; text.isAutomaticTextReplacementEnabled = false
    text.isAutomaticSpellingCorrectionEnabled = false; text.smartInsertDeleteEnabled = false
    text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false
    text.font = .systemFont(ofSize: 14); text.textContainerInset = NSSize(width: 14, height: 14)
    text.textColor = .textColor; text.backgroundColor = .textBackgroundColor
    text.textContainer?.lineFragmentPadding = 0
    text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
    text.frame = scroll.bounds; text.textContainer?.widthTracksTextView = true; scroll.documentView = text
    return scroll
}
/// A drawing overlay keeps the subtle border visible above the scroll view's clip view.
private final class TextSurfaceBorder: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 0.5; border.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
private final class TextSurfaceScroll: NSScrollView {
    private let border = TextSurfaceBorder()
    override init(frame: NSRect) {
        super.init(frame: frame); addSubview(border, positioned: .above, relativeTo: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func layout() {
        super.layout(); border.frame = bounds
        if let text = documentView as? NSTextView {
            text.minSize = NSSize(width: 0, height: contentSize.height)
            if abs(text.frame.width - contentSize.width) > 0.5 { text.setFrameSize(NSSize(width: contentSize.width, height: max(contentSize.height, text.frame.height))) }
        }
    }
}
private enum TextFeedback { case info, waiting, success, error, warning }
private final class TextStatus: NSView {
    let label = NSTextField(wrappingLabelWithString: "")
    private let icon = NSImageView()
    private var labelHeight: NSLayoutConstraint!
    init() {
        super.init(frame: .zero)
        icon.translatesAutoresizingMaskIntoConstraints = false; label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon); addSubview(label)
        label.font = .systemFont(ofSize: 12); label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping; label.cell?.wraps = true; label.cell?.usesSingleLineMode = false
        labelHeight = label.heightAnchor.constraint(equalToConstant: 16); labelHeight.isActive = true
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: leadingAnchor), icon.topAnchor.constraint(equalTo: topAnchor), label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7), label.trailingAnchor.constraint(equalTo: trailingAnchor), label.topAnchor.constraint(equalTo: topAnchor), label.bottomAnchor.constraint(equalTo: bottomAnchor)])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: labelHeight?.constant ?? 16) }
    override func layout() {
        let width = max(1, bounds.width - 23)
        if abs(label.preferredMaxLayoutWidth - width) > 0.5 {
            label.preferredMaxLayoutWidth = width; label.invalidateIntrinsicContentSize()
        }
        let measured = (label.stringValue as NSString).boundingRect(with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: label.font!]).height
        let height = max(16, min(ceil(measured) + 3, 48))
        if abs(labelHeight.constant - height) > 0.5 { labelHeight.constant = height; invalidateIntrinsicContentSize() }
        super.layout()
    }
    func show(_ message: String, _ kind: TextFeedback = .info) {
        let symbol: String, color: NSColor
        switch kind {
        case .info: symbol = "info.circle"; color = .secondaryLabelColor
        case .waiting: symbol = "clock"; color = .secondaryLabelColor
        case .success: symbol = "checkmark.circle.fill"; color = .systemGreen
        case .error: symbol = "exclamationmark.circle.fill"; color = .systemRed
        case .warning: symbol = "exclamationmark.triangle.fill"; color = .systemOrange
        }
        if label.stringValue != message { MotionEffects.transition(label); MotionEffects.transition(icon) }
        label.stringValue = message; label.textColor = kind == .error || kind == .warning ? color : .secondaryLabelColor
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); icon.contentTintColor = color
        if kind == .success { MotionEffects.pulse(icon) } else { icon.layer?.removeAnimation(forKey: "PeerJetty.feedback") }
        label.toolTip = message; needsLayout = true
    }
}
private enum TextLayout {
    static func label(_ text: String, size: CGFloat = 12, secondary: Bool = true) -> NSTextField {
        let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: size)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor; return label
    }
    static func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 10
        row.setHuggingPriority(.required, for: .vertical); return row
    }
    static func spacer() -> NSView {
        let view = NSView(); view.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal); return view
    }
    static func button(_ key: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: L10n.text(key), target: target, action: action); button.bezelStyle = .rounded
        button.setContentCompressionResistancePriority(.required, for: .horizontal); return button
    }
    static func install(_ rows: [NSView], in content: NSView, inset: CGFloat = 20, spacing: CGFloat = 12) {
        let stack = NSStackView(views: rows); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: inset), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -inset)])
        for row in rows { row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }
    static func date(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: L10n.language)
        formatter.dateStyle = .short; formatter.timeStyle = .short; return formatter.string(from: date)
    }
}
final class TextComposer: NSWindowController, NSWindowDelegate {
    var onSend: ((String, String) -> UUID?)?
    var onConnect: ((String) -> Void)?
    var onVisibility: ((NSScreen?) -> Void)?
    let editor = ComposerTextView()
    private let targets = NSPopUpButton()
    private let status = TextStatus()
    private let sendButton = NSButton()
    private let connect = NSButton()
    private var peers: [DiscoveredPeer] = []
    private var pending: UUID?
    private var submitted = ""
    var selectedPeer: DiscoveredPeer? { peers.indices.contains(targets.indexOfSelectedItem) ? peers[targets.indexOfSelectedItem] : nil }
    init() {
        let panel = TextPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 350), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = L10n.text("text.compose_title"); panel.isReleasedWhenClosed = false; panel.isRestorable = false
        panel.level = .floating; panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel); panel.delegate = self
        targets.target = self; targets.action = #selector(connectTarget); targets.cell?.lineBreakMode = .byTruncatingMiddle
        targets.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        targets.setAccessibilityLabel(L10n.text("text.send_to")); targets.identifier = NSUserInterfaceItemIdentifier("textTargets")
        connect.title = L10n.text("text.connect"); connect.target = self; connect.action = #selector(connectTarget); connect.bezelStyle = .rounded
        connect.setContentCompressionResistancePriority(.required, for: .horizontal)
        let heading = TextLayout.row([TextLayout.label(L10n.text("text.send_to"), size: 13, secondary: false), targets, connect])
        editor.placeholder = L10n.text("text.placeholder"); editor.setAccessibilityLabel(L10n.text("text.compose_title"))
        let scroll = plainTextScroll(editor, frame: NSRect(x: 0, y: 0, width: 520, height: 180))
        scroll.identifier = NSUserInterfaceItemIdentifier("textBody")
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        status.identifier = NSUserInterfaceItemIdentifier("textStatus"); status.show(L10n.text("text.local_record_hint"))
        let close = TextLayout.button("text.close_action", target: self, action: #selector(closePanel))
        sendButton.title = L10n.text("text.send_action"); sendButton.target = self; sendButton.action = #selector(sendText)
        sendButton.bezelStyle = .rounded; sendButton.bezelColor = .controlAccentColor
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        let footer = TextLayout.row([close, TextLayout.label("Esc"), TextLayout.spacer(), TextLayout.label("⌘Enter"), sendButton])
        editor.sendCommand = { [weak self] in self?.sendText() }; editor.closeCommand = { [weak self] in self?.closePanel() }
        TextLayout.install([heading, scroll, status, footer], in: panel.contentView!)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    func updatePeers(_ value: [DiscoveredPeer], preferred: String?, resetSelection: Bool = false) {
        let selected = resetSelection && pending == nil && editor.string.isEmpty ? preferred : selectedPeer?.id ?? preferred
        peers = value.filter(\.paired); targets.removeAllItems()
        for peer in peers {
            let state = !peer.connected ? L10n.text("text.offline_short") : peer.supportsText == false ? L10n.text("text.old_peer") : L10n.text("text.online")
            targets.addItem(withTitle: L10n.text("text.target", peer.name, state))
        }
        if peers.isEmpty { targets.addItem(withTitle: L10n.text("text.no_target")) }
        if let index = peers.firstIndex(where: { $0.id == selected }) { targets.selectItem(at: index) }
        targets.toolTip = targets.titleOfSelectedItem
    }
    func historyFailure() { status.show(L10n.text("text.history_failed"), .warning) }
    func present() {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let decoration = max(0, (window?.frame.height ?? 0) - (window?.contentView?.bounds.height ?? 0))
            let placement = TextPanelPlacement(DropScreenMetrics(screen), decoration: decoration)
            window?.setContentSize(placement.contentSize); window?.setFrameOrigin(placement.frame.origin)
            onVisibility?(screen)
        }
        NSApp.activate(ignoringOtherApps: true)
        if let panel = window as? TextPanel { panel.motion.reveal { panel.makeKeyAndOrderFront(nil) }; panel.makeFirstResponder(editor) }
    }
    @objc private func closePanel() { window?.close() }
    func windowWillClose(_ notification: Notification) { onVisibility?(nil) }
    func windowDidMove(_ notification: Notification) { if window?.isVisible == true { onVisibility?(window?.screen) } }
    @objc private func connectTarget() {
        targets.toolTip = targets.titleOfSelectedItem
        guard pending == nil, let peer = selectedPeer, peer.connected else { status.show(L10n.text("text.offline"), .error); return }
        if peer.supportsText == nil { status.show(L10n.text("text.connecting"), .waiting); onConnect?(peer.id) }
        else { status.show(L10n.text(peer.supportsText == true ? "text.local_record_hint" : "text.upgrade"), peer.supportsText == true ? .info : .warning) }
    }
    @objc func sendText() {
        guard pending == nil else { return }
        do {
            try TextRules.validate(editor.string)
            guard let peer = selectedPeer else { throw PeerError.localized("text.no_target", []) }
            guard peer.connected else { throw PeerError.localized("text.offline", []) }
            if peer.supportsText == nil { connectTarget(); return }
            guard peer.supportsText == true else { throw PeerError.localized("text.upgrade", []) }
            submitted = editor.string
            if let id = onSend?(submitted, peer.id) {
                pending = id; editor.isEditable = false; targets.isEnabled = false; sendButton.isEnabled = false; connect.isEnabled = false
                status.show(L10n.text("text.waiting"), .waiting)
            }
        } catch { status.show(error.localizedDescription, .error) }
    }
    func result(_ id: UUID, error: Error?) {
        guard id == pending else { return }; pending = nil
        editor.isEditable = true; targets.isEnabled = true; sendButton.isEnabled = true; connect.isEnabled = true
        if let error { status.show(error.localizedDescription, .error) }
        else { if editor.string == submitted { editor.string = "" }; status.show(L10n.text("text.confirmed"), .success) }
    }
}
final class TextReader: NSWindowController {
    private let text = PlainTextView()
    private let pasteboard: NSPasteboard
    private let copied = NSTextField(labelWithString: "")
    init(entry: TextEntry, saved: Bool = true, pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        let window = TextReaderWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 400), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentMinSize = NSSize(width: 360, height: 200)
        window.title = L10n.text("text.reader_title", entry.peerName); window.isReleasedWhenClosed = false; window.isRestorable = false; window.center()
        super.init(window: window)
        let peer = TextLayout.label(entry.peerName, size: 14, secondary: false); peer.font = .systemFont(ofSize: 14, weight: .semibold)
        peer.lineBreakMode = .byTruncatingMiddle; peer.toolTip = entry.peerName
        peer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detail = TextLayout.label(L10n.text("text.metadata", L10n.text(entry.direction == .sent ? "text.sent" : "text.received"), TextLayout.date(entry.date)))
        let header = NSStackView(views: [peer, detail]); header.orientation = .vertical; header.alignment = .leading; header.spacing = 4
        header.setHuggingPriority(.required, for: .vertical)
        peer.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        text.isEditable = false; text.string = entry.text; text.setAccessibilityLabel(L10n.text("text.reader_title", entry.peerName))
        let scroll = plainTextScroll(text, frame: NSRect(x: 0, y: 0, width: 548, height: 260))
        scroll.identifier = NSUserInterfaceItemIdentifier("textBody"); scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        let copy = TextLayout.button("text.copy", target: self, action: #selector(copyText)); copy.identifier = NSUserInterfaceItemIdentifier("textCopy")
        copied.font = .systemFont(ofSize: 12); copied.textColor = .secondaryLabelColor
        copied.identifier = NSUserInterfaceItemIdentifier("textCopyFeedback")
        let footer = TextLayout.row([copied, TextLayout.spacer(), copy])
        var rows: [NSView] = [header, scroll]
        if !saved { let warning = TextStatus(); warning.show(L10n.text("text.history_failed"), .warning); rows.append(warning) }
        rows.append(footer); TextLayout.install(rows, in: window.contentView!, inset: 16, spacing: 10)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    @objc private func copyText() {
        MotionEffects.transition(copied)
        pasteboard.clearContents()
        if pasteboard.setString(text.string, forType: .string) { copied.stringValue = L10n.text("text.copied") }
        else { copied.stringValue = L10n.text("text.copy_failed") }
    }
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = window as? TextReaderWindow { window.motion.reveal { window.makeKeyAndOrderFront(nil) }; window.makeFirstResponder(text) }
    }
}
private final class TextHistoryCell: NSTableCellView {
    private let direction = NSImageView()
    private let peer = NSTextField(labelWithString: "")
    private let date = NSTextField(labelWithString: "")
    private let preview = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        peer.font = .systemFont(ofSize: 13, weight: .medium); peer.lineBreakMode = .byTruncatingMiddle
        peer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        date.font = .systemFont(ofSize: 12); date.textColor = .secondaryLabelColor
        date.setContentCompressionResistancePriority(.required, for: .horizontal)
        preview.font = .systemFont(ofSize: 13); preview.textColor = .secondaryLabelColor; preview.lineBreakMode = .byTruncatingTail
        direction.widthAnchor.constraint(equalToConstant: 16).isActive = true; direction.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let heading = TextLayout.row([direction, peer, TextLayout.spacer(), date])
        TextLayout.install([heading, preview], in: self, inset: 10, spacing: 5)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    func configure(_ entry: TextEntry) {
        let kind = L10n.text(entry.direction == .sent ? "text.sent" : "text.received")
        direction.image = NSImage(systemSymbolName: entry.direction == .sent ? "arrow.up.right" : "arrow.down.left", accessibilityDescription: kind)
        peer.stringValue = entry.peerName; peer.toolTip = entry.peerName; date.stringValue = TextLayout.date(entry.date)
        preview.stringValue = String(entry.text.prefix(120)).components(separatedBy: .newlines).joined(separator: " ")
        setAccessibilityLabel(L10n.text("text.history_row", kind, entry.peerName, date.stringValue, preview.stringValue))
    }
}
final class TextHistoryWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onLoad: ((Int) -> Void)?
    var onOpen: ((UUID) -> Void)?
    var onDelete: ((UUID?) -> Void)?
    private var entries: [TextEntry] = []
    private var offset = 0
    private let table = NSTableView()
    private let info = TextStatus()
    private let empty = NSStackView()
    private let viewButton = NSButton()
    private let deleteButton = NSButton()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 450), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentMinSize = NSSize(width: 500, height: 350)
        window.title = L10n.text("text.history_heading"); window.isReleasedWhenClosed = false; window.isRestorable = false; window.center()
        super.init(window: window)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry")); column.width = 610; column.minWidth = 0; table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 64; table.intercellSpacing = NSSize(width: 0, height: 0)
        table.delegate = self; table.dataSource = self; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.target = self; table.doubleAction = #selector(openSelected)
        table.identifier = NSUserInterfaceItemIdentifier("textHistoryTable")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 610, height: 280))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.documentView = table; scroll.borderType = .noBorder
        table.frame = scroll.bounds; table.autoresizingMask = [.width]
        let body = NSView(); body.addSubview(scroll); scroll.translatesAutoresizingMaskIntoConstraints = false
        body.setContentHuggingPriority(.defaultLow, for: .vertical)
        body.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: body.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: body.trailingAnchor), scroll.topAnchor.constraint(equalTo: body.topAnchor), scroll.bottomAnchor.constraint(equalTo: body.bottomAnchor)])
        let symbol = NSImageView(); symbol.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil); symbol.contentTintColor = .tertiaryLabelColor
        symbol.widthAnchor.constraint(equalToConstant: 28).isActive = true; symbol.heightAnchor.constraint(equalToConstant: 28).isActive = true
        empty.orientation = .vertical; empty.alignment = .centerX; empty.spacing = 8
        empty.addArrangedSubview(symbol); empty.addArrangedSubview(TextLayout.label(L10n.text("text.history_empty"), size: 14))
        empty.identifier = NSUserInterfaceItemIdentifier("textHistoryEmpty"); empty.translatesAutoresizingMaskIntoConstraints = false; body.addSubview(empty)
        NSLayoutConstraint.activate([empty.centerXAnchor.constraint(equalTo: body.centerXAnchor), empty.centerYAnchor.constraint(equalTo: body.centerYAnchor)])
        for (button, key, action) in [(viewButton, "text.view", #selector(openSelected)), (deleteButton, "text.delete", #selector(deleteSelected)), (previousButton, "text.previous", #selector(previous)), (nextButton, "text.next", #selector(next))] {
            button.title = L10n.text(key); button.target = self; button.action = action; button.bezelStyle = .rounded
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let clear = TextLayout.button("text.clear", target: self, action: #selector(clearAll))
        let controls = TextLayout.row([viewButton, deleteButton, TextLayout.spacer(), previousButton, nextButton])
        let maintenance = TextLayout.row([clear, TextLayout.spacer()])
        let line = NSBox(); line.boxType = .separator
        info.show(L10n.text("text.history_hint"))
        TextLayout.install([body, info, controls, line, maintenance], in: window.contentView!)
        updateButtons()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    func present() { offset = 0; reload(); showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
    func reload() { onLoad?(offset) }
    private func updateButtons() {
        let selected = entries.indices.contains(table.selectedRow)
        viewButton.isEnabled = selected; deleteButton.isEnabled = selected
        previousButton.isEnabled = offset > 0; nextButton.isEnabled = entries.count == 100
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }
    func update(_ rows: [TextEntry], error: Error? = nil) {
        let selected = entries.indices.contains(table.selectedRow) ? entries[table.selectedRow].id : nil
        entries = rows; table.reloadData()
        if let selected, let index = entries.firstIndex(where: { $0.id == selected }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
        empty.isHidden = !rows.isEmpty || error != nil
        info.show(error?.localizedDescription ?? L10n.text("text.history_hint"), error == nil ? .info : .error)
        updateButtons()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("textHistoryCell"), owner: self) as? TextHistoryCell) ?? TextHistoryCell(frame: .zero)
        cell.identifier = NSUserInterfaceItemIdentifier("textHistoryCell"); cell.configure(entries[row]); return cell
    }
    @objc private func openSelected() { if entries.indices.contains(table.selectedRow) { onOpen?(entries[table.selectedRow].id) } }
    @objc private func deleteSelected() { if entries.indices.contains(table.selectedRow) { onDelete?(entries[table.selectedRow].id) } }
    @objc private func clearAll() { onDelete?(nil) }
    @objc private func previous() { offset = max(0, offset - 100); reload() }
    @objc private func next() { if entries.count == 100 { offset += 100; reload() } }
}

/// Notifications expose only the sending device, never the message body.
func textNotificationContent(id: UUID, peerName: String, saved: Bool) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = L10n.text(saved ? "text.notification" : "text.notification_unsaved")
    content.body = L10n.text("text.notification_body",peerName); content.sound = .default
    content.userInfo = ["textEntry":id.uuidString]; return content
}
