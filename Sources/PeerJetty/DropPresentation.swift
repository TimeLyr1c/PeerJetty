import AppKit
import PeerCore

/// All rectangles are in AppKit's global screen coordinates, in points.
struct DropScreenMetrics {
    let frame: NSRect
    let visibleFrame: NSRect
    let safeTop: CGFloat
    let leftArea: NSRect?
    let rightArea: NSRect?
    let scale: CGFloat

    init(frame: NSRect, visibleFrame: NSRect, safeTop: CGFloat = 0,
         leftArea: NSRect? = nil, rightArea: NSRect? = nil, scale: CGFloat = 1) {
        self.frame = frame; self.visibleFrame = visibleFrame; self.safeTop = safeTop
        self.leftArea = leftArea; self.rightArea = rightArea; self.scale = max(1, scale)
    }

    init(_ screen: NSScreen) {
        self.init(frame: screen.frame, visibleFrame: screen.visibleFrame,
                  safeTop: screen.safeAreaInsets.top, leftArea: screen.auxiliaryTopLeftArea,
                  rightArea: screen.auxiliaryTopRightArea, scale: screen.backingScaleFactor)
    }
}

struct DropPresentation {
    let card: NSRect
    let trigger: NSRect
    let retention: NSRect
    let notch: NSRect?

    init(_ screen: DropScreenMetrics, size: NSSize? = nil) {
        let frame = screen.frame
        // A top inset alone is not enough: use both auxiliary areas and validate
        // the intervening gap, rather than guessing from a Mac model name.
        if screen.safeTop > 0, let left = screen.leftArea, let right = screen.rightArea,
           left.maxX >= frame.minX, right.minX <= frame.maxX,
           right.minX > left.maxX, left.maxY > frame.maxY - screen.safeTop,
           right.maxY > frame.maxY - screen.safeTop {
            notch = NSRect(x: left.maxX, y: frame.maxY - screen.safeTop,
                           width: right.minX - left.maxX, height: screen.safeTop)
        } else { notch = nil }
        let center = notch?.midX ?? frame.midX
        let width = min(size?.width ?? max(320, (notch?.width ?? 0) + 64), max(1, frame.width - 24))
        let x = min(max(frame.minX + 12, center - width / 2), frame.maxX - width - 12)
        let reservedTop = max(0, screen.safeTop, frame.maxY - screen.visibleFrame.maxY)
        // Keep the entire target away from the physical edge and menu bar,
        // including on displays whose menu bar automatically hides.
        let top = frame.maxY - max(64, reservedTop + 12)
        let snap: (CGFloat) -> CGFloat = { ($0 * screen.scale).rounded() / screen.scale }
        card = NSRect(x: snap(x), y: snap(top - (size?.height ?? 76)), width: snap(width), height: size?.height ?? 76)
        // Activate below the menu bar, before reaching the card. The card
        // appears at its final position immediately, so the drag can enter it
        // without passing through macOS's top-edge/Spaces gesture region.
        trigger = NSRect(x: card.minX - 24, y: card.minY - 48,
                         width: card.width + 48, height: card.height + 48).intersection(frame)
        // Exit hysteresis surrounds the approach area and card, but the
        // physical edge is not an additional activation route.
        retention = trigger.insetBy(dx: -16, dy: -16).intersection(frame)
    }
}

/// A stale drag pasteboard must not turn a later ordinary mouse drag into a
/// file drag. Consume the pasteboard generation when the mouse is released.
struct FileDragTracker {
    private(set) var handled: Int
    private var pressedBefore = false
    private var origin = NSPoint.zero
    private(set) var active = false

    init(changeCount: Int) { handled = changeCount }

    mutating func update(pressed: Bool, location: NSPoint, changeCount: Int, acceptsFiles: Bool) -> Bool {
        if pressed, !pressedBefore { origin = location }
        if pressed, !active, changeCount != handled, acceptsFiles,
           hypot(location.x - origin.x, location.y - origin.y) >= 4 {
            active = true; handled = changeCount
        }
        if !pressed, pressedBefore { active = false; handled = changeCount }
        pressedBefore = pressed
        return active
    }
}


/// Main-thread feedback ownership for preparation/connection failures, independent of animation.
struct FileSendFeedback {
    private(set) var latestID:UUID?
    private(set) var pendingIDs=Set<UUID>()
    private(set) var failedID:UUID?
    var allowsIdle:Bool {pendingIDs.isEmpty && latestID == nil && failedID == nil}
    mutating func begin(_ id:UUID) {latestID=id;pendingIDs.insert(id);failedID=nil}
    mutating func accept(_ event:FileSendEvent) -> Bool {
        if event.phase == .started || event.phase == .failed {pendingIDs.remove(event.id)}
        guard latestID == event.id else {return false}
        if event.phase == .started {latestID=nil;failedID=nil}
        if event.phase == .failed {latestID=nil;failedID=event.id}
        return true
    }
    mutating func transferStarted() {latestID=nil;failedID=nil}
    mutating func transferFailed(_ id:UUID) {if latestID == nil {failedID=id}}
    mutating func clearFailure() {failedID=nil}
}

/// Stable identity-based layout; frozen for the lifetime of one drag.
struct DropTargets {
    let peers: [DiscoveredPeer]
    let preferred: String?
    let overflow: Bool
    init(_ peers: [DiscoveredPeer], preferred: String?) {
        let paired = peers.filter(\.paired).sorted {
            if ($0.id == preferred) != ($1.id == preferred) { return $0.id == preferred }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id < $1.id
        }
        self.peers = Array(paired.prefix(6)); self.preferred = preferred; overflow = paired.count > 6
    }
    var size: NSSize? {
        guard peers.count > 1 else { return nil }
        let columns = min(3,peers.count), rows = (peers.count + columns - 1) / columns
        return NSSize(width:24 + columns * 170 + (columns - 1) * 8, height:24 + rows * 76 + (rows - 1) * 8 + (overflow ? 24 : 0))
    }
    func rect(_ index: Int, width: CGFloat, statusHeight: CGFloat = 0) -> NSRect {
        let columns = min(3,peers.count), rows = (peers.count + columns - 1) / columns
        let cell = (width - 24 - CGFloat(columns - 1)*8)/CGFloat(columns)
        return NSRect(x:12+CGFloat(index % columns)*(cell+8),y:statusHeight + (overflow ? 24 : 0) + 12+CGFloat(rows-1-index/columns)*84,width:cell,height:76)
    }
}
