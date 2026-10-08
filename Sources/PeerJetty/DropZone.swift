import AppKit
import PeerCore

enum DragPayload {
    static let types = [NSPasteboard.PasteboardType.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    static let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    static func accepts(_ board: NSPasteboard) -> Bool {
        board.canReadObject(forClasses: [NSURL.self], options: options) || board.availableType(from: Array(types.dropFirst())) != nil
    }
}

/// Small vector renderer. No spinner, display link or per-frame drawing loop.
final class TransferGlyph: NSView {
    static let checkPoints = [CGPoint(x:0.32,y:0.49),CGPoint(x:0.45,y:0.65),CGPoint(x:0.68,y:0.34)]
    static var shortStrokeFraction: Double {
        let points = checkPoints
        let short = hypot(points[1].x-points[0].x,points[1].y-points[0].y)
        let long = hypot(points[2].x-points[1].x,points[2].y-points[1].y)
        return short/(short+long)
    }
    private let track = CAShapeLayer(), arc = CAShapeLayer(), tick = CAShapeLayer()
    private var id: UUID?
    private var revision = 0
    private var completion: (() -> Void)?
    private var observer: NSObjectProtocol?
    private let policy: MotionPolicy
    private var progressMotion: ProgressMotion?
    private(set) var successDuration: Double = 0
    private(set) var fraction: Double = 0
    private(set) var isSuccess = false
    init(policy: MotionPolicy) {
        self.policy = policy; super.init(frame:.zero); wantsLayer = true
        for shape in [track,arc,tick] { shape.fillColor = NSColor.clear.cgColor; shape.lineWidth = 2.2; shape.lineCap = .round; shape.lineJoin = .round; layer?.addSublayer(shape) }
        tick.strokeEnd = 0
        setAccessibilityElement(true); setAccessibilityRole(.progressIndicator)
        observer = NotificationCenter.default.addObserver(forName:MotionPolicy.changed, object:policy, queue:.main) { [weak self] _ in
            guard let self, !policy.allowed else { return }; self.settle()
        }
        colors()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
        for shape in [track,arc,tick] { shape.frame = bounds }
        let path = CGMutablePath(); path.addArc(center:NSPoint(x:bounds.midX,y:bounds.midY), radius:max(0,min(bounds.width,bounds.height)/2-3),startAngle:-.pi/2,endAngle:3 * .pi/2,clockwise:false)
        track.path = path; arc.path = path
        let points = Self.checkPoints.map { CGPoint(x:bounds.width*$0.x,y:bounds.height*$0.y) }
        let check = CGMutablePath(); check.move(to:points[0]); check.addLine(to:points[1]); check.addLine(to:points[2]); tick.path = check
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors() }
    private func colors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
            track.strokeColor = NSColor.separatorColor.cgColor; arc.strokeColor = (isSuccess ? NSColor.systemGreen : .systemBlue).cgColor; tick.strokeColor = NSColor.systemGreen.cgColor
        }
    }
    func reset() {
        revision += 1; completion = nil; id = nil; fraction = 0; isSuccess = false; progressMotion = nil; successDuration = 0
        MotionEffects.clear(self)
        CATransaction.begin(); CATransaction.setDisableActions(true); arc.strokeEnd = 0; tick.strokeEnd = 0; CATransaction.commit(); colors()
    }
    func update(id: UUID, completed: Int64, total: Int64) {
        if self.id != id { reset(); self.id = id }
        guard !isSuccess, total > 0 else { return }
        let target = max(fraction,min(1,max(0,Double(completed)/Double(total))))
        guard target != fraction else { return }
        let now = CACurrentMediaTime()
        let current = progressMotion?.sample(at:now) ?? (value:Double(arc.strokeEnd),velocity:0)
        fraction = target; setAccessibilityValue(NSNumber(value:target))
        CATransaction.begin(); CATransaction.setDisableActions(true); arc.strokeEnd = CGFloat(target); CATransaction.commit()
        if policy.allowed, window?.isVisible == true {
            let profile = policy.profile
            let motion = ProgressMotion(from:current.value,target:target,velocity:current.velocity,rate:profile.progressRate,minimum:profile.status,started:now)
            progressMotion = motion
            let animation = CABasicAnimation(keyPath:"strokeEnd"); animation.fromValue = motion.from; animation.toValue = target; animation.duration = motion.duration; animation.timingFunction = motion.timing
            MotionEffects.add(animation, to:arc, key:"PeerJetty.progress")
        } else { progressMotion = nil }
    }
    func succeed(id: UUID, finished: @escaping () -> Void) {
        if self.id != id { reset(); self.id = id }
        guard !isSuccess else { return }
        revision += 1; let token = revision; completion = finished
        let profile = policy.profile, now = CACurrentMediaTime()
        let current = progressMotion?.sample(at:now) ?? (value:Double(arc.strokeEnd),velocity:0)
        let finishing = ProgressMotion(from:current.value,target:1,velocity:current.velocity,rate:profile.progressRate,minimum:profile.success*0.25,started:now)
        let fillDuration = max(finishing.duration,profile.success*0.25)
        progressMotion = nil; successDuration = fillDuration + profile.success*0.75
        let previousColor = arc.presentation()?.strokeColor ?? arc.strokeColor
        isSuccess = true; fraction = 1; setAccessibilityValue(NSNumber(value:1)); colors()
        CATransaction.begin(); CATransaction.setDisableActions(true); arc.strokeEnd = 1; tick.strokeEnd = 1; CATransaction.commit()
        guard policy.allowed else { settle(); return }
        let color = CABasicAnimation(keyPath:"strokeColor"); color.fromValue = previousColor; color.toValue = arc.strokeColor; color.duration = fillDuration
        MotionEffects.add(color,to:arc,key:"PeerJetty.successColor")
        let fill = CABasicAnimation(keyPath:"strokeEnd"); fill.fromValue = current.value; fill.toValue = 1; fill.duration = fillDuration; fill.timingFunction = finishing.timing
        MotionEffects.add(fill,to:arc,key:"PeerJetty.progress")
        let draw = CAKeyframeAnimation(keyPath:"strokeEnd")
        draw.values = [0,Self.shortStrokeFraction,Self.shortStrokeFraction,1]; draw.keyTimes = [0,0.25,0.34,1]
        draw.timingFunctions = [.init(name:.easeIn),.init(name:.easeInEaseOut),.init(controlPoints:0.18,0.65,0.3,1)]
        draw.duration = profile.success * 0.60; draw.fillMode = .backwards
        MotionEffects.add(draw,to:tick,key:"PeerJetty.check",delay:fillDuration)
        let spring = MotionEffects.spring(duration:profile.success * 0.15,from:0.985)
        MotionEffects.add(spring,to:layer,key:"PeerJetty.feedback",delay:fillDuration + profile.success * 0.60)
        DispatchQueue.main.asyncAfter(deadline:.now()+successDuration) { [weak self] in guard let self, self.revision == token else { return }; self.settle() }
    }
    private func settle() {
        progressMotion = nil
        MotionEffects.clear(self)
        guard isSuccess, let completion else { return }
        self.completion = nil; revision += 1; completion()
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
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
    let progress: TransferGlyph
    private let policy: MotionPolicy
    var onSuccessFinished: ((UUID, Double) -> Void)?
    var onDragStarted: (() -> Void)?
    private let cancelButton = NSButton(title: L10n.text("dropzone.cancel"), target: nil, action: nil)
    var onCancel: (() -> Void)?
    var targetName = L10n.text("dropzone.choose_a_destination")
    private let promises: OperationQueue = {
        let queue = OperationQueue(); queue.name = "PeerJetty.FilePromises"; queue.maxConcurrentOperationCount = 1; return queue
    }()
    private var promiseTracker: PromiseTracker?
    convenience override init(frame: NSRect) { self.init(frame: frame, forceLegacyMaterial: false) }
    // Exercise the macOS 15 fallback on a newer development host without changing production selection.
    init(frame: NSRect, forceLegacyMaterial: Bool, policy: MotionPolicy = .shared) {
        self.policy = policy; progress = TransferGlyph(policy:policy)
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
        motionObserver = NotificationCenter.default.addObserver(forName: MotionPolicy.changed, object: policy, queue: .main) { [weak self] _ in
            if !policy.allowed, let self { MotionEffects.clear(self) }
        }
        title.lineBreakMode = .byTruncatingTail
        title.textColor = .labelColor; title.font = .systemFont(ofSize: 15, weight: .semibold)
        subtitle.textColor = .secondaryLabelColor; subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.lineBreakMode = .byTruncatingMiddle
        progress.isHidden = true
        cancelButton.bezelStyle = .inline; cancelButton.font = .systemFont(ofSize: 12); cancelButton.contentTintColor = .labelColor
        cancelButton.target = self; cancelButton.action = #selector(cancel); cancelButton.isHidden = true
        [icon, title, subtitle, progress, cancelButton].forEach(content.addSubview)
        registerForDraggedTypes(DragPayload.types); idle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func layout() {
        super.layout()
        let centerY = bounds.midY
        let subtitleY = centerY - 22
        let titleY = subtitleY + 18 + 4
        icon.frame = NSRect(x: 16, y: centerY - 11, width: 22, height: 22)
        title.frame = NSRect(x: 49, y: titleY, width: max(0, bounds.width - 49 - (cancelButton.isHidden ? 16 : 92)), height: 22)
        subtitle.frame = NSRect(x: 49, y: subtitleY, width: max(0, bounds.width - 65), height: 18)
        progress.frame = NSRect(x: 12, y: centerY - 15, width: 30, height: 30)
        cancelButton.frame = NSRect(x: bounds.width - 80, y: titleY, width: 64, height: 22)
    }
    func idle() { show(title: L10n.text("dropzone.drop_into_card_to_send"), subtitle: targetName, symbol: "arrow.up.doc.fill", color: .labelColor); progress.isHidden = true; cancelButton.isHidden = true }
    func show(title: String, subtitle: String, symbol: String = "arrow.up.circle.fill", color: NSColor = .systemBlue, preserveProgress: Bool = false) {
        if !preserveProgress { progress.reset(); progress.isHidden = true; icon.isHidden = false }
        if self.title.stringValue != title { icon.layer?.removeAnimation(forKey: "PeerJetty.feedback"); MotionEffects.transition(self.title, policy:policy); MotionEffects.transition(icon, policy:policy) }
        if self.subtitle.stringValue != subtitle { MotionEffects.transition(self.subtitle, policy:policy) }
        self.title.stringValue = title; self.subtitle.stringValue = subtitle
        self.title.toolTip = title; self.subtitle.toolTip = subtitle; needsLayout = true
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); icon.contentTintColor = color
    }
    func transfer(_ update: TransferUpdate) {
        if update.finished, update.succeeded, successIDs.contains(update.id) { return }
        let waiting = !update.finished && update.total > 0 && update.completed >= update.total
        show(title: waiting ? L10n.text("drop.waiting_confirmation") : update.status, subtitle: L10n.text(update.receiving ? "drop.receiving_peer" : "drop.sending_peer", update.peerName),
             symbol: update.finished ? (update.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill") : "arrow.up.arrow.down.circle.fill",
             color: update.finished ? (update.succeeded ? .systemGreen : .systemOrange) : .systemBlue, preserveProgress:true)
        cancelButton.isHidden = update.finished
        progress.setAccessibilityLabel(waiting ? L10n.text("drop.waiting_confirmation") : update.status)
        if update.finished, update.succeeded {
            successIDs.append(update.id); if successIDs.count > 256 { successIDs.removeFirst() }
            progress.isHidden = false; icon.isHidden = true
            let hold = policy.profile.hold
            progress.succeed(id:update.id) { [weak self] in self?.onSuccessFinished?(update.id,hold) }
        } else if !update.finished, update.total > 0 {
            progress.isHidden = false; icon.isHidden = true
            progress.update(id:update.id,completed:update.completed,total:update.total)
        } else { progress.reset(); progress.isHidden = true; icon.isHidden = false }
        needsLayout = true
    }
    deinit { if let motionObserver { NotificationCenter.default.removeObserver(motionObserver) } }
    @objc private func cancel() { promiseTracker?.cancel(); onCancel?() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard DragPayload.accepts(sender.draggingPasteboard) else { return [] }
        onDragStarted?()
        show(title: L10n.text("dropzone.release_to_send"), subtitle: targetName, symbol: "plus.circle.fill"); MotionEffects.pulse(icon, policy:policy); return .copy
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

/// Transparent host: only the original card participates in hit testing and drag registration.
final class DropCardHost: NSView {
    static let padding: CGFloat = 32
    let card: DropZoneView
    let shadowLayer = CALayer()
    init(card: DropZoneView) {
        self.card = card
        super.init(frame: NSRect(origin:.zero, size:NSSize(width:card.frame.width + 64, height:card.frame.height + 64)))
        wantsLayer = true; layer?.masksToBounds = false
        layer?.addSublayer(shadowLayer)
        addSubview(card); updateShadow()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }
    static func windowFrame(_ card: NSRect) -> NSRect { card.insetBy(dx:-padding, dy:-padding) }
    override func layout() { super.layout(); updateShadow() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateShadow() }
    private func updateShadow() {
        let frame = bounds.insetBy(dx:Self.padding, dy:Self.padding)
        if card.frame != frame { card.frame = frame }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = effectiveAppearance.bestMatch(from:[.aqua, .darkAqua]) == .darkAqua ? 0.38 : 0.24
        shadowLayer.shadowRadius = 16; shadowLayer.shadowOffset = NSSize(width:0, height:-6)
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = CGPath(roundedRect:card.frame, cornerWidth:16, cornerHeight:16, transform:nil)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard card.frame.contains(point) else { return nil }
        return super.hitTest(point)
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
    private var resultID: UUID?
    private var successAnimating = false
    private var finishedIDs: [UUID] = []
    private var transfers: [UUID:TransferUpdate] = [:]
    private var transferOrder: [UUID] = []
    var busy = false
    init() {
        panel = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        motion = WindowMotion(panel,cardAppearance:true)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = .statusBar
        panel.hidesOnDeactivate = false; panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = DropCardHost(card:view); panel.orderOut(nil)
        view.onDragStarted = { [weak self] in self?.resetFeedback() }
        view.onSuccessFinished = { [weak self] id, hold in
            guard let self, self.resultID == id else { return }
            self.revision += 1; self.hidePending = false; self.successAnimating = false
            self.keepUntil = Date().addingTimeInterval(hold); self.hide()
        }
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
        panel.setFrame(DropCardHost.windowFrame(geometry.card), display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
    }
    func show() { show(on: nil) }
    private func show(on screen: NSScreen?, immediately: Bool = false) {
        let destination = screen ?? (visible ? selectedScreen() : mouseScreen())
        if let destination, editingScreenID != nil, screenID(destination) == editingScreenID {
            revision += 1; hidePending = false; visible = false; panel.orderOut(nil); motion.finishImmediately(); return
        }
        if visible {
            if immediately { motion.makeInteractive() }
            if hidePending { revision += 1; hidePending = false }
            return
        }
        if let screen = screen ?? mouseScreen() { selectedScreenID = screenID(screen) }
        guard let geometry = geometry() else { return }
        revision += 1; hidePending = false; visible = true
        cardFrame = geometry.card
        panel.setFrame(DropCardHost.windowFrame(geometry.card), display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.ignoresMouseEvents = !geometry.card.contains(NSEvent.mouseLocation)
        motion.reveal(immediately: immediately, animateImmediateContent: immediately) { panel.orderFrontRegardless() }

    }
    func hide(after seconds: Double = 0) {
        guard visible, !hidePending, !successAnimating else { return }
        revision += 1; let token = revision; hidePending = true
        let delay = max(seconds, keepUntil.timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0,delay)) { [weak self] in
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
    func resetFeedback() {
        revision += 1; hidePending = false; resultID = nil; successAnimating = false; keepUntil = .distantPast
    }
    func presentTransfer(_ update: TransferUpdate) {
        if finishedIDs.contains(update.id) { return }
        if update.finished {
            transfers.removeValue(forKey:update.id); transferOrder.removeAll {$0 == update.id}
            finishedIDs.append(update.id); if finishedIDs.count > 256 { finishedIDs.removeFirst() }
            if let other = transferOrder.last.flatMap({transfers[$0]}) { resetFeedback(); show(); view.transfer(other); return }
        } else {
            transfers[update.id] = update; transferOrder.removeAll {$0 == update.id}; transferOrder.append(update.id)
        }
        resetFeedback(); show()
        if update.finished, update.succeeded {
            resultID = update.id; successAnimating = true
            let profile = MotionPolicy.shared.profile
            keepUntil = Date().addingTimeInterval((MotionPolicy.shared.allowed ? profile.success : 0) + profile.hold)
        }
        view.transfer(update)
        if update.finished, !update.succeeded { hide(after:5) }
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
    var feedbackRemaining: TimeInterval { max(0,keepUntil.timeIntervalSinceNow) }
    var currentFeedbackID: UUID? { resultID }
    private func poll() {
        if panel.isVisible, let cardFrame { panel.ignoresMouseEvents = !cardFrame.contains(NSEvent.mouseLocation) }
        if let screen = mouseScreen(), screenID(screen) == editingScreenID, editingScreenID != nil { return }
        let pressed = NSEvent.pressedMouseButtons & 1 == 1
        let location = NSEvent.mouseLocation
        let board = NSPasteboard(name: .drag)
        // Menu-bar visibility can change without a screen-parameters event.
        if visible, let geometry = geometry(), cardFrame != geometry.card {
            cardFrame = geometry.card
            panel.setFrame(DropCardHost.windowFrame(geometry.card), display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
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

/// Isolated preview: simulated updates touch only this view, never the transfer engine.
final class MotionPreviewWindow: NSWindowController, NSWindowDelegate {
    private let policy = MotionPolicy()
    private var card: DropZoneView!
    private var host: DropCardHost!
    private var generation = 0
    private let speeds = NSPopUpButton()
    private var observer: NSObjectProtocol?
    private var hiding = false
    init() {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:520,height:320),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init(window:window); window.title = L10n.text("motion.preview_title"); window.isReleasedWhenClosed = false; window.delegate = self; window.center()
        card = DropZoneView(frame:NSRect(x:0,y:0,width:320,height:76),forceLegacyMaterial:false,policy:policy)
        card.unregisterDraggedTypes()
        card.targetName = "PeerJetty"
        host = DropCardHost(card:card); host.frame.origin = NSPoint(x:68,y:105); window.contentView?.addSubview(host)
        let hint = NSTextField(wrappingLabelWithString:L10n.text("motion.preview_hint")); hint.frame = NSRect(x:24,y:260,width:472,height:40); window.contentView?.addSubview(hint)
        speeds.addItems(withTitles:AnimationSpeed.allCases.map(\.localizedTitle)); speeds.frame = NSRect(x:24,y:40,width:160,height:28); speeds.target = self; speeds.action = #selector(changeSpeed); window.contentView?.addSubview(speeds)
        observer = NotificationCenter.default.addObserver(forName:MotionPolicy.changed, object:MotionPolicy.shared, queue:.main) { [weak self] _ in
            guard let self else { return }
            self.policy.enabled = MotionPolicy.shared.enabled
            if !self.policy.allowed {
                MotionEffects.clear(self.host)
                NSAnimationContext.runAnimationGroup { context in context.duration = 0; self.host.animator().alphaValue = self.hiding ? 0 : 1 }
            }
        }
        let replay = NSButton(title:L10n.text("motion.replay"),target:self,action:#selector(play)); replay.bezelStyle = .rounded; replay.frame = NSRect(x:376,y:40,width:120,height:28); window.contentView?.addSubview(replay)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }
    func present() {
        policy.speed = MotionPolicy.shared.speed; policy.enabled = MotionPolicy.shared.enabled
        speeds.selectItem(at:AnimationSpeed.allCases.firstIndex(of:policy.speed) ?? 1)
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); play()
    }
    @objc private func changeSpeed() { policy.speed = AnimationSpeed.allCases[speeds.indexOfSelectedItem]; play() }
    @objc private func play() {
        generation += 1; hiding = false; let token = generation, id = UUID()
        MotionEffects.clear(host); host.alphaValue = 1; card.idle(); host.layoutSubtreeIfNeeded()
        if policy.allowed { MotionEffects.cardAppear(host,duration:policy.profile.cardAppear) }
        card.onSuccessFinished = { [weak self] _,hold in
            guard let self, self.generation == token else { return }
            DispatchQueue.main.asyncAfter(deadline:.now()+hold) { [weak self] in
                guard let self, self.generation == token else { return }
                self.hiding = true
                NSAnimationContext.runAnimationGroup { context in context.duration = self.policy.allowed ? self.policy.profile.dismiss : 0; context.timingFunction = MotionEffects.exit; self.host.animator().alphaValue = 0 } completionHandler: { [weak self] in
                    guard let self, self.generation == token else { return }; MotionEffects.clear(self.host)
                }
            }
        }
        for (delay,amount,finished) in [(0.6,Int64(15),false),(1.0,Int64(55),false),(1.4,Int64(100),false),(1.8,Int64(100),true)] {
            DispatchQueue.main.asyncAfter(deadline:.now()+delay) { [weak self] in
                guard let self, self.generation == token, self.window?.isVisible == true else { return }
                self.card.transfer(TransferUpdate(id:id,peerName:"PeerJetty",receiving:false,completed:amount,total:100,status:L10n.text(finished ? "peerengine.saved_by_the_other_mac" : "peerengine.sending"),finished:finished,succeeded:finished))
            }
        }
    }
    func windowWillClose(_ notification:Notification) { generation += 1; card.progress.reset(); MotionEffects.clear(host) }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
