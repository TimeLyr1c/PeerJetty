import Foundation
import CryptoKit
import Darwin
@testable import PeerCore

private func check(_ value: Bool, _ message: String) {
    if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private func pump(_ done: () -> Bool, timeout: Double = 12) {
    let end = Date().addingTimeInterval(timeout)
    while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    check(done(), "async deadline")
}
private let full = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))

@main struct DiskSpaceChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PeerJetty-disk-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        check(ReceiveStorageError.isFull(full), "POSIX disk full")
        check(ReceiveStorageError.isFull(NSError(domain:NSCocoaErrorDomain,code:NSFileWriteOutOfSpaceError)), "Cocoa disk full")
        check(ReceiveStorageError.isFull(NSError(domain:"wrapper",code:1,userInfo:[NSUnderlyingErrorKey:full])), "nested disk full")
        for code in [EACCES, ENOENT, EIO] {
            let error = NSError(domain:NSPOSIXErrorDomain,code:Int(code))
            check(!ReceiveStorageError.isFull(error) && (ReceiveStorageError.normalize(error) as NSError).code == Int(code), "other errors stay distinct")
        }
        let source = root.appendingPathComponent("source.txt")
        try Data("原样 Unicode 🧪\nsecond line\n".utf8).write(to: source)
        let prepared = try PreparedTransfer(urls:[source])
        for stage in [ReceiveStorageIO.Stage.createDirectory, .createFile, .write, .synchronize, .commit] {
            let destination = root.appendingPathComponent("unit-\(stage)")
            try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
            var io = ReceiveStorageIO(); io.before = { if $0 == stage { throw full } }
            var transaction: ReceiveTransaction?
            do {
                let t = try ReceiveTransaction(manifest:prepared.manifest,destination:destination,io:io); transaction=t
                let data=try Data(contentsOf:source)
                try t.beginFile(index:0); try t.append(data)
                try t.endFile(index:0,expectedHash:Digest.hex(data)); _ = try t.finish()
                check(false,"injected failure must be observed")
            } catch { check(ReceiveStorageError.isFull(error), "\(stage) maps to app disk error") }
            transaction?.cancel()
            check(try FileManager.default.contentsOfDirectory(atPath:destination.path).isEmpty,"\(stage) cleans staging")
        }
        var io=ReceiveStorageIO(); io.availableBytes={_ in prepared.manifest.byteCount + 16*1024*1024 - 1}
        do { _ = try ReceiveTransaction(manifest:prepared.manifest,destination:root,io:io);check(false,"reserve preflight") }
        catch {check(ReceiveStorageError.isFull(error),"16 MiB reserve kept")}
        io.availableBytes={_ in prepared.manifest.byteCount + 16*1024*1024}
        let boundary=try ReceiveTransaction(manifest:prepared.manifest,destination:root,io:io);boundary.cancel()
        let en=TranslationCatalog(preferences:["en"]),zh=TranslationCatalog(preferences:["zh-Hans"])
        for catalog in [en,zh] {
            let status=catalog.remoteError(key:ReceiveStorageError.partialKey,arguments:["1"],fallback:"legacy")
            check(status != "legacy" && status.contains("1"),"localized partial count")
            check(catalog.remoteError(key:ReceiveStorageError.partialKey,arguments:[],fallback:"legacy")=="legacy","wrong field count rejected")
        }
        struct LegacyReject:Decodable {let kind:String;let text:String?}
        var reject=Message("reject");reject.errorKey=ReceiveStorageError.partialKey;reject.errorArguments=["1"]
        reject.text=en.remoteError(key:reject.errorKey,arguments:reject.errorArguments,fallback:"legacy")
        check(try JSONDecoder().decode(LegacyReject.self,from:JSONEncoder().encode(reject)).text==reject.text,"old peer gets English fallback")
        print("PASS: create/write/sync/commit classification, cleanup, reserve boundary, bilingual and legacy diagnostics")
        for stage in ["preflight","createDirectory","createFile","write","synchronize","commit","partial"] {
            try network(root:root,source:source,stage:stage)
        }
    }
    static func network(root:URL,source:URL,stage:String) throws {
        let local=root.appendingPathComponent("A-\(stage)"),remote=root.appendingPathComponent("B-\(stage)")
        for d in [local,remote] {try FileManager.default.createDirectory(at:d,withIntermediateDirectories:true)}
        let aid=try DeviceIdentity.ephemeral(),bid=try DeviceIdentity.ephemeral()
        let sa=try ConfigurationStore(url:nil,fallback:Configuration(name:"A",receivePath:local.path))
        let sb=try ConfigurationStore(url:nil,fallback:Configuration(name:"B",receivePath:remote.path))
        try sa.update {$0.peers=[TrustedPeer(id:bid.fingerprint,name:"B")]}
        try sb.update {$0.peers=[TrustedPeer(id:aid.fingerprint,name:"A")]}
        let a=PeerEngine(identity:aid,store:sa),b=PeerEngine(identity:bid,store:sb)
        defer {a.stop();b.stop();RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
        var io=ReceiveStorageIO(),commits=0
        if stage=="preflight" {io.availableBytes={_ in 0}}
        io.before={step in
            if step == .commit {commits+=1}
            if String(describing:step)==stage || (stage=="partial" && step == .commit && commits==2) {throw full}
        }
        b.testingStorage(io)
        var port:UInt16=0,connected=false,au:[TransferUpdate]=[],bu:[TransferUpdate]=[],receiptsA=0,receiptsB=0
        var statusA:[String]=[],statusB:[String]=[]
        a.onStatus={statusA.append($0)};b.onStatus={statusB.append($0)}
        a.onPeers={connected=$0.contains {$0.id==bid.fingerprint && $0.connected}}
        b.onListening={port=$0}; a.onTransfer={au.append($0)}; b.onTransfer={bu.append($0)}
        a.onReceived={_,urls in receiptsA+=1;check(urls.count==1,"reverse complete")}
        b.onReceived={_,_ in receiptsB+=1}
        a.start(discovery:false);b.start(discovery:false);pump({port>0})
        a.connect(host:"127.0.0.1",port:port);pump({connected})
        // Reverse traffic shares the same authenticated connection. No real disk saturation.
        let reverse=root.appendingPathComponent("reverse-\(stage).bin")
        try Data(repeating:7,count:16*1024*1024).write(to:reverse)
        let second=root.appendingPathComponent("second-\(stage).txt")
        try Data("second root".utf8).write(to:second)
        let reverseID=b.send(urls:[reverse],peerID:aid.fingerprint)
        let failedID=a.send(urls:stage=="partial" ? [source,second] : [stage=="write" ? reverse : source],peerID:bid.fingerprint)
        pump({au.contains {$0.id==failedID && $0.finished} && bu.contains {$0.id==failedID && $0.finished} && receiptsA==1 && bu.contains {$0.id==reverseID && $0.finished && $0.succeeded}})
        let af=au.filter {$0.id==failedID && $0.finished},bf=bu.filter {$0.id==failedID && $0.finished}
        let expected=L10n.message(stage=="partial" ? ReceiveStorageError.partialKey : ReceiveStorageError.fullKey,arguments:stage=="partial" ? ["1"] : [])
        pump({statusA.contains(expected) && statusB.contains(expected)})
        check(af.count==1 && bf.count==1 && !af[0].succeeded && !bf[0].succeeded && af[0].status==expected && bf[0].status==expected,"\(stage) both ends fail exactly once with disk reason")
        check(bu.contains {$0.id==reverseID && $0.finished && $0.succeeded},"reverse sender succeeds")
        check(connected && sa.snapshot.peers.count==1 && sb.snapshot.peers.count==1,"failure retains session and trust")
        let files=try FileManager.default.contentsOfDirectory(atPath:remote.path)
        check(files.count==(stage=="partial" ? 1:0) && !files.contains {$0.hasPrefix(".PeerJetty-Partial")},"partial cleanup retains only committed roots")
        if stage=="partial" {check(try Data(contentsOf:remote.appendingPathComponent(source.lastPathComponent))==Data(contentsOf:source),"committed root intact")}
        check(receiptsB==0,"failed or partial transfer cannot auto-open or notify success")
        b.testingStorage(nil)
        let retry=a.send(urls:[source],peerID:bid.fingerprint)
        pump({receiptsB==1 && au.contains {$0.id==retry && $0.finished && $0.succeeded}})
        check(connected,"same connection accepts retry after draining old frames")
        print("PASS: TLS \(stage), both-end status, reverse traffic, partial cleanup, no false receipt and retry")
    }
}
