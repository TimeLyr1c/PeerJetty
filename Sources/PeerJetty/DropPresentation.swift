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
        // Keep the entire target away from the physical edge and menu bar,
        // including on displays whose menu bar automatically hides.
        let top = frame.maxY - max(64, reservedTop + 12)
        let snap: (CGFloat) -> CGFloat = { ($0 * screen.scale).rounded() / screen.scale }
        card = NSRect(x: snap(x), y: snap(top - 76), width: snap(width), height: 76)
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
