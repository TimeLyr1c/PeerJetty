import AppKit

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
    let hidden: NSRect
    let trigger: NSRect
    let retention: NSRect
    let notch: NSRect?

    init(_ screen: DropScreenMetrics) {
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
        let width = min(max(320, (notch?.width ?? 0) + 64), max(1, frame.width - 24))
        let x = min(max(frame.minX + 12, center - width / 2), frame.maxX - width - 12)
        let reservedTop = max(0, screen.safeTop, frame.maxY - screen.visibleFrame.maxY)
        let top = frame.maxY - reservedTop - 8
        let snap: (CGFloat) -> CGFloat = { ($0 * screen.scale).rounded() / screen.scale }
        card = NSRect(x: snap(x), y: snap(top - 76), width: snap(width), height: 76)
        hidden = NSRect(x: card.minX, y: frame.maxY + 2, width: card.width, height: card.height)
        let triggerWidth = min(card.width, max(180, (notch?.width ?? 0) + 48))
        // Both the physical edge and the accessible area immediately below a
        // real notch activate the card. This also covers a hidden menu bar.
        trigger = NSRect(x: snap(center - triggerWidth / 2),
                         y: frame.maxY - max(18, screen.safeTop + 12),
                         width: triggerWidth, height: max(18, screen.safeTop + 12))
        // Keep the card open while moving from the edge, through the menu bar
        // and gap, into the card. Wider margins provide exit hysteresis.
        retention = NSRect(x: card.minX - 20, y: card.minY - 20,
                           width: card.width + 40, height: frame.maxY - card.minY + 20)
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
