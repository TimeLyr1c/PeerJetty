import AppKit
import Network
import SQLite3
@testable import PeerCore

func check(_ ok: Bool, _ description: String) { if !ok { fputs("FAIL: \(description)\n",stderr); exit(1) } }
func rejects(_ description: String, _ body: () throws -> Void) { do { try body(); check(false,description) } catch {} }
func pump(_ until: () -> Bool, timeout: Double = 6) { let end = Date().addingTimeInterval(timeout); while !until(), Date() < end { RunLoop.main.run(until:Date().addingTimeInterval(0.02)) }; check(until(),"async deadline") }

func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
func settle(_ window: NSWindow) {
    window.displayIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    window.contentView!.layoutSubtreeIfNeeded(); window.displayIfNeeded()
}
func layoutCheck(_ window: NSWindow, _ size: NSSize) {
    window.setContentSize(size); settle(window)
    let root = window.contentView!, stack = root.subviews.compactMap { $0 as? NSStackView }.first!
    check(abs(root.bounds.width-size.width)<1 && abs(root.bounds.height-size.height)<1,"requested content size")
    for row in stack.arrangedSubviews {
        let rect = root.convert(row.bounds, from:row)
        check(rect.minX >= -1 && rect.maxX <= size.width+1 && rect.minY >= -1 && rect.maxY <= size.height+1,"layout rows within window")
        for button in descendants(row).compactMap({$0 as? NSButton}) {
            if !(button is NSPopUpButton) { check(button.bounds.width >= button.intrinsicContentSize.width-1,"native buttons not compressed") }
        }
    }
}
func button(_ window: NSWindow, _ title: String) -> NSButton {
    descendants(window.contentView!).compactMap {$0 as? NSButton}.first {$0.title == L10n.text(title)}!
}

@main struct TextTests {
static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PeerJetty-text-data-\(UUID())")
    let fm = FileManager.default; try fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? fm.removeItem(at:root) }
    let original = "  中文🙂\n\r\ne\u{301}\u{0}https://example.invalid  "
    try TextRules.validate(original); try TextRules.validate(" \n")
    try TextRules.validate(String(repeating:"🙂",count:65536))
    rejects("UTF8 boundary"){try TextRules.validate(String(repeating:"🙂",count:65536)+"a")}
    rejects("empty rejected"){try TextRules.validate("")}
    var message = Message("text"); message.transfer = UUID(); message.text = original
    let decoded = try JSONDecoder().decode(Message.self,from:JSONEncoder().encode(message))
    check(Data(decoded.text!.utf8) == Data(original.utf8),"JSON preserves original bytes and NUL")
    rejects("malformed UUID"){ _ = try JSONDecoder().decode(Message.self,from:Data(#"{"kind":"text","transfer":"invalid","text":"x"}"#.utf8)) }
    struct Legacy: Codable { let kind:String; let version:Int? }
    var hello = Message("hello"); hello.version = 1; hello.capabilities = ["text-v1"]
    check(try JSONDecoder().decode(Legacy.self,from:JSONEncoder().encode(hello)).version == 1,"legacy ignores optional capability")
    check(try JSONDecoder().decode(Message.self,from:JSONEncoder().encode(Legacy(kind:"hello",version:1))).capabilities == nil,"legacy missing capability")
    var inbox = TextInbox(); let id = UUID()
    check(try inbox.receive(id,text:original) == .new,"first arrival")
    check(try inbox.receive(id,text:original) == .pending,"pending duplicates not acknowledged")
    inbox.complete(id); check(try inbox.receive(id,text:original) == .duplicate,"completed duplicate")
    rejects("conflicting UUID"){_ = try inbox.receive(id,text:original+"x")}
    for _ in 0..<256 { let next = UUID(); _ = try inbox.receive(next,text:"x"); inbox.complete(next) }
    check(try inbox.receive(id,text:original) == .new,"bounded recent256 cache")
    print("PASS: UTF8 boundaries, raw JSON, legacy optional fields and duplicate protection")

    let config = Configuration(name:"Test",receivePath:root.path)
    var legacyConfig = try JSONSerialization.jsonObject(with:JSONEncoder().encode(config)) as! [String:Any]
    legacyConfig.removeValue(forKey:"showTextHistory"); legacyConfig.removeValue(forKey:"textRetention")
    let upgraded = try JSONDecoder().decode(Configuration.self,from:JSONSerialization.data(withJSONObject:legacyConfig))
    check(upgraded.showTextHistory && upgraded.textRetention == .latest500,"upgrade defaults")
    let url = root.appendingPathComponent("history/history.sqlite")
    var history: TextHistory? = try TextHistory(url:url)
    let entry = TextEntry(messageID:UUID(),direction:.received,peerID:"peer",peerName:"设备🙂",text:original)
    try history!.add(entry,retention:.forever)
    history = nil; history = try TextHistory(url:url)
    check(Data(try history!.get(entry.id,retention:.forever)!.text.utf8) == Data(original.utf8),"reopen preserves exact bytes")
    let duplicate = TextEntry(messageID:entry.messageID,direction:.received,peerID:"peer",peerName:"Renamed",text:original)
    check(try history!.add(duplicate,retention:.forever) == entry.id,"canonical ID after reconnection")
    rejects("same persisted UUID different body"){try history!.add(TextEntry(messageID:entry.messageID,direction:.received,peerID:"peer",peerName:"p",text:"changed"),retention:.forever)}
    for index in 0..<503 { try history!.add(TextEntry(messageID:UUID(),direction:index%2 == 0 ? .sent:.received,peerID:"peer",peerName:"p",date:Date().addingTimeInterval(Double(index)),text:"\(index)"),retention:.latest500) }
    check(try history!.list(retention:.latest500,limit:500).count == 500,"combined send+receive retention")
    check(try history!.get(entry.id,retention:.latest500) == nil,"expired notification target")
    let attrs = try fm.attributesOfItem(atPath:url.path); let dir = try fm.attributesOfItem(atPath:url.deletingLastPathComponent().path)
    check((attrs[.posixPermissions] as! NSNumber).intValue == 0o600 && (dir[.posixPermissions] as! NSNumber).intValue == 0o700,"private filesystem permissions")
    try history!.delete(); let old = TextEntry(messageID:UUID(),direction:.sent,peerID:"p",peerName:"p",date:Date().addingTimeInterval(-31*86400),text:"old")
    try history!.add(old,retention:.forever); try history!.add(entry,retention:.forever)
    check(try history!.list(retention:.forever).count == 2,"forever keeps old records")
    check(try history!.list(retention:.thirtyDays).count == 1,"30days pruned on view")
    try history!.delete()
    try history!.add(old,retention:.forever)
    let refreshed = TextEntry(messageID:old.messageID,direction:old.direction,peerID:old.peerID,peerName:old.peerName,text:old.text)
    let refreshedID = try history!.add(refreshed,retention:.thirtyDays)
    check(try history!.get(refreshedID,retention:.thirtyDays) != nil,"expired replay is viewable before receipt")
    try history!.delete(); try history!.add(entry,retention:.forever)
    try history!.delete(entry.id); check(try history!.get(entry.id,retention:.forever) == nil,"deleted notification target")
    var hidden = config; hidden.showTextHistory = false
    try history!.add(entry,retention:hidden.textRetention); check(try history!.list(retention:hidden.textRetention).count == 1,"visibility never disables recording")
    // Force a real SQL write failure without production data or filesystem tricks.
    var connection: OpaquePointer?; sqlite3_open(url.path,&connection)
    sqlite3_exec(connection,"CREATE TRIGGER fail_insert BEFORE INSERT ON entries BEGIN SELECT RAISE(ABORT,'simulated storage failure'); END",nil,nil,nil)
    rejects("SQL failure not reported as saved"){try history!.add(TextEntry(messageID:UUID(),direction:.sent,peerID:"p",peerName:"p",text:"not saved"),retention:.forever)}
    check(try history!.list(retention:.forever).count == 1,"transaction rollback")
    sqlite3_close(connection)
    let link = root.appendingPathComponent("linked.sqlite"); try fm.createSymbolicLink(at:link,withDestinationURL:url)
    rejects("symlink database refused"){_ = try TextHistory(url:link)}
    print("PASS: migration, SQLite reopen, 500/30day/forever, hiding, deletion, permissions, write failure")

    _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited); MotionPolicy.shared.enabled = false
    let composer = TextComposer(); let peer = DiscoveredPeer(id:"p",name:"Test",paired:true,connected:true,supportsText:true)
    composer.updatePeers([peer],preferred:"p"); composer.editor.string = original
    var sent = ""; let pending = UUID(); composer.onSend = { text,id in check(id == "p","temporary target"); sent = text; return pending }
    composer.sendText(); check(Data(sent.utf8) == Data(original.utf8),"composer doesn't transform text")
    check(!composer.editor.isEditable,"freeze submitted draft")
    composer.window?.close(); composer.result(pending,error:PeerError.localized("text.unconfirmed",[]))
    check(composer.editor.string == original && composer.editor.isEditable,"close/failure preserves draft")
    composer.sendText(); composer.result(pending,error:nil); check(composer.editor.string.isEmpty,"only acknowledged draft cleared")
    check(composer.window!.canBecomeKey,"panel accepts focus"); check(composer.window!.makeFirstResponder(composer.editor),"editor first responder")
    check(!composer.editor.isRichText && !composer.editor.isAutomaticLinkDetectionEnabled,"plain inert text")
    composer.editor.string = "Select me"; composer.editor.setSelectedRange(NSRange(location:0,length:0))
    let commandA = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:composer.window!.windowNumber,context:nil,characters:"a",charactersIgnoringModifiers:"a",isARepeat:false,keyCode:0)!
    composer.editor.keyDown(with:commandA)
    check(composer.editor.selectedRange().length == 9,"CmdA works without an application Edit menu")
    let shortcuts = ClipboardShortcutSpy()
    for (key,code) in [("c",8),("v",9),("x",7)] {
        let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:0,context:nil,characters:key,charactersIgnoringModifiers:key,isARepeat:false,keyCode:UInt16(code))!
        check(shortcuts.performKeyEquivalent(with:event),"standard edit shortcut handled")
    }
    check(shortcuts.copied && shortcuts.pasted && shortcuts.cutText,"CmdC/V/X use native copy, plain paste and cut actions")
    composer.editor.string = "before"; composer.editor.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:composer.window!.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!)
    check(composer.editor.string.contains("\n"),"Enter inserts newline")
    composer.editor.string = "keyboard"; composer.editor.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:composer.window!.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!)
    check(sent == "keyboard","CmdEnter sends")
    composer.result(pending,error:nil)
    composer.editor.string = "native equivalent"
    let commandReturn = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:composer.window!.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
    check(composer.editor.performKeyEquivalent(with:commandReturn) && sent == "native equivalent","native key-equivalent dispatch sends CmdEnter")
    composer.result(pending,error:nil)
    let alternative = DiscoveredPeer(id:"q",name:"Alternative",paired:true,connected:true,supportsText:true)
    composer.updatePeers([peer,alternative],preferred:"q",resetSelection:true)
    check(composer.selectedPeer?.id == "q","new empty composer follows current file target")
    composer.editor.string = "draft"; composer.updatePeers([peer,alternative],preferred:"p",resetSelection:true)
    check(composer.selectedPeer?.id == "q","unsent draft preserves temporary target")
    // Inspect resized controls without launching the production app.
    composer.window?.setContentSize(NSSize(width:450,height:300))
    layoutCheck(composer.window!, NSSize(width:450,height:300))
    check(composer.editor.font?.pointSize == 14 && composer.editor.textContainerInset == NSSize(width:14,height:14),"shared text style")
    composer.editor.string = ""; check(composer.editor.placeholder != nil && composer.editor.string.isEmpty,"placeholder never becomes message content")
    let board = NSPasteboard(name:NSPasteboard.Name("PeerJetty-text-copy-\(UUID())")); defer {board.releaseGlobally()}
    board.clearContents(); board.setString("existing clipboard",forType:.string)
    let copyReader = TextReader(entry:entry,pasteboard:board)
    check(board.string(forType:.string) == "existing clipboard","receiving never overwrites clipboard")
    button(copyReader.window!, "text.copy").performClick(nil)
    check(Data(board.string(forType:.string)!.utf8) == Data(original.utf8),"explicit Copy preserves original text")
    check(descendants(copyReader.window!.contentView!).compactMap {$0 as? NSTextField}.contains {$0.stringValue == L10n.text("text.copied")},"copy feedback")
    layoutCheck(copyReader.window!, NSSize(width:360,height:200))
    let failedReader = TextReader(entry:entry,saved:false,pasteboard:board)
    layoutCheck(failedReader.window!, NSSize(width:360,height:200))
    let warningLabel = descendants(failedReader.window!.contentView!).compactMap {$0 as? NSTextField}.first {$0.stringValue == L10n.text("text.history_failed")}!
    let warningHeight = (warningLabel.stringValue as NSString).boundingRect(with:NSSize(width:warningLabel.bounds.width,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:warningLabel.font!]).height
    check(warningLabel.bounds.height >= warningHeight-1,"history warning wraps without clipping")
    let longText = String(repeating:"中文🙂 Unicode e\u{301}\n",count:2000)
    let longReader = TextReader(entry:TextEntry(messageID:UUID(),direction:.received,peerID:"peer",peerName:String(repeating:"Long text 中文 Mac mini ",count:12),text:longText),pasteboard:board)
    settle(longReader.window!); check(longReader.window!.contentView!.bounds.size == NSSize(width:580,height:400),"long device name preserves default reader size")
    layoutCheck(longReader.window!,NSSize(width:360,height:200))
    let longBody = descendants(longReader.window!.contentView!).compactMap {$0 as? NSTextView}.first!
    check(longBody.string == longText && !longBody.isEditable && !longBody.isRichText,"long Unicode reader retains raw read-only content")
    button(longReader.window!,"text.copy").performClick(nil); check(board.string(forType:.string) == longText,"long text copy unchanged")
    let historyUI = TextHistoryWindow()
    check(historyUI.window!.styleMask.contains(.resizable),"history supports resizing")
    layoutCheck(historyUI.window!, NSSize(width:500,height:350))
    let table = descendants(historyUI.window!.contentView!).compactMap {$0 as? NSTableView}.first!
    let secondEntry = TextEntry(messageID:UUID(),direction:.sent,peerID:"peer",peerName:String(repeating:"Mac mini 中文 ",count:12),text:"Next steps for the project…\nMore Unicode 🙂")
    historyUI.update([entry,secondEntry]); table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
    var opened: UUID?, deleted: UUID?, cleared = false, loaded = -1
    historyUI.onOpen = {opened=$0}; historyUI.onDelete = {if let id=$0 {deleted=id} else {cleared=true}}; historyUI.onLoad = {loaded=$0}
    button(historyUI.window!,"text.view").performClick(nil); check(opened == secondEntry.id,"view selected ID")
    button(historyUI.window!,"text.delete").performClick(nil); check(deleted == secondEntry.id,"delete callback selected ID")
    historyUI.update([secondEntry,entry]); check(table.selectedRow == 0,"refresh preserves message ID selection")
    historyUI.update([entry]); check(table.selectedRow == -1 && !button(historyUI.window!,"text.view").isEnabled,"removed selection cleared")
    historyUI.update(Array(repeating:entry,count:100)); button(historyUI.window!,"text.next").performClick(nil); check(loaded == 100,"next page offset"); historyUI.update(Array(repeating:entry,count:100))
    button(historyUI.window!,"text.previous").performClick(nil); check(loaded == 0,"previous page offset")
    button(historyUI.window!,"text.clear").performClick(nil); check(cleared,"clear callback retains confirmation boundary")
    historyUI.update([])
    let empty = descendants(historyUI.window!.contentView!).first {$0.identifier?.rawValue == "textHistoryEmpty"}!
    check(!empty.isHidden && !button(historyUI.window!,"text.next").isEnabled,"empty history and pagination")
    historyUI.update([],error:PeerError.localized("text.history_failed",[])); check(empty.isHidden,"error distinct from empty history")
    for metrics in [
        DropScreenMetrics(frame:NSRect(x:0,y:0,width:800,height:480),visibleFrame:NSRect(x:0,y:40,width:800,height:416)),
        DropScreenMetrics(frame:NSRect(x:0,y:0,width:1440,height:900),visibleFrame:NSRect(x:0,y:0,width:1440,height:860),safeTop:40,leftArea:NSRect(x:0,y:860,width:620,height:40),rightArea:NSRect(x:820,y:860,width:620,height:40)),
        DropScreenMetrics(frame:NSRect(x:-1024,y:-100,width:1024,height:768),visibleFrame:NSRect(x:-984,y:-100,width:984,height:744))
    ] {
        let placement = TextPanelPlacement(metrics,decoration:28)
        check(placement.frame.maxY <= DropPresentation(metrics).card.maxY && metrics.visibleFrame.contains(placement.frame),"notch/non-notch/external panel below menu and within usable screen")
    }
    if let screen = NSScreen.screens.first(where: {$0.frame.contains(NSEvent.mouseLocation)}) ?? NSScreen.main {
        let drop = DropPanelController(); drop.busy = true; drop.show()
        check(drop.isVisible,"file progress visible before editor")
        drop.setEditingScreen(screen); check(!drop.isVisible,"busy file card never overlays input panel")
        drop.show(); check(!drop.isVisible,"parallel transfer updates respect editing screen")
        drop.setEditingScreen(nil); check(drop.isVisible,"closing editor restores active file progress")
        drop.setEditingScreen(screen)
    }
    let notice = textNotificationContent(id:entry.id,peerName:"Test",saved:true)
    check(!notice.body.contains(original) && notice.userInfo["textEntry"] as? String == entry.id.uuidString,"notification privacy and reference")
    let unsaved = textNotificationContent(id:entry.id,peerName:"Test",saved:false); check(unsaved.title != notice.title,"storage failure warning")
    composer.editor.string = ""; composer.editor.setMarkedText("zhong",selectedRange:NSRange(location:5,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
    check(composer.editor.hasMarkedText(),"input-method composition is active")
    let beforeComposition = sent
    check(!composer.editor.performKeyEquivalent(with:commandReturn) && composer.editor.hasMarkedText() && sent == beforeComposition,"key-equivalent route leaves unfinished composition to the input method")
    composer.editor.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:composer.window!.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!)
    check(sent == beforeComposition,"CmdEnter does not send unfinished composition"); composer.editor.unmarkText()
    composer.window?.orderFront(nil)
    var closed = false; composer.onVisibility = {screen in if screen == nil {closed=true}}
    composer.editor.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:composer.window!.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!)
    check(closed,"Escape closes panel")
    if let index = CommandLine.arguments.firstIndex(of:"--snapshots"), CommandLine.arguments.count > index+1 {
        let output = URL(fileURLWithPath:CommandLine.arguments[index+1]); try fm.createDirectory(at:output,withIntermediateDirectories:true)
        func snapshot(_ window:NSWindow,_ name:String,_ dark:Bool=false) throws {
            window.appearance = NSAppearance(named:dark ? .darkAqua : .aqua); settle(window)
            let content = window.contentView!.superview ?? window.contentView!
            let bitmap = content.bitmapImageRepForCachingDisplay(in:content.bounds)!; content.cacheDisplay(in:content.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
        }
        composer.editor.string=""; composer.updatePeers([peer,alternative],preferred:"p",resetSelection:true)
        button(composer.window!,"text.connect").performClick(nil)
        composer.editor.string="Hello from PeerJetty!\n你好，另一台 Mac。\n\nhttps://example.invalid stays plain text."
        try snapshot(composer.window!,"composer-small")
        composer.window?.setContentSize(NSSize(width:560,height:350)); try snapshot(composer.window!,"composer"); try snapshot(composer.window!,"composer-dark",true)
        composer.sendText(); try snapshot(composer.window!,"composer-waiting"); composer.result(pending,error:PeerError.localized("text.unconfirmed",[])); try snapshot(composer.window!,"composer-failure")
        composer.sendText(); composer.result(pending,error:nil); try snapshot(composer.window!,"composer-success")
        composer.editor.string=""; try snapshot(composer.window!,"composer-empty")
        composer.updatePeers([DiscoveredPeer(id:"p",name:secondEntry.peerName,paired:true,connected:true,supportsText:true)],preferred:"p",resetSelection:true)
        layoutCheck(composer.window!,NSSize(width:450,height:300)); try snapshot(composer.window!,"composer-long-device")
        historyUI.update([entry,secondEntry]); try snapshot(historyUI.window!,"history-small")
        historyUI.window?.setContentSize(NSSize(width:650,height:450)); try snapshot(historyUI.window!,"history"); table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false); try snapshot(historyUI.window!,"history-dark",true)
        historyUI.update([]); try snapshot(historyUI.window!,"history-empty")
        historyUI.update([],error:PeerError.localized("text.history_failed",[])); try snapshot(historyUI.window!,"history-failure")
        let longNameReader = TextReader(entry:secondEntry,pasteboard:board); try snapshot(longNameReader.window!,"reader-long-device")
        let reader = TextReader(entry:TextEntry(messageID:UUID(),direction:.received,peerID:"peer",peerName:"MacBook Air",text:"Hello from PeerJetty!\n你好，另一台 Mac。\n\nhttps://example.invalid stays plain text."),pasteboard:board)
        try snapshot(reader.window!,"reader"); try snapshot(reader.window!,"reader-dark",true)
        try snapshot(copyReader.window!,"reader-small"); try snapshot(failedReader.window!,"reader-unsaved-small")

    }
    print("PASS: native input, focus, Enter/CmdEnter, drafts, small layout and notification privacy")
    try adversarial(root:root)
    if !CommandLine.arguments.contains("--quick") { try integration(root:root) }
}
static func integration(root:URL) throws {
    let fm = FileManager.default
    let ar = root.appendingPathComponent("A"),br = root.appendingPathComponent("B")
    try fm.createDirectory(at:ar,withIntermediateDirectories:true); try fm.createDirectory(at:br,withIntermediateDirectories:true)
    let aStore = try ConfigurationStore(url:nil,fallback:Configuration(name:"A",receivePath:ar.path))
    let bStore = try ConfigurationStore(url:nil,fallback:Configuration(name:"B",receivePath:br.path))
    let aID = try DeviceIdentity.ephemeral(),bID = try DeviceIdentity.ephemeral()
    let a = PeerEngine(identity:aID,store:aStore), b = PeerEngine(identity:bID,store:bStore)
    defer { a.stop(); b.stop() }
    var ap: UInt16 = 0,bp: UInt16 = 0
    a.onListening = {ap=$0}; b.onListening = {bp=$0}
    a.onPairing = {id,_,_ in a.confirm(sessionID:id,approved:true)}
    b.onPairing = {id,_,_ in b.confirm(sessionID:id,approved:true)}
    a.start(discovery:false); b.start(discovery:false); pump({ap>0 && bp>0})
    var failures:[UUID:Error] = [:]; var successes:Set<UUID> = []
    a.onTextResult = { value,error in if let error {failures[value.id]=error} else {successes.insert(value.id)} }
    b.onTextResult = { value,error in if let error {failures[value.id]=error} else {successes.insert(value.id)} }
    let unauthorized = a.sendText("no trust",peerID:bID.fingerprint); pump({failures[unauthorized] != nil}); check(successes.isEmpty,"unauthorized send rejected")
    a.openPairing(); b.openPairing(); a.connect(host:"127.0.0.1",port:bp)
    var ready = false
    a.onPeers = { peers in ready = peers.contains { $0.id==bID.fingerprint && $0.supportsText == true } }
    pump({ready && aStore.snapshot.peers.count==1 && bStore.snapshot.peers.count==1}); a.closePairing(); b.closePairing()
    let unicode = " 中文🙂\n\r\n\u{0}  "
    var received:[TextPayload] = []; var receipts:[UUID:()->Void] = [:]
    b.onTextReceived = { value,ack in received.append(value); receipts[value.id]=ack }
    a.onTextReceived = { value,ack in received.append(value); ack() }
    let first = a.sendText(unicode,peerID:bID.fingerprint); pump({receipts[first] != nil})
    check(!successes.contains(first),"no success before receiver marks viewable")
    let second = a.sendText("second",peerID:bID.fingerprint)
    RunLoop.main.run(until:Date().addingTimeInterval(0.15)); check(received.count==1,"one active text per connection")
    receipts[first]!(); pump({receipts[second] != nil && successes.contains(first)}); receipts[second]!(); pump({successes.contains(second)})
    check(Data(received[0].text.utf8)==Data(unicode.utf8),"TLS preserves Unicode/newlines/NUL")
    let back = b.sendText("reverse",peerID:aID.fingerprint); pump({successes.contains(back)})
    let file = root.appendingPathComponent("payload.bin"); let bytes = Data(repeating:42,count:1024*1024); try bytes.write(to:file)
    var fileDone=false; b.onReceived = {_,urls in check((try? Data(contentsOf:urls[0])) == bytes,"parallel file integrity"); fileDone=true}
    a.send(urls:[file],peerID:bID.fingerprint)
    let concurrent = a.sendText("parallel",peerID:bID.fingerprint); pump({receipts[concurrent] != nil}); receipts[concurrent]!(); pump({fileDone && successes.contains(concurrent)})
    // Full queue: one active plus twenty waiting. Timeout is intentionally tested at the real 30-second deadline.
    let stalled = a.sendText("unconfirmed",peerID:bID.fingerprint); pump({receipts[stalled] != nil})
    var queued:[UUID]=[]; for _ in 0..<20 {queued.append(a.sendText("queued",peerID:bID.fingerprint))}
    let overflow = a.sendText("overflow",peerID:bID.fingerprint); pump({failures[overflow] != nil}); check(!successes.contains(stalled),"queue capacity")
    pump({failures[stalled] != nil},timeout:33)
    check(!successes.contains(stalled),"timeout not success and no retry")
    receipts[stalled]!() // A late ack must not acknowledge the next message.
    pump({receipts[queued[0]] != nil}); check(!successes.contains(queued[0]),"late receipt ignored")
    b.onTextReceived = {value,ack in received.append(value); ack()}
    receipts[queued[0]]!(); pump({queued.allSatisfy {successes.contains($0)}})
    check(received.filter {$0.id==stalled}.count==1,"timed-out message not resent")
    print("PASS: two ephemeral TLS peers, authorization, receipt ordering, bidirectional text, parallel file, queue20, real30s timeout, late receipt")
    // A peer with an actual missing hello field remains usable for files.
    let legacyStore = try ConfigurationStore(url:nil,fallback:Configuration(name:"Legacy",receivePath:br.path))
    let legacyID = try DeviceIdentity.ephemeral(); let legacy = PeerEngine(identity:legacyID,store:legacyStore)
    legacy.advertisedCapabilities = nil; var lp:UInt16=0; legacy.onListening={lp=$0}
    legacy.onPairing={id,_,_ in legacy.confirm(sessionID:id,approved:true)}
    legacy.start(discovery:false); defer {legacy.stop()}; pump({lp>0})
    a.openPairing(); legacy.openPairing(); a.connect(host:"127.0.0.1",port:lp)
    var oldReady=false; a.onPeers={peers in oldReady=peers.contains {$0.id==legacyID.fingerprint && $0.supportsText == false}}
    pump({oldReady}); let unsupported = a.sendText("unsupported",peerID:legacyID.fingerprint); pump({failures[unsupported] != nil})
    var oldFile=false; legacy.onReceived={_,_ in oldFile=true}; a.send(urls:[file],peerID:legacyID.fingerprint); pump({oldFile})
    check(!successes.contains(unsupported),"legacy never reports text success")
    print("PASS: legacy hello without capabilities refuses text and still transfers files")
}
static func adversarial(root:URL) throws {
    let remoteID = try DeviceIdentity.ephemeral(),localID = try DeviceIdentity.ephemeral()
    let store = try ConfigurationStore(url:nil,fallback:Configuration(name:"Receiver",receivePath:root.path))
    try store.update {$0.peers = [TrustedPeer(id:remoteID.fingerprint,name:"Raw")]}
    let rawStore = try ConfigurationStore(url:nil,fallback:Configuration(name:"Raw",receivePath:root.path))
    try rawStore.update {$0.peers = [TrustedPeer(id:localID.fingerprint,name:"Receiver")]}
    let engine = PeerEngine(identity:localID,store:store); var port:UInt16=0; engine.onListening={port=$0}
    engine.start(discovery:false); defer {engine.stop()}; pump({port>0})
    var deliveries=0; var ackCount=0
    engine.onTextReceived={_,ack in deliveries+=1; ack()}
    func client(premature:Bool = false) throws -> RawPeer {
        let peer = try RawPeer(identity:remoteID,store:rawStore,port:port,premature:premature)
        peer.onReceipt={_ in ackCount+=1}; peer.start(); pump({premature ? peer.closed:peer.ready}); return peer
    }
    let early = try client(premature:true); check(deliveries==0,"TLS alone grants no application text authority"); early.close()
    let raw = try client(); let id=UUID()
    raw.text(id,"original"); pump({deliveries==1 && ackCount==1})
    raw.text(id,"original"); pump({ackCount==2}); check(deliveries==1,"duplicate wire message not delivered twice")
    raw.text(id,"conflict"); pump({raw.closed}); check(deliveries==1,"conflicting body closes connection")
    let huge = try client(); huge.text(UUID(),String(repeating:"x",count:TextRules.maxBytes+1)); pump({huge.closed}); check(deliveries==1,"oversized inbound rejected")
    let boundary = try client(); boundary.text(UUID(),String(repeating:"🙂",count:65536)); pump({deliveries==2}); boundary.close()
    let wrong = try client(); var failed=false; engine.onTextResult={_,error in failed = error != nil}
    wrong.onText={_ in var receipt=Message("textReceipt"); receipt.transfer=UUID(); wrong.wire.send(receipt)}
    engine.sendText("must match receipt",peerID:remoteID.fingerprint); pump({wrong.closed && failed})
    check(deliveries==2,"unexpected receipt never reported success")
    print("PASS: raw TLS premature authority, duplicate/conflicting IDs, inbound UTF8 boundary, unmatched acknowledgement")
}

}

// Isolated protocol peer for adversarial wire-level checks, using only ephemeral identities.
private final class RawPeer {
    let wire: FramedConnection
    let identity: DeviceIdentity
    let nonce: Data
    var ready=false,closed=false
    var onReceipt: ((UUID)->Void)?
    var onText: ((UUID)->Void)?
    init(identity:DeviceIdentity,store:ConfigurationStore,port:UInt16,premature:Bool) throws {
        self.identity=identity; nonce=try DeviceIdentity.random(32)
        let parameters=TLS.parameters(identity:identity,store:store,gate:PairingGate(),queue:.main)
        wire=FramedConnection(NWConnection(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:port)!,using:parameters))
        wire.onFailure={ [weak self] _ in self?.closed=true }
        wire.connection.stateUpdateHandler={ [weak self] state in
            guard let self else {return}
            if case .ready = state {
                self.wire.begin()
                if premature {self.text(UUID(),"premature");return}
                var hello=Message("hello");hello.id=identity.fingerprint;hello.name="Raw";hello.version=1;hello.capabilities=["text-v1"]
                hello.commitment=PairingProof.commitment(id:identity.fingerprint,nonce:self.nonce);self.wire.send(hello)
            }
            if case .failed = state {self.closed=true}
        }
        wire.onMessage={ [weak self] message in
            guard let self else {return}
            switch message.kind {
            case "hello": var reveal=Message("reveal"); reveal.nonce=self.nonce; self.wire.send(reveal)
            case "reveal": self.wire.send(Message("confirm"))
            case "confirm": self.ready=true
            case "textReceipt": if let id=message.transfer {self.onReceipt?(id)}
            case "text": if let id=message.transfer {self.onText?(id)}
            default: break
            }
        }
    }
    func start(){wire.connection.start(queue:.main)}
    func close(){wire.close()}
    func text(_ id:UUID,_ body:String){var message=Message("text");message.transfer=id;message.text=body;wire.send(message)}
}

private final class ClipboardShortcutSpy: PlainTextView {
    var copied=false,pasted=false,cutText=false
    override func copy(_ sender:Any?) {copied=true}
    override func pasteAsPlainText(_ sender:Any?) {pasted=true}
    override func cut(_ sender:Any?) {cutText=true}
}
