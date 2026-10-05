import Foundation
import PeerCore

let testRoot: URL = {
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--root" {
        return URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("run-\(UUID())")
    }
    return FileManager.default.temporaryDirectory.appendingPathComponent("OpenOnMini-Test-\(UUID())")
}()

func check(_ condition: Bool, _ text: String) {
    if !condition { fputs("FAIL: \(text)\n", stderr); exit(1) }
}
func fail(_ error: Error) { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
let fm = FileManager.default
try fm.createDirectory(at: testRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
let ar = testRoot.appendingPathComponent("A-receive"), br = testRoot.appendingPathComponent("B-receive")
let source = testRoot.appendingPathComponent("source"), folder = source.appendingPathComponent("资料夹")
for url in [ar, br, source, folder, folder.appendingPathComponent("nested")] { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
try Data("hello 中文\n".utf8).write(to: folder.appendingPathComponent("nested/文档.txt"))
try Data().write(to: folder.appendingPathComponent("empty"))
try Data("hidden".utf8).write(to: folder.appendingPathComponent(".hidden"))
try fm.createSymbolicLink(atPath: folder.appendingPathComponent("link").path, withDestinationPath: "nested/文档.txt")
let loose = source.appendingPathComponent("same.txt")
try Data("payload".utf8).write(to: loose); try Data("original".utf8).write(to: br.appendingPathComponent("same.txt"))
let back = source.appendingPathComponent("back.txt"); try Data("reverse direction".utf8).write(to: back)
let aStore = try ConfigurationStore(url: nil, fallback: Configuration(name: "Test A", receivePath: ar.path))
let bStore = try ConfigurationStore(url: nil, fallback: Configuration(name: "Test B", receivePath: br.path))
let aIdentity = try DeviceIdentity.ephemeral(), bIdentity = try DeviceIdentity.ephemeral()
let a = PeerEngine(identity: aIdentity, store: aStore), b = PeerEngine(identity: bIdentity, store: bStore)
var aPort: UInt16 = 0, bPort: UInt16 = 0
var aProof: (UUID, String)?, bProof: (UUID, String)?
var stage = "pairing", pairedSent = false, done = false
var forwardReceipt = false, reverseReceipt = false, strangerRejected = false
var strangerID: String?
var cancelID: UUID?
var passChecks = ["ephemeral identities (no production Keychain)"]
func connectWhenReady() { if aPort > 0 && bPort > 0 && stage == "pairing" { a.openPairing(); b.openPairing(); a.connect(host: "127.0.0.1", port: bPort) } }
a.onListening = { port in aPort = port; connectWhenReady() }
b.onListening = { port in bPort = port; connectWhenReady() }
a.onStatus = { text in print("A:", text) }
b.onStatus = { text in print("B:", text) }
func confirmIfReady() {
    if let ap = aProof, let bp = bProof {
        check(ap.1 == bp.1, "TLS-bound pairing codes must agree")
        passChecks.append("mutual TLS + matching SAS + bilateral confirmation")
        a.confirm(sessionID: ap.0, approved: true); b.confirm(sessionID: bp.0, approved: true)
        aProof = nil; bProof = nil
    }
}
a.onPairing = { id, _, code in check(stage == "pairing", "trusted reconnect must not request pairing"); aProof = (id, code); confirmIfReady() }
b.onPairing = { id, _, code in check(stage == "pairing", "trusted reconnect must not request pairing"); bProof = (id, code); confirmIfReady() }
func startSendingIfReady() {
    if !pairedSent, aStore.snapshot.peers.count == 1, bStore.snapshot.peers.count == 1 {
        pairedSent = true; stage = "forward"; a.closePairing(); b.closePairing()
        a.send(urls: [folder, loose], peerID: bIdentity.fingerprint)
    }
}
a.onPeers = { _ in startSendingIfReady() }
b.onPeers = { _ in startSendingIfReady() }
b.onReceived = { _, urls in
    do {
        if stage == "forward" {
            check(urls.count == 2, "all top-level items received")
            check(try Data(contentsOf: br.appendingPathComponent("same.txt")) == Data("original".utf8), "existing file preserved")
            check(try Data(contentsOf: br.appendingPathComponent("same (1).txt")) == Data("payload".utf8), "numbered collision")
            check(try Data(contentsOf: br.appendingPathComponent("资料夹/nested/文档.txt")) == Data("hello 中文\n".utf8), "nested Unicode content")
            check(try Data(contentsOf: br.appendingPathComponent("资料夹/empty")).isEmpty, "empty file")
            check(try fm.destinationOfSymbolicLink(atPath: br.appendingPathComponent("资料夹/link").path) == "nested/文档.txt", "safe link preserved")
            passChecks.append("forward: multiple roots, Unicode, nested directories, hidden/empty files, internal links, collision without overwrite")
            stage = "reverse"; b.send(urls: [back], peerID: aIdentity.fingerprint)
        }
    } catch { fail(error) }
}
a.onReceived = { _, urls in
    do {
        if stage == "reverse" {
            check(try Data(contentsOf: urls[0]) == Data("reverse direction".utf8), "reverse content")
            passChecks.append("reverse transfer with receiver commit receipt")
            stage = "cancelling"
            let huge = source.appendingPathComponent("cancel.bin")
            fm.createFile(atPath: huge.path, contents: nil)
            let file = try FileHandle(forWritingTo: huge); try file.truncate(atOffset: 128 * 1024 * 1024); try file.close()
            a.send(urls: [huge], peerID: bIdentity.fingerprint)
        }
    } catch { fail(error) }
}
b.onTransfer = { update in
    if !update.receiving, update.finished, update.succeeded { reverseReceipt = true }
}
a.onRejectedConnection = { id in if id == strangerID { strangerRejected = true } }
a.onTransfer = { update in
    if !update.receiving, update.finished, update.succeeded { forwardReceipt = true }
    if stage == "cancelling", !update.receiving, !update.finished, update.completed > 0, cancelID == nil {
        cancelID = update.id; a.cancel(transferID: update.id)
    }
    if stage == "cancelling", update.id == cancelID, update.finished {
        check(!update.succeeded, "cancel not reported as success")
        stage = "cleanup"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            do {
                check(!fm.fileExists(atPath: br.appendingPathComponent("cancel.bin").path), "cancelled payload not published")
                check(try fm.contentsOfDirectory(atPath: br.path).allSatisfy { !$0.hasPrefix(".OpenOnMini-Partial-") }, "cancelled staging removed")
                passChecks.append("cancellation closes stream and removes partial data")
                stage = "reconnecting"; a.connect(host: "127.0.0.1", port: bPort)
            } catch { fail(error) }
        }
    }
}
a.onPeers = { peers in
    startSendingIfReady()
    if stage == "reconnecting", peers.contains(where: { $0.id == bIdentity.fingerprint && $0.connected }) {
        passChecks.append("trusted TLS reconnect without pairing prompt")
        stage = "revoking"; a.forget(bIdentity.fingerprint)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            check(aStore.snapshot.peers.isEmpty, "local revocation persisted")
            let stranger = PeerEngine(identity: try! DeviceIdentity.ephemeral(), store: try! ConfigurationStore(url: nil, fallback: Configuration(name: "Unknown", receivePath: ar.path)))
            strangerID = stranger.identity.fingerprint
            stranger.onPairing = { _, _, _ in check(false, "closed pairing gate must reject strangers") }
            stranger.onStatus = { text in
                if text.contains("SSL") || text.contains("TLS") || text.contains("连接") {
                    check(aStore.snapshot.peers.isEmpty, "stranger not trusted")
                }
            }
            stranger.start(discovery: false); stranger.openPairing(); stranger.connect(host: "127.0.0.1", port: aPort)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                check(strangerRejected, "unknown TLS identity actually rejected by listener")
                check(forwardReceipt && reverseReceipt, "both senders received verified commit receipts")
                stranger.stop()
                passChecks.append("revocation and closed pairing window leave unknown identity untrusted")
                done = true
            }
        }
    }
}
a.start(discovery: false); b.start(discovery: false)
let deadline = Date().addingTimeInterval(35)
while !done, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
check(done, "integration harness timed out at \(stage)")
a.stop(); b.stop()
let report: [String: Any] = ["status": "passed", "checks": passChecks, "scope": "two isolated engines on loopback; not real-device Bonjour/Finder/WeChat verification"]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: testRoot.appendingPathComponent("report.json"))
print("PASS:", passChecks.count, "integration checks; report:", testRoot.appendingPathComponent("report.json").path)
