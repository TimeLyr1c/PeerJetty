import AppKit
import PeerCore
import SQLite3
import Darwin

func check(_ value:Bool,_ label:String) {precondition(value,label)}
func pump(_ done:()->Bool,seconds:Double=3) {
    let end=Date().addingTimeInterval(seconds)
    while !done() && Date()<end {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
    check(done(),"timed out")
}
func modelTests() {
    var gate=UpdateReadiness();gate.begin()
    let first=gate.arm()!,second=gate.arm()!
    check(!gate.accept(first),"old idle callback rejected after re-arm")
    check(gate.accept(second),"latest idle accepted")
    check(!gate.claimInstallation(otherWork:true),"pending-to-active handoff stays busy")
    check(gate.claimInstallation(otherWork:false),"idle installs")
    check(!gate.claimInstallation(otherWork:false),"authorization exactly once")
    gate.cancel();gate.begin();check(!gate.accept(second),"prior session rejected")
    let current=gate.arm()!;gate.accept(current)
    let id=UUID();gate.beginPromise(id,peer:"a")
    check(!gate.claimInstallation(otherWork:false),"outstanding promise blocks")
    let write=gate.beginHistory();gate.endPromise(id)
    check(!gate.claimInstallation(otherWork:false),"history blocks")
    gate.cancel();check(gate.historyWrites.contains(write),"cancel preserves real work")
    gate.begin();gate.accept(gate.arm()!);gate.endHistory(write)
    check(gate.claimInstallation(otherWork:false),"retry succeeds after work ends")
    print("PASS: session/check generations, handoff, promises, history, cancel/retry and one-shot authorization")
}
@main struct UpdateReadinessTests {
    static func main() throws {
        setbuf(stdout,nil)
        _=NSApplication.shared;NSApp.setActivationPolicy(.accessory);modelTests()
        let root=URL(fileURLWithPath:CommandLine.arguments[1]);let identity=try DeviceIdentity.ephemeral()
        func app(_ name:String) throws -> (AppDelegate,URL) {
            let history=root.appendingPathComponent(name+"/history.sqlite")
            var config=Configuration(name:"Fixture",receivePath:root.path)
            config.peers=[TrustedPeer(id:"fixture",name:"Fixture")]
            let value=AppDelegate();try value.configureUpdateFixture(store:ConfigurationStore(url:nil,fallback:config),identity:identity,historyURL:history)
            return (value,history)
        }
        let (delayed,url)=try app("delayed")
        delayed.fixtureSuspendHistory();var stored=false,allowed=false
        let entry=TextEntry(messageID:UUID(),direction:.sent,peerID:"fixture",peerName:"Fixture",text:"Unicode 原文\n🙂")
        delayed.fixtureSave(entry) {_,saved in stored=saved}
        delayed.fixtureBeginUpdate {allowed=$0}
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        check(!allowed && !stored && delayed.fixtureReadiness.waiting,"actual AppDelegate waits for SQLite and completion")
        delayed.fixtureResumeHistory();pump({allowed && stored})
        check(try TextHistory(url:url).get(entry.id,retention:.forever)?.text == entry.text,"committed original text before authorization")
        delayed.fixtureCancelUpdate()
        print("PASS: actual AppDelegate waits for delayed real SQLite write and main-thread result")

        let (failed,failedURL)=try app("failed");var connection:OpaquePointer?
        sqlite3_open(failedURL.path,&connection)
        check(sqlite3_exec(connection,"CREATE TRIGGER fail_insert BEFORE INSERT ON entries BEGIN SELECT RAISE(ABORT,'fixture'); END",nil,nil,nil)==SQLITE_OK,"fault injection")
        sqlite3_close(connection)
        failed.fixtureSuspendHistory();var result:Bool?,savedResult:Bool?
        failed.fixtureSave(entry) {_,saved in savedResult=saved}
        failed.fixtureBeginUpdate {result=$0};failed.fixtureResumeHistory();pump({result != nil && savedResult != nil})
        check(result == false && savedResult == false && !failed.fixtureReadiness.blocksNewWork,"history failure cancels installation and restores admission")
        check(failed.fixtureStatus == L10n.text("text.history_failed"),"explicit storage failure")
        check(failed.fixtureVolatileText(entry.id) == entry.text,"unsaved original text remains available for copying")
        print("PASS: actual SQLite failure cancels update, retains volatile text and restores admission")

        let (mixed,_)=try app("mixed")
        let view=DropZoneView(frame:NSRect(x:0,y:0,width:320,height:76))
        let peer=DiscoveredPeer(id:"fixture",name:"Fixture",paired:true,connected:false)
        view.updateTargets([peer],preferred:peer.id)
        view.onReceivingPromise={id,target in mixed.fixturePromise(id,peer:target!)}
        view.onTargetFiles={urls,peer,source,cleanup in mixed.fixtureDrop(urls,peer:peer,source:source,cleanup:cleanup)}
        view.onPromiseFailure={id,text in mixed.fixturePromiseFailed(id,text:text)}
        let tracker=view.trackPromise(receivers:1,target:peer.id,cleanup:{})
        let promise=mixed.fixtureReadiness.promises.keys.first!
        let file=root.appendingPathComponent("file.txt");try "fixture".write(to:file,atomically:true,encoding:.utf8)
        view.deliver([file],target:peer.id,cleanup:nil)
        check(mixed.fixtureReadiness.promises[promise] == "fixture","ordinary drop cannot finish another promise")
        var mixedResult:Bool?;mixed.fixtureBeginUpdate {mixedResult=$0}
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        check(mixedResult == nil,"original promise continues blocking")
        var rejectedCleanup=false
        view.deliver([file],target:peer.id,cleanup:{rejectedCleanup=true})
        check(rejectedCleanup && mixed.fixtureReadiness.promises[promise] == peer.id,"ordinary drop cannot borrow promise admission during update")
        tracker.expect(receiver:0,count:1);tracker.record(receiver:0,url:file,error:nil)
        pump({mixed.fixtureReadiness.promises.isEmpty})
        pump({mixedResult != nil});check(mixedResult == true,"promise preparation failure drains safely")
        mixed.fixtureCancelUpdate()
        for mode in ["cancel","failure","revoked"] {
            view.updateTargets([peer],preferred:peer.id)
            let pending=view.trackPromise(receivers:1,target:peer.id,cleanup:{})
            let id=mixed.fixtureReadiness.promises.keys.first!
            if mode == "revoked" {view.updateTargets([],preferred:nil)}
            else if mode == "failure" {pending.expect(receiver:0,count:1);pending.record(receiver:0,url:file,error:PeerError.message("fixture failure"))}
            else {pending.cancel()}
            pump({mixed.fixtureReadiness.promises[id] == nil})
            if mode == "revoked" {check(mixed.fixtureStatus == L10n.text("targets.revoked"),"revocation retains explicit reason")}
            pending.cancel();pending.record(receiver:0,url:file,error:nil)
            check(mixed.fixtureReadiness.promises[id] == nil,"late callbacks cannot revive work")
        }
        print("PASS: real promise tracker cancellation/timeout path, failure, target revocation and late callbacks")
        view.updateTargets([peer],preferred:peer.id)
        let pending=view.trackPromise(receivers:1,target:peer.id,cleanup:{})
        let activeID=UUID();var cancelled:UUID?
        view.onCancel={cancelled=$0}
        view.transfer(TransferUpdate(id:activeID,peerName:"Fixture",receiving:false,completed:1,total:10,status:"Sending",finished:false,succeeded:false))
        func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
        let cancel=descendants(view).compactMap{$0 as? NSButton}.first{$0.identifier?.rawValue == "cancelCardTransfer"}!
        cancel.performClick(nil)
        check(cancelled == activeID && !pending.wasCancelled,"active file cancel cannot cancel a different pending promise")
        pending.cancel();pump({mixed.fixtureReadiness.promises.isEmpty})
        check(!cancel.isHidden,"ending a promise preserves an unrelated active cancel button")
        let started=UUID();mixed.fixtureFileEvent(FileSendEvent(id:started,peerID:"fixture",peerName:"Fixture",phase:.started))
        check(mixed.fixtureActive.contains(started),"started task registered before pending removal")
        print("PASS: actual drop handler isolates ordinary/promise origin, drains handoff and registers activity")
        NSApp.windows.forEach{$0.orderOut(nil)}
    }
}
