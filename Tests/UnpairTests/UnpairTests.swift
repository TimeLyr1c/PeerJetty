import Foundation
import Network
@testable import PeerCore

func check(_ value:Bool,_ message:String) { if !value { fputs("FAIL: \(message)\n",stderr); exit(1) } }
func pump(_ done:()->Bool,timeout:Double=8) {
    let deadline = Date().addingTimeInterval(timeout)
    while !done(), Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.02)) }
    check(done(),"async deadline")
}
final class RawUnpairPeer {
    let identity:DeviceIdentity, nonce:Data, wire:FramedConnection
    var ready=false,closed=false
    var control:((Message)->Void)?
    init(identity:DeviceIdentity,store:ConfigurationStore,port:UInt16,legacy:Bool=false,premature:Bool=false) throws {
        self.identity=identity; nonce=try DeviceIdentity.random(32)
        let params=TLS.parameters(identity:identity,store:store,gate:PairingGate(),queue:.main)
        wire=FramedConnection(NWConnection(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:port)!,using:params))
        wire.onFailure={ [weak self] _ in self?.closed=true }
        wire.connection.stateUpdateHandler={ [weak self] state in
            guard let self else {return}
            if case .failed = state {self.closed=true}
            if case .ready = state {
                self.wire.begin()
                if premature { self.send("unpair",id:identity.fingerprint,request:UUID()); return }
                var hello=Message("hello");hello.id=identity.fingerprint;hello.name="Raw";hello.version=1
                hello.capabilities=legacy ? nil : ["unpair-v1","text-v1"]
                hello.commitment=PairingProof.commitment(id:identity.fingerprint,nonce:self.nonce);self.wire.send(hello)
            }
        }
        wire.onMessage={ [weak self] message in
            guard let self else {return}
            switch message.kind {
            case "hello": var reveal=Message("reveal");reveal.nonce=self.nonce;self.wire.send(reveal)
            case "reveal": self.wire.send(Message("confirm"))
            case "confirm": self.ready=true
            default:self.control?(message)
            }
        }
        wire.connection.start(queue:.main)
    }
    func send(_ kind:String,id:String,request:UUID) { var m=Message(kind);m.id=id;m.transfer=request;wire.send(m) }
}
@main struct UnpairTests {
    static func main() throws {
        let fm=FileManager.default, root=fm.temporaryDirectory.appendingPathComponent("PeerJetty-unpair-\(UUID())")
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? fm.removeItem(at:root)}
        for mode in ["legacy","timeout","wrongID","premature","wrongAck","receiverSaveFailure","localSaveFailure"] {
            let local=try DeviceIdentity.ephemeral(),remote=try DeviceIdentity.ephemeral()
            let directory=root.appendingPathComponent(mode), configURL=directory.appendingPathComponent("config.json")
            let store=try ConfigurationStore(url:configURL,fallback:Configuration(name:"Local",receivePath:root.path))
            try store.update {$0.peers=[TrustedPeer(id:remote.fingerprint,name:"Remote")];$0.preferredPeer=remote.fingerprint}
            let remoteStore=try ConfigurationStore(url:nil,fallback:Configuration(name:"Remote",receivePath:root.path))
            try remoteStore.update {$0.peers=[TrustedPeer(id:local.fingerprint,name:"Local")]}
            let engine=PeerEngine(identity:local,store:store);var port:UInt16=0, events:[Bool]=[],statuses:[String]=[]
            engine.onListening={port=$0};engine.onUnpaired={_,_,_,confirmed in events.append(confirmed)};engine.onStatus={statuses.append($0)}
            engine.start(discovery:false);pump({port>0})
            let raw=try RawUnpairPeer(identity:remote,store:remoteStore,port:port,legacy:mode=="legacy",premature:mode=="premature")
            if mode=="premature" {
                pump({raw.closed});check(store.snapshot.peers.count==1 && events.isEmpty,"unauthorized request cannot revoke trust")
            } else {
                pump({raw.ready})
                if mode=="receiverSaveFailure" || mode=="localSaveFailure" {
                    try fm.moveItem(at:directory,to:root.appendingPathComponent(mode+"-saved"))
                    try Data("blocked".utf8).write(to:directory)
                }
                switch mode {
                case "wrongID": raw.send("unpair",id:local.fingerprint,request:UUID());pump({raw.closed});check(store.snapshot.peers.count==1,"request cannot target another identity")
                case "receiverSaveFailure":
                    var receipt:Message?;raw.control={receipt=$0};raw.send("unpair",id:remote.fingerprint,request:UUID())
                    pump({receipt != nil});check(receipt?.errorKey != nil && store.snapshot.peers.count==1 && events.isEmpty,"failed persistence cannot acknowledge remote unpair success")
                case "localSaveFailure":
                    var requests=0;raw.control={_ in requests+=1};engine.forget(remote.fingerprint)
                    pump({statuses.contains { $0.contains("blocked") || $0.contains("file") || $0.contains("文件") }})
                    check(store.snapshot.peers.count==1 && events.isEmpty && requests==0,"failed local persistence does not notify or revoke")
                default:
                    if mode=="wrongAck" { raw.control={m in if m.kind=="unpair" {raw.send("unpairReceipt",id:remote.fingerprint,request:UUID())}} }
                    var rejectedText=false,unexpectedTexts=0
                    if mode=="timeout" {
                        raw.control={m in if m.kind=="text" {unexpectedTexts+=1}}
                        engine.onTextResult={_,error in rejectedText=error != nil}
                    }
                    engine.forget(remote.fingerprint)
                    if mode=="timeout" {engine.sendText("must not send after revocation",peerID:remote.fingerprint)}
                    pump({!events.isEmpty})
                    if mode=="timeout" {check(rejectedText && unexpectedTexts==0,"revoking control connection cannot send new text")}
                    check(events==[false] && store.snapshot.peers.isEmpty,"\(mode) does not claim confirmed remote deletion")
                }
            }
            raw.wire.close();engine.stop();RunLoop.main.run(until:Date().addingTimeInterval(0.1))
            print("PASS: unpair \(mode)")
        }
        let offlineID=try DeviceIdentity.ephemeral(),absentID=try DeviceIdentity.ephemeral()
        let offlineStore=try ConfigurationStore(url:nil,fallback:Configuration(name:"Offline",receivePath:root.path))
        try offlineStore.update {$0.peers=[TrustedPeer(id:absentID.fingerprint,name:"Absent")];$0.preferredPeer=absentID.fingerprint}
        let offline=PeerEngine(identity:offlineID,store:offlineStore);var offlineEvent:Bool?
        offline.onUnpaired={_,_,_,confirmed in offlineEvent=confirmed};offline.forget(absentID.fingerprint)
        pump({offlineEvent != nil});check(offlineEvent==false && offlineStore.snapshot.peers.isEmpty && offlineStore.snapshot.preferredPeer==nil,"offline unpair deletes only local trust and default")
        print("PASS: offline unpair is explicitly unconfirmed")
        try cancellationChecks(root:root)
        // Two real engines: acknowledgement comes after the receiving store commits.
        let aID=try DeviceIdentity.ephemeral(),bID=try DeviceIdentity.ephemeral()
        let aStore=try ConfigurationStore(url:nil,fallback:Configuration(name:"A",receivePath:root.path))
        let bStore=try ConfigurationStore(url:nil,fallback:Configuration(name:"B",receivePath:root.path))
        try aStore.update {$0.peers=[TrustedPeer(id:bID.fingerprint,name:"B")]}
        try bStore.update {$0.peers=[TrustedPeer(id:aID.fingerprint,name:"A")]}
        let a=PeerEngine(identity:aID,store:aStore),b=PeerEngine(identity:bID,store:bStore)
        var port:UInt16=0,connected=false,confirmed=false,received=false
        b.onListening={port=$0};a.onPeers={connected=$0.contains {$0.id==bID.fingerprint && $0.connected}}
        a.onUnpaired={_,_,remote,ok in confirmed = !remote && ok};b.onUnpaired={_,_,remote,ok in received=remote && ok}
        a.start(discovery:false);b.start(discovery:false);pump({port>0});a.connect(host:"127.0.0.1",port:port);pump({connected})
        b.stop();pump({!connected});check(aStore.snapshot.peers.count==1 && bStore.snapshot.peers.count==1,"ordinary disconnect preserves trust")
        b.start(discovery:false);port=0;pump({port>0});a.connect(host:"127.0.0.1",port:port);pump({connected})
        var revoking=false,abortedA=false,abortedB=false
        a.onTransfer={u in if u.finished && !u.succeeded {abortedA=true}}
        b.onTransfer={u in
            if u.receiving && !u.finished && !revoking {revoking=true;a.forget(bID.fingerprint)}
            if u.finished && !u.succeeded {abortedB=true}
        }
        a.send(urls:[root.appendingPathComponent("cancel-large.bin")],peerID:bID.fingerprint)
        pump({confirmed && received && abortedA && abortedB})
        check(aStore.snapshot.peers.isEmpty && bStore.snapshot.peers.isEmpty,"both stores committed before success")
        a.stop();b.stop();print("PASS: disconnect vs authenticated bilateral revocation")
    }
}


private func cancellationChecks(root:URL) throws {
    let fm=FileManager.default
    let payload=root.appendingPathComponent("cancel-large.bin"),followup=root.appendingPathComponent("after-cancel.txt")
    try Data(repeating:42,count:64*1024*1024).write(to:payload)
    try Data("after cancellation".utf8).write(to:followup)
    for receiverCancels in [false,true] {
        let ar=root.appendingPathComponent("cancel-A-\(receiverCancels)"),br=root.appendingPathComponent("cancel-B-\(receiverCancels)")
        try fm.createDirectory(at:ar,withIntermediateDirectories:true);try fm.createDirectory(at:br,withIntermediateDirectories:true)
        let aid=try DeviceIdentity.ephemeral(),bid=try DeviceIdentity.ephemeral()
        let sa=try ConfigurationStore(url:nil,fallback:Configuration(name:"A",receivePath:ar.path)),sb=try ConfigurationStore(url:nil,fallback:Configuration(name:"B",receivePath:br.path))
        try sa.update {$0.peers=[TrustedPeer(id:bid.fingerprint,name:"B")]};try sb.update {$0.peers=[TrustedPeer(id:aid.fingerprint,name:"A")]}
        let a=PeerEngine(identity:aid,store:sa),b=PeerEngine(identity:bid,store:sb)
        var port:UInt16=0,connected=false,target:UUID?,incomingA=false,incomingB=false,cancelled=false,failures=Set<UUID>(),reverseDone=false,nextDone=false
        a.onPeers={connected=$0.contains {$0.id==bid.fingerprint && $0.connected}};b.onListening={port=$0}
        let cancelIfReady = {
            if let target, incomingA && incomingB && !cancelled {
                cancelled=true;(receiverCancels ? b : a).cancel(transferID:target)
            }
        }
        a.onTransfer={u in
            if !u.receiving && target==nil {target=u.id}
            if u.receiving && !u.finished {incomingA=true}
            if u.finished && !u.succeeded {failures.insert(u.id)}
            cancelIfReady()
        }
        b.onTransfer={u in if u.receiving && !u.finished {incomingB=true};cancelIfReady()}
        a.onReceived={_,urls in
            check((try? Data(contentsOf:urls[0])) == Data(repeating:42,count:64*1024*1024),"reverse transfer retains byte integrity")
            reverseDone=true
        }
        b.onReceived={_,urls in
            check(urls[0].lastPathComponent==followup.lastPathComponent,"cancelled payload must not commit")
            check((try? Data(contentsOf:urls[0]))==Data("after cancellation".utf8),"follow-up integrity")
            nextDone=true
        }
        a.start(discovery:false);b.start(discovery:false);pump({port>0});a.connect(host:"127.0.0.1",port:port);pump({connected})
        a.send(urls:[payload],peerID:bid.fingerprint);b.send(urls:[payload],peerID:aid.fingerprint)
        pump({cancelled && target.map {failures.contains($0)}==true && reverseDone},timeout:15)
        a.send(urls:[followup],peerID:bid.fingerprint);pump({nextDone})
        check(connected && sa.snapshot.peers.count==1 && sb.snapshot.peers.count==1,"task cancellation leaves connection/trust intact")
        check(!(try fm.contentsOfDirectory(atPath:br.path)).contains {$0.hasPrefix(".PeerJetty-Partial")},"cancelled staging cleaned")
        a.stop();b.stop();RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        print("PASS: \(receiverCancels ? "receiver" : "sender") task cancellation preserves reverse and follow-up transfers")
    }
}
