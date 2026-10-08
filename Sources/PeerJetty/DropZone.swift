import AppKit
import PeerCore

enum DragPayload {
    static let types = [NSPasteboard.PasteboardType.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    static let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    static func accepts(_ board: NSPasteboard) -> Bool {
        board.canReadObject(forClasses: [NSURL.self], options: options) || board.availableType(from: Array(types.dropFirst())) != nil
    }
}

final class DropZoneView: NSView {
    var onFiles: (([URL], (() -> Void)?) -> Void)?
    var onFailure: ((String) -> Void)?
    var onReceivingPromise: (() -> Void)?
    private let content = NSView()
    private var motionObserver: NSObjectProtocol?
    private var successIDs: [UUID] = []
    private(set) var usesNativeGlass = false
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: L10n.text("dropzone.drop_here"))
    private let subtitle = NSTextField(labelWithString: L10n.text("dropzone.choose_a_destination"))
    private let progress = NSProgressIndicator()
    private let cancelButton = NSButton(title: L10n.text("dropzone.cancel"), target: nil, action: nil)
    var onCancel: (() -> Void)?
    var targetName = L10n.text("dropzone.choose_a_destination")
    private let promises: OperationQueue = {
        let queue = OperationQueue(); queue.name = "PeerJetty.FilePromises"; queue.maxConcurrentOperationCount = 1; return queue
    }()
    private var promiseTracker: PromiseTracker?
    convenience override init(frame: NSRect) { self.init(frame: frame, forceLegacyMaterial: false) }
    // Exercise the macOS 15 fallback on a newer development host without changing production selection.
    init(frame: NSRect, forceLegacyMaterial: Bool) {
        super.init(frame: frame)
        content.frame = bounds; content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *), !forceLegacyMaterial {
            let glass = NSGlassEffectView(frame: bounds); glass.style = .regular; glass.cornerRadius = 16
            glass.autoresizingMask = [.width, .height]; glass.contentView = content
            addSubview(glass); usesNativeGlass = true
        } else {
            let background = NSVisualEffectView(frame: bounds)
            background.material = .hudWindow; background.blendingMode = .behindWindow; background.state = .active
            background.wantsLayer = true; background.layer?.cornerRadius = 16; background.layer?.masksToBounds = true
            background.autoresizingMask = [.width, .height]; addSubview(background); background.addSubview(content)
        }
        icon.contentTintColor = .labelColor
        motionObserver = NotificationCenter.default.addObserver(forName: MotionPolicy.changed, object: MotionPolicy.shared, queue: .main) { [weak self] _ in
            if !MotionPolicy.shared.allowed, let self { MotionEffects.clear(self) }
        }
        title.lineBreakMode = .byTruncatingTail
        title.textColor = .labelColor; title.font = .systemFont(ofSize: 15, weight: .semibold)
        subtitle.textColor = .secondaryLabelColor; subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.lineBreakMode = .byTruncatingMiddle
        progress.style = .bar; progress.isIndeterminate = false; progress.maxValue = 1; progress.isHidden = true
        cancelButton.bezelStyle = .inline; cancelButton.font = .systemFont(ofSize: 12); cancelButton.contentTintColor = .labelColor
        cancelButton.target = self; cancelButton.action = #selector(cancel); cancelButton.isHidden = true
        [icon, title, subtitle, progress, cancelButton].forEach(content.addSubview)
        registerForDraggedTypes(DragPayload.types); idle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func layout() {
        super.layout()
        // Center the two-line group; reserve the progress band only while visible.
        let contentBottom: CGFloat = progress.isHidden ? 0 : 20
        let contentTop = progress.isHidden ? bounds.height : bounds.height - 12
        let centerY = (contentBottom + contentTop) / 2
        let subtitleY = centerY - 22
        let titleY = subtitleY + 18 + 4
        icon.frame = NSRect(x: 16, y: centerY - 11, width: 22, height: 22)
        title.frame = NSRect(x: 49, y: titleY, width: max(0, bounds.width - 49 - (cancelButton.isHidden ? 16 : 92)), height: 22)
        subtitle.frame = NSRect(x: 49, y: subtitleY, width: max(0, bounds.width - 65), height: 18)
        progress.frame = NSRect(x: 16, y: 10, width: max(0, bounds.width - 32), height: 5)
        cancelButton.frame = NSRect(x: bounds.width - 80, y: titleY, width: 64, height: 22)
    }
    func idle() { show(title: L10n.text("dropzone.drop_into_card_to_send"), subtitle: targetName, symbol: "arrow.up.doc.fill", color: .labelColor); progress.isHidden = true; cancelButton.isHidden = true }
    func show(title: String, subtitle: String, symbol: String = "arrow.up.circle.fill", color: NSColor = .systemBlue) {
        if self.title.stringValue != title { icon.layer?.removeAnimation(forKey: "PeerJetty.feedback"); MotionEffects.transition(self.title); MotionEffects.transition(icon) }
        if self.subtitle.stringValue != subtitle { MotionEffects.transition(self.subtitle) }
        self.title.stringValue = title; self.subtitle.stringValue = subtitle
        self.title.toolTip = title; self.subtitle.toolTip = subtitle; needsLayout = true
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); icon.contentTintColor = color
    }
    func transfer(_ update: TransferUpdate) {
        show(title: update.status, subtitle: L10n.text(update.receiving ? "drop.receiving_peer" : "drop.sending_peer", update.peerName),
             symbol: update.finished ? (update.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill") : "arrow.up.arrow.down.circle.fill",
             color: update.finished ? (update.succeeded ? .systemGreen : .systemOrange) : .systemBlue)
        if update.finished, update.succeeded, !successIDs.contains(update.id) {
            successIDs.append(update.id); if successIDs.count > 256 { successIDs.removeFirst() }; MotionEffects.pulse(icon)
        }
        progress.isHidden = update.finished; cancelButton.isHidden = update.finished
        progress.doubleValue = update.total > 0 ? min(1, Double(update.completed) / Double(update.total)) : 0
    }
    deinit { if let motionObserver { NotificationCenter.default.removeObserver(motionObserver) } }
    @objc private func cancel() { promiseTracker?.cancel(); onCancel?() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard DragPayload.accepts(sender.draggingPasteboard) else { return [] }
        show(title: L10n.text("dropzone.release_to_send"), subtitle: targetName, symbol: "plus.circle.fill"); MotionEffects.pulse(icon); return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { idle() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { DragPayload.accepts(sender.draggingPasteboard) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        if let urls = board.readObjects(forClasses: [NSURL.self], options: DragPayload.options) as? [URL], !urls.isEmpty {
            onFiles?(urls, nil); return true
        }
        guard promiseTracker == nil,
              let receivers = board.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver], !receivers.isEmpty else { return false }
        receive(receivers); return true
    }
    private func receive(_ receivers: [NSFilePromiseReceiver]) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PeerJetty-Promises-\(UUID())")
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        catch { onFailure?(L10n.text("dropzone.could_not_create_a_temporary_folder_for_the")); return }
        let cleanup = { try? FileManager.default.removeItem(at: folder); return () }
        let tracker = PromiseTracker(receivers: receivers.count) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { cleanup(); return }
                self.promiseTracker = nil
                switch result {
                case .success(let urls): self.onFiles?(urls, cleanup)
                case .failure(let error): cleanup(); self.onFailure?(error.localizedDescription)
                }
            }
        }
        promiseTracker = tracker; onReceivingPromise?()
        show(title: L10n.text("dropzone.reading_files"), subtitle: L10n.text("dropzone.waiting_for_the_source_app_to_provide_files")); cancelButton.isHidden = false
        for (index, receiver) in receivers.enumerated() {
            receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: promises) { url, error in
                if tracker.wasCancelled { cleanup(); return }
                tracker.expect(receiver: index, count: max(receiver.fileNames.count, 1))
                let missing: Error? = error ?? (FileManager.default.fileExists(atPath: url.path) ? nil : PeerError.message(L10n.text("dropzone.the_source_app_did_not_provide_a_readable")))
                tracker.record(receiver: index, url: url, error: missing)
            }
            tracker.expect(receiver: index, count: max(receiver.fileNames.count, 1))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak tracker] in tracker?.cancel() }
    }
}

final class DropPanelController {
    let view = DropZoneView(frame: NSRect(x: 0, y: 0, width: 320, height: 76))
    private let panel: NSPanel
    private let motion: WindowMotion
    private var timer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var visible = false
    private var revision = 0
    private var dragTracker = FileDragTracker(changeCount: NSPasteboard(name: .drag).changeCount)
    private var dragActive = false
    private var selectedScreenID: NSNumber?
    private var cardFrame: NSRect?
    private var hidePending = false
    private var keepUntil = Date.distantPast
    var busy = false
    init() {
        panel = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        motion = WindowMotion(panel)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .statusBar
        panel.hidesOnDeactivate = false; panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = view; panel.orderOut(nil)
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.position() }
    }
    private func screenID(_ screen: NSScreen) -> NSNumber? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }
    private func mouseScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }
    private func selectedScreen() -> NSScreen? {
        NSScreen.screens.first { screenID($0) == selectedScreenID } ?? mouseScreen()
    }
    private func geometry() -> DropPresentation? {
        selectedScreen().map { DropPresentation(DropScreenMetrics($0)) }
    }
    private func position() {
        guard let screen = selectedScreen() else { panel.orderOut(nil); motion.finishImmediately(); visible = false; return }
        selectedScreenID = screenID(screen)
        revision += 1; hidePending = false
        let geometry = DropPresentation(DropScreenMetrics(screen))
        cardFrame = geometry.card
        panel.setFrame(geometry.card, display: true)
    }
    func show() { show(on: nil) }
    private func show(on screen: NSScreen?, immediately: Bool = false) {
        let destination = screen ?? (visible ? selectedScreen() : mouseScreen())
        if let destination, editingScreenID != nil, screenID(destination) == editingScreenID {
            revision += 1; hidePending = false; visible = false; panel.orderOut(nil); motion.finishImmediately(); return
        }
        if visible {
            if hidePending { revision += 1; hidePending = false }
            return
        }
        if let screen = screen ?? mouseScreen() { selectedScreenID = screenID(screen) }
        guard let geometry = geometry() else { return }
        revision += 1; hidePending = false; visible = true
        cardFrame = geometry.card
        panel.setFrame(geometry.card, display: true)
        motion.reveal(immediately: immediately) { panel.orderFrontRegardless() }

    }
    func hide(after seconds: Double = 0) {
        guard visible, !hidePending else { return }
        revision += 1; let token = revision; hidePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.revision == token else { return }
            self.hidePending = false
            guard !self.busy, self.visible, let geometry = self.geometry() else { return }
            // A drag elsewhere on the screen must not hold this card open.
            if self.dragActive, geometry.retention.contains(NSEvent.mouseLocation) { return }
            self.visible = false
            self.motion.dismiss { [weak self] in
                guard let self, self.revision == token, !self.visible else { return }
                self.panel.orderOut(nil)
            }
        }
    }
    func preview() {
        if !busy { view.idle() }
        keepUntil = Date().addingTimeInterval(5); show(); hide(after: 5)
    }
    var editingScreenID: NSNumber?
    func setEditingScreen(_ screen:NSScreen?) {
        editingScreenID = screen.flatMap { screenID($0) }
        if let screen, let selected = selectedScreen(), screenID(selected) == screenID(screen) {
            revision += 1; hidePending = false; visible = false; panel.orderOut(nil); motion.finishImmediately()
        } else if busy { show(on:selectedScreen()) }
    }
    var isVisible: Bool { visible }
    private func poll() {
        if let screen = mouseScreen(), screenID(screen) == editingScreenID, editingScreenID != nil { return }
        let pressed = NSEvent.pressedMouseButtons & 1 == 1
        let location = NSEvent.mouseLocation
        let board = NSPasteboard(name: .drag)
        // Menu-bar visibility can change without a screen-parameters event.
        if visible, let geometry = geometry(), cardFrame != geometry.card {
            cardFrame = geometry.card
            panel.setFrame(geometry.card, display: true)
        }
        let acceptsFiles = pressed && board.changeCount != dragTracker.handled && DragPayload.accepts(board)
        dragActive = dragTracker.update(pressed: pressed, location: location,
                                        changeCount: board.changeCount, acceptsFiles: acceptsFiles)
        if !pressed {
            if visible, !busy, Date() >= keepUntil { hide(after: 0.25) }
        } else if dragActive {
            motion.snapAppearance()
            if let geometry = geometry(), visible, geometry.retention.contains(location) {
                // Cancel an exit dismissal when the user returns to the card.
                if hidePending { revision += 1; hidePending = false }
            } else if let screen = mouseScreen(), DropPresentation(DropScreenMetrics(screen)).trigger.contains(location) {
                if visible, !busy, screenID(screen) != selectedScreenID {
                    revision += 1; hidePending = false; visible = false; panel.orderOut(nil); motion.finishImmediately()
                }
                if !busy { view.idle() }; show(on: screen, immediately: true)
            } else if visible, !busy { hide(after: 0.25) }
        }
    }
    deinit {
        timer?.invalidate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}
