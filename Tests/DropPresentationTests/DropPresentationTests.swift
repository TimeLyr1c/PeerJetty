import AppKit

private func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Expected true", file: file, line: line) }
private func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(!value, "Expected false", file: file, line: line) }
private func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { precondition(value == nil, "Expected nil", file: file, line: line) }
private func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) { precondition(actual == expected, "Values differ: \(actual), \(expected)", file: file, line: line) }
private func XCTAssertGreaterThan<T: Comparable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) { precondition(actual > expected, "Expected greater value", file: file, line: line) }

final class DropPresentationTests {
    func testDragTrackerRejectsStalePasteboardAndTextAndRequiresMovement() {
        var tracker = FileDragTracker(changeCount: 10)
        let origin = NSPoint(x: 500, y: 500), moved = NSPoint(x: 510, y: 500)
        XCTAssertFalse(tracker.update(pressed: true, location: origin, changeCount: 10, acceptsFiles: true))
        XCTAssertFalse(tracker.update(pressed: true, location: moved, changeCount: 10, acceptsFiles: true))
        XCTAssertFalse(tracker.update(pressed: false, location: moved, changeCount: 10, acceptsFiles: true))
        XCTAssertFalse(tracker.update(pressed: true, location: origin, changeCount: 11, acceptsFiles: false))
        XCTAssertFalse(tracker.update(pressed: true, location: moved, changeCount: 11, acceptsFiles: false))
        XCTAssertFalse(tracker.update(pressed: false, location: moved, changeCount: 11, acceptsFiles: false))
        XCTAssertFalse(tracker.update(pressed: true, location: origin, changeCount: 12, acceptsFiles: true))
        XCTAssertTrue(tracker.update(pressed: true, location: moved, changeCount: 12, acceptsFiles: true))
        XCTAssertFalse(tracker.update(pressed: false, location: moved, changeCount: 12, acceptsFiles: true))
        XCTAssertFalse(tracker.update(pressed: true, location: origin, changeCount: 12, acceptsFiles: true))
        XCTAssertFalse(tracker.update(pressed: true, location: moved, changeCount: 12, acceptsFiles: true))
    }
    func testPlainScreenTriggerUsesPhysicalEdgeButCardClearsMenuBar() {
        let screen = DropScreenMetrics(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                                       visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1056))
        let g = DropPresentation(screen)
        XCTAssertNil(g.notch)
        XCTAssertTrue(g.trigger.contains(NSPoint(x: 960, y: 1079)))
        XCTAssertFalse(g.trigger.contains(NSPoint(x: 300, y: 1079)))
        XCTAssertFalse(g.trigger.contains(NSPoint(x: 960, y: 500)))
        XCTAssertEqual(g.card.maxY, 1048)
        XCTAssertGreaterThan(g.hidden.minY, screen.frame.maxY)
        XCTAssertTrue(g.retention.contains(NSPoint(x: 960, y: 1060)))
        XCTAssertTrue(g.retention.contains(NSPoint(x: 960, y: g.card.midY)))
    }
    func testDifferentNotchWidthsAreMeasuredAndContentsStayBelowHousing() {
        for width: CGFloat in [180, 220, 300] {
            let screen = DropScreenMetrics(frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
                visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 950), safeTop: 32,
                leftArea: NSRect(x: 0, y: 950, width: 756 - width / 2, height: 32),
                rightArea: NSRect(x: 756 + width / 2, y: 950, width: 756 - width / 2, height: 32), scale: 2)
            let g = DropPresentation(screen)
            XCTAssertEqual(g.notch?.width, width)
            XCTAssertEqual(g.card.midX, 756)
            XCTAssertEqual(g.card.maxY, 942)
            XCTAssertTrue(g.trigger.contains(NSPoint(x: 756, y: 949)))
            XCTAssertTrue(g.retention.contains(NSPoint(x: 756, y: 943)))
        }
    }
    func testNegativeScreenOriginsAndHiddenMenuBar() {
        let screen = DropScreenMetrics(frame: NSRect(x: -1920, y: -200, width: 1920, height: 1080),
                                       visibleFrame: NSRect(x: -1920, y: -200, width: 1920, height: 1080), scale: 2)
        let g = DropPresentation(screen)
        XCTAssertEqual(g.card.midX, -960)
        XCTAssertEqual(g.card.maxY, 872)
        XCTAssertTrue(g.trigger.contains(NSPoint(x: -960, y: 879)))
        XCTAssertFalse(g.retention.contains(NSPoint(x: 100, y: 879)))
    }
    func testMissingOrInvalidNotchDataFallsBackWithoutPuttingContentInSafeInset() {
        let frame = NSRect(x: 400, y: 100, width: 1440, height: 900)
        for areas: (NSRect?, NSRect?) in [(nil, nil),
             (NSRect(x: 400, y: 970, width: 900, height: 30), NSRect(x: 1200, y: 970, width: 640, height: 30))] {
            let g = DropPresentation(DropScreenMetrics(frame: frame, visibleFrame: frame,
                safeTop: 30, leftArea: areas.0, rightArea: areas.1))
            XCTAssertNil(g.notch)
            XCTAssertEqual(g.card.midX, frame.midX)
            XCTAssertEqual(g.card.maxY, 962)
        }
    }
}

@main
struct RunDropPresentationTests {
    static func main() throws {
        let tests = DropPresentationTests()
        tests.testDragTrackerRejectsStalePasteboardAndTextAndRequiresMovement()
        tests.testPlainScreenTriggerUsesPhysicalEdgeButCardClearsMenuBar()
        tests.testDifferentNotchWidthsAreMeasuredAndContentsStayBelowHousing()
        tests.testNegativeScreenOriginsAndHiddenMenuBar()
        tests.testMissingOrInvalidNotchDataFallsBackWithoutPuttingContentInSafeInset()
        print("PASS: drag session checks and 4 screen geometry groups")
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let board = NSPasteboard.withUniqueName()
        board.setString("ordinary text", forType: .string)
        XCTAssertFalse(DragPayload.accepts(board))
        board.clearContents()
        board.writeObjects([NSURL(fileURLWithPath: "/isolated-test/example.txt")])
        XCTAssertTrue(DragPayload.accepts(board))
        board.releaseGlobally()
        print("PASS: isolated pasteboard rejects text and accepts file URLs")
        for (index, screen) in NSScreen.screens.enumerated() {
            let g = DropPresentation(DropScreenMetrics(screen))
            print("Screen \(index + 1): safe top \(screen.safeAreaInsets.top), notch width \(g.notch?.width ?? 0), card \(g.card)")
        }
        // Instantiate only the view, never the production app/engine/identity.
        let view = DropZoneView(frame: NSRect(x: 0, y: 0, width: 320, height: 76))
        view.targetName = "Test Mac"; view.idle(); view.layoutSubtreeIfNeeded()
        for child in view.subviews {
            XCTAssertTrue(view.bounds.contains(child.frame))
        }
        XCTAssertEqual(view.layer?.cornerRadius, 16)
        XCTAssertEqual(view.layer?.masksToBounds, true)
        print("PASS: card layout and full corner clipping")
        if CommandLine.arguments.count == 2 {
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
            print("Card snapshot saved")
        }
    }
}
