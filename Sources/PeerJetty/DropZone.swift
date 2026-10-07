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
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 16; layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        appearance = NSAppearance(named: .darkAqua)
        let background = NSVisualEffectView(frame: bounds)
        background.material = .hudWindow; background.blendingMode = .behindWindow
        background.state = .active; background.autoresizingMask = [.width, .height]
        addSubview(background)
        layer?.borderWidth = 0.5; layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        icon.contentTintColor = .white
        title.lineBreakMode = .byTruncatingTail
        title.textColor = .white; title.font = .systemFont(ofSize: 12.5, weight: .semibold)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.65); subtitle.font = .systemFont(ofSize: 10)
        subtitle.lineBreakMode = .byTruncatingMiddle
        progress.style = .bar; progress.isIndeterminate = false; progress.maxValue = 1; progress.isHidden = true
        cancelButton.bezelStyle = .inline; cancelButton.font = .systemFont(ofSize: 10); cancelButton.contentTintColor = .white
        cancelButton.target = self; cancelButton.action = #selector(cancel); cancelButton.isHidden = true
        [icon, title, subtitle, progress, cancelButton].forEach(addSubview)
        registerForDraggedTypes(DragPayload.types); idle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 16, y: 27, width: 22, height: 22)
        title.frame = NSRect(x: 49, y: 42, width: max(0, bounds.width - 49 - (cancelButton.isHidden ? 16 : 92)), height: 17)
        subtitle.frame = NSRect(x: 49, y: 24, width: max(0, bounds.width - 61), height: 15)
        progress.frame = NSRect(x: 16, y: 10, width: max(0, bounds.width - 32), height: 5)
        cancelButton.frame = NSRect(x: bounds.width - 80, y: 42, width: 64, height: 17)
    }
    func idle() { show(title: L10n.text("dropzone.drop_into_card_to_send"), subtitle: targetName, symbol: "arrow.up.doc.fill", color: .white); progress.isHidden = true; cancelButton.isHidden = true }
    func show(title: String, subtitle: String, symbol: String = "arrow.up.circle.fill", color: NSColor = .systemBlue) {
        self.title.stringValue = title; self.subtitle.stringValue = subtitle; needsLayout = true
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); icon.contentTintColor = color
    }
    func transfer(_ update: TransferUpdate) {
        show(title: update.status, subtitle: L10n.text(update.receiving ? "drop.receiving_peer" : "drop.sending_peer", update.peerName),
             symbol: update.finished ? (update.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill") : "arrow.up.arrow.down.circle.fill",
             color: update.finished ? (update.succeeded ? .systemGreen : .systemOrange) : .systemBlue)
        progress.isHidden = update.finished; cancelButton.isHidden = update.finished
        progress.doubleValue = update.total > 0 ? min(1, Double(update.completed) / Double(update.total)) : 0
    }
    @objc private func cancel() { promiseTracker?.cancel(); onCancel?() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard DragPayload.accepts(sender.draggingPasteboard) else { return [] }
        show(title: L10n.text("dropzone.release_to_send"), subtitle: targetName, symbol: "plus.circle.fill"); return .copy
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
        guard let screen = selectedScreen() else { panel.orderOut(nil); visible = false; return }
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
            revision += 1; hidePending = false; visible = false; panel.orderOut(nil); return
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
        let animate = !immediately && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = animate ? 0 : 1
        panel.orderFrontRegardless()
        // File drags get an immediate, stationary target; only status/preview
        // presentation fades in. Never move a drop target from the top edge.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? 0.12 : 0
            panel.animator().alphaValue = 1
        }
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
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
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
            revision += 1; hidePending = false; visible = false; panel.orderOut(nil)
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
            if let geometry = geometry(), visible, geometry.retention.contains(location) {
                // Cancel an exit dismissal when the user returns to the card.
                if hidePending { revision += 1; hidePending = false }
            } else if let screen = mouseScreen(), DropPresentation(DropScreenMetrics(screen)).trigger.contains(location) {
                if visible, !busy, screenID(screen) != selectedScreenID {
                    revision += 1; hidePending = false; visible = false; panel.orderOut(nil)
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
