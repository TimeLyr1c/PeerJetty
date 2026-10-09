import Foundation
import Network
import Darwin
@testable import PeerCore

private func check(_ condition:Bool,_ text:String) {if !condition {fputs("FAIL: \(text)\n",stderr);exit(1)}}
private func pump(_ done:()->Bool,timeout:Double=8) {
    let end=Date().addingTimeInterval(timeout)
    while !done() && Date()<end {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
    check(done(),"async deadline")
}
@main struct ConnectionChecks {
    static func main() throws {
        if CommandLine.arguments.contains("--worker") {try worker();return}
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("PeerJetty-connection-\(UUID())")
        try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer {try? fm.removeItem(at:root)}
        try eofChecks()
        let file=root.appendingPathComponent("fixture.txt");try Data("Fixture 中文\n".utf8).write(to:file)
        try startup(root:root)
        try requests(root:root,file:file)
        try processExit(root:root,file:file)
    }
    static func startup(root:URL) throws {
        let aid=try DeviceIdentity.ephemeral(),bid=try DeviceIdentity.ephemeral()
        var config=Configuration(name:"Startup A",receivePath:root.path)
        config.peers=[TrustedPeer(id:bid.fingerprint,name:"Startup B"),TrustedPeer(id:"another",name:"Default")]
        config.preferredPeer="another";config.lastConnectedPeer=bid.fingerprint
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(config)) as! [String:Any]
        legacy.removeValue(forKey:"lastConnectedPeer");legacy.removeValue(forKey:"autoConnectLastPeer")
        let upgraded=try JSONDecoder().decode(Configuration.self,from:JSONSerialization.data(withJSONObject:legacy))
        check(upgraded.autoConnectLastPeer && upgraded.lastConnectedPeer == nil,"legacy auto-connect default with no guessed last peer")
        let location=root.appendingPathComponent("startup-config/configuration.json")
        let sa=try ConfigurationStore(url:location,fallback:config)
        try sa.update {_ in}
        let sb=try ConfigurationStore(url:nil,fallback:Configuration(name:"Startup B",receivePath:root.path))
        try sb.update {$0.peers=[TrustedPeer(id:aid.fingerprint,name:"Startup A")]}
        let a=PeerEngine(identity:aid,store:sa),b=PeerEngine(identity:bid,store:sb)
        var connected=false,port:UInt16=0,files=0,texts=0,statuses:[String]=[]
        a.onPeers={connected=$0.contains {$0.id==bid.fingerprint && $0.connected}}
        a.onStatus={statuses.append($0)};b.onListening={port=$0}
        b.onReceived={_,_ in files+=1};b.onTextReceived={_,ack in texts+=1;ack()}
        defer {a.stop();b.stop()}
        b.start(discovery:false);pump({port>0});a.start(discovery:false)
        a.testingEndpoint(peerID:bid.fingerprint,port:port);pump({connected})
        check(files==0 && texts==0 && sa.snapshot.preferredPeer=="another","startup connects without sending or changing default")
        let reopened=try ConfigurationStore(url:location,fallback:upgraded)
        check(reopened.snapshot.lastConnectedPeer==bid.fingerprint,"successful authorized peer persisted")
        try sa.update {$0.autoConnectLastPeer=false};a.autoConnectPreferenceChanged()
        RunLoop.main.run(until:Date().addingTimeInterval(0.1));check(connected,"disabling does not interrupt established transport")
        a.stop();pump({!connected});a.start(discovery:false)
        a.testingEndpoint(peerID:bid.fingerprint,port:port);RunLoop.main.run(until:Date().addingTimeInterval(0.3))
        check(!connected,"disabled startup does not connect")
        try sa.update {$0.autoConnectLastPeer=true};a.autoConnectPreferenceChanged();pump({connected})
        a.forget(bid.fingerprint);pump({sa.snapshot.lastConnectedPeer == nil && !connected})
        check(sa.snapshot.preferredPeer=="another","unpair clears last peer but preserves other default")
        a.stop();b.stop();RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        try sa.update {$0.lastConnectedPeer=bid.fingerprint}
        a.start(discovery:false);a.testingEndpoint(peerID:bid.fingerprint,port:port)
        RunLoop.main.run(until:Date().addingTimeInterval(0.2));check(!connected,"untrusted remembered ID is ignored")
        a.stop();RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        try sa.update {$0.peers.append(TrustedPeer(id:bid.fingerprint,name:"Startup B"))}
        try sb.update {$0.peers=[TrustedPeer(id:aid.fingerprint,name:"Startup A")]}
        let listener=try NWListener(using:TLS.parameters(identity:bid,store:sb,gate:PairingGate(),queue:.main),on:.any)
        var stalledPort:UInt16=0,accepted=0,closed=0,held:[NWConnection]=[]
        listener.stateUpdateHandler={if case .ready=$0 {stalledPort=listener.port!.rawValue}}
        func drain(_ c:NWConnection) {
            c.receive(minimumIncompleteLength:1,maximumLength:4096) {_,_,ended,error in
                if ended || error != nil {closed+=1} else {drain(c)}
            }
        }
        listener.newConnectionHandler={c in accepted+=1;held.append(c);c.start(queue:.main);drain(c)}
        listener.start(queue:.main);pump({stalledPort>0})
        defer {listener.cancel();held.forEach {$0.cancel()}}
        statuses=[];a.start(discovery:false)
        a.testingEndpoint(peerID:bid.fingerprint,port:stalledPort)
        pump({accepted==1})
        RunLoop.main.run(until:Date().addingTimeInterval(5.2))
        check(closed==1 && !connected && !statuses.contains(L10n.text("file.connection_timeout")),"automatic timeout is quiet and disconnected")
        a.testingEndpoint(peerID:bid.fingerprint,port:stalledPort)
        RunLoop.main.run(until:Date().addingTimeInterval(0.2));check(accepted==1,"unchanged discovery does not retry")
        a.testingRemoveEndpoint(peerID:bid.fingerprint);a.testingEndpoint(peerID:bid.fingerprint,port:stalledPort);pump({accepted==2})
        RunLoop.main.run(until:Date().addingTimeInterval(5.2));check(closed==2,"second automatic attempt also closes by deadline")
        a.testingRemoveEndpoint(peerID:bid.fingerprint);a.testingEndpoint(peerID:bid.fingerprint,port:stalledPort)
        RunLoop.main.run(until:Date().addingTimeInterval(0.2));check(accepted==2,"automatic attempt budget is two per startup")
        try sa.update {$0.autoConnectLastPeer=false};a.autoConnectPreferenceChanged()
        a.testingRemoveEndpoint(peerID:bid.fingerprint);a.testingEndpoint(peerID:bid.fingerprint,port:stalledPort)
        RunLoop.main.run(until:Date().addingTimeInterval(0.2));check(accepted==2,"disabled retry stops pending attempt")
        print("PASS: startup trusted TLS, persisted last/default separation, migration, toggle, unpair, quiet five-second timeout and bounded reappearance retry")
    }
    static func eofChecks() throws {
        for size in [0,3,4] {
            let wire=FramedConnection(NWConnection(host:"127.0.0.1",port:1,using:.tcp));var order:[String]=[]
            wire.onFailure={_ in order.append("closed")}
            wire.acceptReadResult(Data(repeating:1,count:size),isComplete:true,error:nil,count:4,accumulated:Data()) {_ in order.append("data")}
            check(order == (size==4 ? ["data","closed"] : ["closed"]),"full final data processed before EOF; partial frame fails")
        }
        let wire=FramedConnection(NWConnection(host:"127.0.0.1",port:1,using:.tcp));var order:[String]=[]
        wire.onFailure={_ in order.append("error")}
        wire.acceptReadResult(Data(repeating:1,count:4),isComplete:false,error:NWError.posix(.ECONNRESET),count:4,accumulated:Data()) {_ in order.append("data")}
        check(order == ["data","error"],"full final data precedes transport error")
        print("PASS: complete/partial/empty EOF and terminal-data ordering")
    }
    static func requests(root:URL,file:URL) throws {
        let aid=try DeviceIdentity.ephemeral(),bid=try DeviceIdentity.ephemeral()
        let sa=try ConfigurationStore(url:nil,fallback:Configuration(name:"A",receivePath:root.path))
        let br=root.appendingPathComponent("B");try FileManager.default.createDirectory(at:br,withIntermediateDirectories:true)
        let sb=try ConfigurationStore(url:nil,fallback:Configuration(name:"B",receivePath:br.path))
        try sa.update {$0.peers=[TrustedPeer(id:bid.fingerprint,name:"B")];$0.preferredPeer=bid.fingerprint}
        try sb.update {$0.peers=[TrustedPeer(id:aid.fingerprint,name:"A")];$0.preferredPeer=aid.fingerprint}
        let a=PeerEngine(identity:aid,store:sa),b=PeerEngine(identity:bid,store:sb)
        defer {a.stop();b.stop()}
        var events:[FileSendEvent]=[],connected=false,port:UInt16=0,received=0,unpaired=0,connections=0
        a.onFileSendEvent={events.append($0)};a.onPeers={connected=$0.contains {$0.id==bid.fingerprint && $0.connected}}
        a.onUnpaired={_,_,_,_ in unpaired+=1};b.onListening={port=$0};b.onReceived={_,urls in check((try? Data(contentsOf:urls[0]))==Data("Fixture 中文\n".utf8),"file integrity after restart");received+=1}
        a.onStatus={if $0==L10n.text("peerengine.connected","B") {connections+=1}}
        a.start(discovery:false)
        let absent=a.send(urls:[file],peerID:bid.fingerprint)
        pump({events.contains {$0.id==absent && $0.phase == .failed}})
        check(events.last?.notConnected==true && !connected,"no endpoint gives request-scoped disconnected result")
        var cleaned=0
        let bad=a.send(urls:[root.appendingPathComponent("missing")],peerID:bid.fingerprint,cleanup:{cleaned+=1})
        pump({events.contains {$0.id==bad && $0.phase == .failed}})
        check(events.last?.notConnected==false && cleaned==1,"preparation failure has ID and cleans source once")
        b.start(discovery:false);pump({port>0});a.testingEndpoint(peerID:bid.fingerprint,port:port)
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        check(!connected,"discovery does not imply connection")
        let reconnect=a.send(urls:[file],peerID:bid.fingerprint)
        pump({received==1 && connected})
        check(events.contains {$0.id==reconnect && $0.phase == .connecting} && events.contains {$0.id==reconnect && $0.phase == .started},"automatic send connection reuses request ID")
        a.connect(host:"127.0.0.1",port:port);pump({connections>=2})
        a.testingWaiting(peerID:bid.fingerprint);RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        check(connected,"one failed/waiting connection leaves other valid connection visible")
        a.testingWaiting(peerID:bid.fingerprint);pump({!connected})
        check(sa.snapshot.peers.count==1 && sa.snapshot.preferredPeer==bid.fingerprint && unpaired==0,"waiting ends connections, not trust")
        b.stop();RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        let stale=a.send(urls:[file],peerID:bid.fingerprint)
        pump({events.contains {$0.id==stale && $0.phase == .failed}})
        check(events.last?.notConnected==true && !connected,"stale endpoint failure ends request")
        port=0;b.start(discovery:false);pump({port>0});a.testingEndpoint(peerID:bid.fingerprint,port:port)
        RunLoop.main.run(until:Date().addingTimeInterval(0.3));check(received==1,"failed requests are not replayed on restart")
        a.send(urls:[file],peerID:bid.fingerprint);pump({received==2 && connected})
        print("PASS: no endpoint, preparation, discovery, automatic reconnect, multi-session/waiting, stale address and no offline replay")
        b.stop();pump({!connected});check(sa.snapshot.peers.count==1 && unpaired==0,"normal service stop retains trust")
        // Real TLS listener that intentionally never completes application hello/authorization.
        let params=TLS.parameters(identity:bid,store:sb,gate:PairingGate(),queue:.main)
        let stall=try NWListener(using:params,on:.any);var stallPort:UInt16=0,connectionsHeld:[NWConnection]=[]
        stall.stateUpdateHandler={state in if case .ready=state {stallPort=stall.port!.rawValue}}
        stall.newConnectionHandler={c in connectionsHeld.append(c);c.start(queue:.main)};stall.start(queue:.main);pump({stallPort>0})
        defer {stall.cancel();connectionsHeld.forEach {$0.cancel()}}
        a.testingEndpoint(peerID:bid.fingerprint,port:stallPort)
        let start=Date();let timeout1=a.send(urls:[file],peerID:bid.fingerprint),timeout2=a.send(urls:[file],peerID:bid.fingerprint)
        pump({[timeout1,timeout2].allSatisfy {id in events.contains {$0.id==id && $0.phase == .failed}}},timeout:7)
        check(Date().timeIntervalSince(start)>=4.8 && Date().timeIntervalSince(start)<6.5,"real five-second connection bound")
        check([timeout1,timeout2].allSatisfy {id in events.filter {$0.id==id && $0.phase == .failed}.count==1},"each unstarted queued request fails once")
        print("PASS: real 5s TLS authorization deadline and all queued requests fail once")
    }
    static func worker() throws {
        let args=CommandLine.arguments,peer=args[2],report=URL(fileURLWithPath:args[3]),directory=args[4]
        let identity=try DeviceIdentity.ephemeral(),store=try ConfigurationStore(url:nil,fallback:Configuration(name:"Worker",receivePath:directory))
        try store.update {$0.peers=[TrustedPeer(id:peer,name:"Parent")]}
        let engine=PeerEngine(identity:identity,store:store)
        engine.onListening={port in try! JSONSerialization.data(withJSONObject:["id":identity.fingerprint,"port":Int(port)]).write(to:report)}
        var stopping=false
        if args.contains("--during-transfer") {engine.onTransfer={u in if !u.finished && !stopping {stopping=true;engine.stop();DispatchQueue.main.asyncAfter(deadline:.now()+0.1){exit(0)}}}}
        engine.start(discovery:false)
        DispatchQueue.global().async {
            _=FileHandle.standardInput.readDataToEndOfFile()
            engine.stop();DispatchQueue.main.asyncAfter(deadline:.now()+0.1){exit(0)}
        }
        RunLoop.main.run()
    }
    static func processExit(root:URL,file:URL) throws {
        for mode in ["normal","kill","during-transfer"] {
            let identity=try DeviceIdentity.ephemeral(),store=try ConfigurationStore(url:nil,fallback:Configuration(name:"Parent",receivePath:root.path))
            let engine=PeerEngine(identity:identity,store:store);var connected=false,failed=false,unpaired=false
            engine.onPeers={connected=$0.contains( where:{$0.connected})};engine.onTransfer={if $0.finished && !$0.succeeded {failed=true}};engine.onUnpaired={_,_,_,_ in unpaired=true}
            let directory=root.appendingPathComponent(mode);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let report=directory.appendingPathComponent("public-listener.json"),process=Process(),input=Pipe()
            process.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]);process.arguments=["--worker",identity.fingerprint,report.path,directory.path]+(mode=="during-transfer" ? ["--during-transfer"] : [])
            process.standardInput=input;process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
            try process.run()
            defer {if process.isRunning {kill(process.processIdentifier,SIGKILL)};input.fileHandleForWriting.closeFile();engine.stop()}
            pump({FileManager.default.fileExists(atPath:report.path)})
            let info=try JSONSerialization.jsonObject(with:Data(contentsOf:report)) as! [String:Any],id=info["id"] as! String,port=UInt16(info["port"] as! Int)
            try store.update {$0.peers=[TrustedPeer(id:id,name:"Worker")];$0.preferredPeer=id}
            engine.start(discovery:false);engine.connect(host:"127.0.0.1",port:port);pump({connected})
            if mode=="normal" {input.fileHandleForWriting.closeFile()}
            else if mode=="kill" {kill(process.processIdentifier,SIGKILL)}
            else {
                let large=directory.appendingPathComponent("large-source.bin")
                try Data(repeating:7,count:32*1024*1024).write(to:large)
                engine.send(urls:[large],peerID:id)
            }
            pump({!connected},timeout:4)
            if mode=="during-transfer" {pump({failed});check(!(try FileManager.default.contentsOfDirectory(atPath:directory.path)).contains {$0.hasPrefix(".PeerJetty-Partial")},"partial receive cleaned on stop")}
            check(store.snapshot.peers.count==1 && store.snapshot.preferredPeer==id && !unpaired,"process exit preserves trust/default and never triggers unpair alert")
            print("PASS: real remote process \(mode) updates disconnected state")
        }
    }
}
