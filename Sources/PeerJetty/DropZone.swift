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
    private let title = NSTextField(labelWithString: "拖到这里")
    private let subtitle = NSTextField(labelWithString: "请选择发送设备")
    private let progress = NSProgressIndicator()
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    var onCancel: (() -> Void)?
    var targetName = "请选择发送设备"
    private let promises: OperationQueue = {
        let queue = OperationQueue(); queue.name = "PeerJetty.FilePromises"; queue.maxConcurrentOperationCount = 1; return queue
    }()
    private var promiseTracker: PromiseTracker?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor; layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous; layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        icon.contentTintColor = .white
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
        title.frame = NSRect(x: 49, y: 42, width: max(0, bounds.width - 100), height: 17)
        subtitle.frame = NSRect(x: 49, y: 24, width: max(0, bounds.width - 61), height: 15)
        progress.frame = NSRect(x: 16, y: 10, width: max(0, bounds.width - 32), height: 5)
        cancelButton.frame = NSRect(x: bounds.width - 47, y: 42, width: 40, height: 17)
    }
    func idle() { show(title: "拖到这里", subtitle: targetName, symbol: "arrow.up.doc.fill", color: .white); progress.isHidden = true; cancelButton.isHidden = true }
    func show(title: String, subtitle: String, symbol: String = "arrow.up.circle.fill", color: NSColor = .systemBlue) {
        self.title.stringValue = title; self.subtitle.stringValue = subtitle
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); icon.contentTintColor = color
    }
    func transfer(_ update: TransferUpdate) {
        show(title: update.status, subtitle: (update.receiving ? "来自 " : "发往 ") + update.peerName,
             symbol: update.finished ? (update.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill") : "arrow.up.arrow.down.circle.fill",
             color: update.finished ? (update.succeeded ? .systemGreen : .systemOrange) : .systemBlue)
        progress.isHidden = update.finished; cancelButton.isHidden = update.finished
        progress.doubleValue = update.total > 0 ? min(1, Double(update.completed) / Double(update.total)) : 0
    }
    @objc private func cancel() { promiseTracker?.cancel(); onCancel?() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard DragPayload.accepts(sender.draggingPasteboard) else { return [] }
        show(title: "松开发送", subtitle: targetName, symbol: "plus.circle.fill"); return .copy
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
        catch { onFailure?("无法创建拖拽临时目录"); return }
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
        show(title: "正在读取文件", subtitle: "等待拖拽来源提供文件"); cancelButton.isHidden = false
        for (index, receiver) in receivers.enumerated() {
            receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: promises) { url, error in
                if tracker.wasCancelled { cleanup(); return }
                tracker.expect(receiver: index, count: max(receiver.fileNames.count, 1))
                let missing: Error? = error ?? (FileManager.default.fileExists(atPath: url.path) ? nil : PeerError.message("拖拽来源未提供可读取文件"))
                tracker.record(receiver: index, url: url, error: missing)
            }
            tracker.expect(receiver: index, count: max(receiver.fileNames.count, 1))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak tracker] in tracker?.cancel() }
    }
}

final class DropPanelController {
    let view = DropZoneView(frame: NSRect(x: 0, y: 0, width: 260, height: 102))
    private let panel: NSPanel
    private var timer: Timer?
    private var visible = false
    private var revision = 0
    private var mouseDown = false
    private var downLocation = NSPoint.zero
    private var handled = NSPasteboard(name: .drag).changeCount
    private var dragActive = false
    var busy = false
    init() {
        panel = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = .statusBar
        panel.hidesOnDeactivate = false; panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = view; panel.orderOut(nil)
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.position() }
    }
    private func geometry() -> (NSRect, NSRect)? {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return nil }
        let frame = screen.frame
        let notch = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 0
        let width: CGFloat, x: CGFloat
        if notch > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, right.minX - left.maxX > 100 {
            width = right.minX - left.maxX; x = left.maxX
        } else { width = 260; x = frame.midX - width / 2 }
        let top = notch > 0 ? frame.maxY : screen.visibleFrame.maxY
        let height = notch + 70
        return (NSRect(x: x, y: top - notch, width: width, height: height), NSRect(x: x, y: top - height, width: width, height: height))
    }
    private func position() { if let geometry = geometry() { panel.setFrame(visible ? geometry.1 : geometry.0, display: true) } }
    func show() {
        guard !visible, let geometry = geometry() else { return }
        revision += 1; visible = true; panel.setFrame(geometry.0, display: true); panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(geometry.1, display: true)
        }
    }
    func hide(after seconds: Double = 0) {
        revision += 1; let token = revision
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.revision == token, !self.busy, !self.dragActive, self.visible, let geometry = self.geometry() else { return }
            self.visible = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2; context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.panel.animator().setFrame(geometry.0, display: true)
            } completionHandler: { [weak self] in
                guard let self, self.revision == token, !self.visible else { return }; self.panel.orderOut(nil)
            }
        }
    }
    func preview() { view.idle(); show(); hide(after: 5) }
    private func poll() {
        let pressed = NSEvent.pressedMouseButtons & 1 == 1
        let board = NSPasteboard(name: .drag)
        if pressed, !mouseDown { downLocation = NSEvent.mouseLocation }
        if pressed, !dragActive, board.changeCount != handled,
           hypot(NSEvent.mouseLocation.x - downLocation.x, NSEvent.mouseLocation.y - downLocation.y) >= 4,
           DragPayload.accepts(board) {
            dragActive = true; handled = board.changeCount
            if !busy { view.idle() }; show()
        }
        if !pressed, mouseDown { dragActive = false; hide() }
        mouseDown = pressed
    }
    deinit { timer?.invalidate() }
}
