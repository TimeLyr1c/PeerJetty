import AppKit
import PeerCore
import Darwin

/// A test-only entrypoint around the real AppDelegate, updater and UI. No production startup.
@main struct ActualAppUpdate {
    static var timer:Timer?
    static var clicked=Set<String>()
    static var waitingSince:Date?
    static var resumed=false
    static var app:AppDelegate?
    static var root:URL!
    static func main() {
        setbuf(stdout,nil)
        AppDelegate.isolatedStartup={delegate in
            app=delegate
            do {try start(delegate)} catch {finish("FAIL: \(error)")}
        }
        AppDelegate.main()
    }
    static func finish(_ message:String) {
        try? message.write(to:root.appendingPathComponent("result.txt"),atomically:true,encoding:.utf8)
        timer?.invalidate();NSApp.terminate(nil)
    }
    static func buttons(_ view:NSView)->[NSButton] {
        (view as? NSButton).map{[$0]} ?? view.subviews.flatMap(buttons)
    }
    static func start(_ delegate:AppDelegate) throws {
        root=URL(fileURLWithPath:Bundle.main.object(forInfoDictionaryKey:"FixtureRoot") as! String)
        let identity=try DeviceIdentity.isolated(at:root.appendingPathComponent("identity.json"))
        let store=try ConfigurationStore(url:root.appendingPathComponent("config.json"),fallback:Configuration(name:"Isolated",receivePath:root.path))
        let historyURL=root.appendingPathComponent("history/history.sqlite")
        if Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String == "1001" {
            let expected=try String(contentsOf:root.appendingPathComponent("fingerprint.txt"),encoding:.utf8)
            precondition(identity.fingerprint == expected,"persisted disposable identity changed")
            precondition(store.snapshot.peers.first?.id == "fixture-peer" && store.snapshot.preferredPeer == "fixture-peer")
            precondition(store.snapshot.showMenuBarIcon == false && store.snapshot.showDockIcon == true)
            let entries=try TextHistory(url:historyURL).list(retention:.forever)
            precondition(entries.count == 2 && entries.contains{$0.text == "confirmed before update 🙂"})
            precondition(FileManager.default.fileExists(atPath:root.appendingPathComponent("wait-observed.txt").path))
            finish("PASS: actual PeerJetty AppDelegate + native Sparkle UI + signed DMG download/replacement/relaunch; waited for delayed SQLite; disposable identity, pairing/default, icon preferences and original text history preserved")
            return
        }
        try identity.fingerprint.write(to:root.appendingPathComponent("fingerprint.txt"),atomically:true,encoding:.utf8)
        try store.update {$0.peers=[TrustedPeer(id:"fixture-peer",name:"Paired fixture")];$0.preferredPeer="fixture-peer";$0.showMenuBarIcon=false;$0.showDockIcon=true;$0.textRetention = .forever}
        let history=try TextHistory(url:historyURL)
        try history.add(TextEntry(messageID:UUID(),direction:.received,peerID:"fixture-peer",peerName:"Fixture",text:"existing history"),retention:.forever)
        try delegate.configureUpdateFixture(store:store,identity:identity,historyURL:historyURL)
        delegate.fixtureSuspendHistory()
        delegate.fixtureSave(TextEntry(messageID:UUID(),direction:.sent,peerID:"fixture-peer",peerName:"Fixture",text:"confirmed before update 🙂")) {_,saved in precondition(saved)}
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) {_ in
            guard let app else {return}
            if app.fixtureReadiness.waiting {
                if waitingSince == nil {
                    waitingSince=Date()
                    precondition(!app.fixtureReadiness.historyWrites.isEmpty)
                    try? "actual wait visible".write(to:root.appendingPathComponent("wait-observed.txt"),atomically:true,encoding:.utf8)
                }
                if !resumed,Date().timeIntervalSince(waitingSince!)>1.2 {resumed=true;app.fixtureResumeHistory()}
            }
            for window in NSApp.windows where window.isVisible {
                for button in buttons(window.contentView ?? NSView()) where button.isEnabled {
                    if ["Install Update","Install and Relaunch"].contains(button.title),clicked.insert(button.title).inserted {
                        print("Fixture clicks native button:",button.title);button.performClick(nil)
                    }
                }
            }
        }
        delegate.fixtureCheckUpdates()
    }
}
