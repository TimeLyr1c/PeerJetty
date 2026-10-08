func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
import AppKit
import PeerCore

private func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Expected true", file: file, line: line) }
private func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(!value, "Expected false", file: file, line: line) }
private func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { precondition(value == nil, "Expected nil", file: file, line: line) }
private func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) { precondition(actual == expected, "Values differ: \(actual), \(expected)", file: file, line: line) }

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
    func testPlainScreenApproachTriggersBeforeCardWithoutEnteringSystemEdge() {
        let screen = DropScreenMetrics(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                                       visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1056))
        let g = DropPresentation(screen)
        XCTAssertNil(g.notch)
        XCTAssertFalse(g.trigger.contains(NSPoint(x: 960, y: 1079)))
        XCTAssertFalse(g.trigger.contains(NSPoint(x: 960, y: 1050)))
        XCTAssertTrue(g.trigger.contains(NSPoint(x: 960, y: 920)))
        XCTAssertTrue(g.trigger.contains(NSPoint(x: 960, y: g.card.midY)))
        XCTAssertFalse(g.trigger.contains(NSPoint(x: 300, y: 1079)))
        XCTAssertFalse(g.trigger.contains(NSPoint(x: 960, y: 500)))
        XCTAssertEqual(g.card.maxY, 1016)
        XCTAssertFalse(g.retention.contains(NSPoint(x: 960, y: 1060)))
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
            XCTAssertEqual(g.card.maxY, 918)
            XCTAssertFalse(g.trigger.contains(NSPoint(x: 756, y: 949)))
            XCTAssertTrue(g.trigger.contains(NSPoint(x: 756, y: 810)))
            XCTAssertTrue(g.retention.contains(NSPoint(x: 756, y: g.card.midY)))
        }
    }
    func testNegativeScreenOriginsAndHiddenMenuBar() {
        let screen = DropScreenMetrics(frame: NSRect(x: -1920, y: -200, width: 1920, height: 1080),
                                       visibleFrame: NSRect(x: -1920, y: -200, width: 1920, height: 1080), scale: 2)
        let g = DropPresentation(screen)
        XCTAssertEqual(g.card.midX, -960)
        XCTAssertEqual(g.card.maxY, 816)
        XCTAssertFalse(g.trigger.contains(NSPoint(x: -960, y: 879)))
        XCTAssertTrue(g.trigger.contains(NSPoint(x: -960, y: 705)))
        XCTAssertFalse(g.retention.contains(NSPoint(x: 100, y: 879)))
    }
    func testUpwardApproachPrecedesCardAndMenuWithOrWithoutNotch() {
        for safeTop: CGFloat in [0, 32, 48, 72] {
            let frame = NSRect(x: -800, y: 200, width: 1600, height: 1000)
            let metrics = DropScreenMetrics(frame: frame,
                visibleFrame: NSRect(x: -800, y: 200, width: 1600, height: 1000 - safeTop),
                safeTop: safeTop, scale: 2)
            let g = DropPresentation(metrics)
            let path = stride(from: frame.maxY - 250, through: frame.maxY - 1, by: 25)
            let first = path.map { NSPoint(x: frame.midX, y: $0) }.first { g.trigger.contains($0) }
            XCTAssertTrue(first != nil)
            XCTAssertTrue(first!.y < g.card.minY)
            XCTAssertTrue(frame.maxY - first!.y >= 140)
            XCTAssertTrue(g.card.maxY <= frame.maxY - 64)
            XCTAssertFalse(g.trigger.contains(NSPoint(x: frame.midX, y: frame.maxY - 10)))
            XCTAssertTrue(g.retention.contains(first!))
            XCTAssertTrue(g.retention.contains(NSPoint(x: g.card.midX, y: g.card.midY)))
        }
    }
    func testMissingOrInvalidNotchDataFallsBackWithoutPuttingContentInSafeInset() {
        let frame = NSRect(x: 400, y: 100, width: 1440, height: 900)
        for areas: (NSRect?, NSRect?) in [(nil, nil),
             (NSRect(x: 400, y: 970, width: 900, height: 30), NSRect(x: 1200, y: 970, width: 640, height: 30))] {
            let g = DropPresentation(DropScreenMetrics(frame: frame, visibleFrame: frame,
                safeTop: 30, leftArea: areas.0, rightArea: areas.1))
            XCTAssertNil(g.notch)
            XCTAssertEqual(g.card.midX, frame.midX)
            XCTAssertEqual(g.card.maxY, 936)
        }
    }
}

@main
struct RunDropPresentationTests {
    static func main() throws {
        let tests = DropPresentationTests()
        tests.testDragTrackerRejectsStalePasteboardAndTextAndRequiresMovement()
        tests.testPlainScreenApproachTriggersBeforeCardWithoutEnteringSystemEdge()
        tests.testDifferentNotchWidthsAreMeasuredAndContentsStayBelowHousing()
        tests.testNegativeScreenOriginsAndHiddenMenuBar()
        tests.testUpwardApproachPrecedesCardAndMenuWithOrWithoutNotch()
        tests.testMissingOrInvalidNotchDataFallsBackWithoutPuttingContentInSafeInset()
        print("PASS: drag session checks and 5 screen geometry/path groups")
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
        if #available(macOS 26.0, *) {
            XCTAssertEqual((view.subviews.first as? NSGlassEffectView)?.cornerRadius, 16)
        } else { XCTAssertEqual(view.subviews.first?.layer?.cornerRadius, 16); XCTAssertEqual(view.subviews.first?.layer?.masksToBounds, true) }
        print("PASS: card layout and full corner clipping")
        let labels = descendants(view).compactMap { $0 as? NSTextField }
        let title = labels[0], subtitle = labels[1]
        let progress = descendants(view).compactMap { $0 as? NSProgressIndicator }.first!
        let cancel = descendants(view).compactMap { $0 as? NSButton }.first!
        let icon = descendants(view).compactMap { $0 as? NSImageView }.first!
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        let snapshot = CommandLine.arguments.count == 2 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil
        for language in ["en", "zh-Hans"] {
            let catalog = TranslationCatalog(preferences: [language])
            let peer = language == "en" ? "Mac mini — Shared workspace upstairs — Design and development machine" : "Mac mini — 楼上共享工作空间的设计与开发电脑"
            for width: CGFloat in [320, 364] {
                view.setFrameSize(NSSize(width: width, height: 76))
                for state in ["idle", "hover", "loading", "transfer", "success", "failure"] {
                    let key: String
                    switch state {
                    case "hover": key = "dropzone.release_to_send"
                    case "loading": key = "dropzone.reading_files"
                    default: key = "dropzone.drop_into_card_to_send"
                    }
                    let message: String
                    if state == "success" { message = language == "en" ? "Files received" : "文件已收到" }
                    else if state == "failure" { message = language == "en" ? "Transfer failed" : "传输失败" }
                    else if state == "transfer" { message = language == "en" ? "Sending files…" : "正在发送文件…" }
                    else { message = catalog.text(key) }
                    view.show(title: message, subtitle: peer)
                    // Exercise the same visibility combinations used by transfer and file promises.
                    progress.isHidden = state != "transfer"
                    cancel.isHidden = state != "transfer" && state != "loading"
                    cancel.title = catalog.text("dropzone.cancel")
                    progress.doubleValue = 0.45
                    view.layoutSubtreeIfNeeded()
                    let group = title.frame.union(subtitle.frame)
                    XCTAssertEqual(group.midY, progress.isHidden ? view.bounds.midY : (20 + view.bounds.height - 12) / 2)
                    XCTAssertEqual(icon.frame.midY, group.midY)
                    XCTAssertTrue(title.frame.minY >= subtitle.frame.maxY + 4)
                    XCTAssertTrue(title.fittingSize.height <= title.frame.height)
                    XCTAssertTrue(subtitle.fittingSize.height <= subtitle.frame.height)
                    XCTAssertEqual(subtitle.toolTip, peer)
                    for child in view.subviews where !child.isHidden { XCTAssertTrue(view.bounds.contains(child.frame)) }
                    if !progress.isHidden { XCTAssertTrue(subtitle.frame.minY >= progress.frame.maxY + 5) }
                    if !cancel.isHidden {
                        XCTAssertEqual(cancel.frame.midY, title.frame.midY)
                        XCTAssertTrue(cancel.frame.minX >= title.frame.maxX + 12)
                        XCTAssertFalse(cancel.frame.intersects(subtitle.frame))
                    }
                    if let snapshot, width == 320 {
                        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
                        let name = snapshot.deletingPathExtension().lastPathComponent
                        let destination = snapshot.deletingLastPathComponent().appendingPathComponent("\(name)-\(language)-\(state).png")
                        try data.write(to: destination)
                        if language == "en", state == "idle" { try data.write(to: snapshot) }
                    }
                }
            }
        }
        print("PASS: bilingual card centering, text fit, long-name tooltips and controls across 24 layouts")
    }
}
