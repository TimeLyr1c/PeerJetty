import Foundation
import CryptoKit
import PeerCore

final class PeerCoreTests {
    func testOptionalAutoOpenDefaultsPersistsAndUsesOnlyCommittedRoots() throws {
        let legacy = Data(#"{"name":"Mac","receivePath":"/test/inbox","peers":[],"onboardingComplete":true}"#.utf8)
        let decoded = try JSONDecoder().decode(Configuration.self, from: legacy)
        XCTAssertEqual(decoded.autoOpenReceivedFiles, false)
        XCTAssertEqual(decoded.onboardingComplete, true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("configuration.json")
        let store = try ConfigurationStore(url: url, fallback: decoded)
        try store.update { $0.autoOpenReceivedFiles = true }
        XCTAssertEqual(try ConfigurationStore(url: url, fallback: decoded).snapshot.autoOpenReceivedFiles, true)
        try store.update { $0.autoOpenReceivedFiles = false }
        XCTAssertEqual(try ConfigurationStore(url: url, fallback: decoded).snapshot.autoOpenReceivedFiles, false)
        let paths = [URL(fileURLWithPath: "/committed/a.txt"), URL(fileURLWithPath: "/committed/folder")]
        var opened: [URL] = []
        let disabled = ReceivedFileActions.openCommitted(paths, enabled: false) { opened.append($0); return true }
        XCTAssertEqual(disabled, []); XCTAssertEqual(opened, [])
        let failures = ReceivedFileActions.openCommitted(paths, enabled: true) { opened.append($0); return $0 == paths[0] }
        XCTAssertEqual(opened, paths); XCTAssertEqual(failures, [paths[1]])
        opened = []
        XCTAssertEqual(ReceivedFileActions.openCommitted([], enabled: true) { opened.append($0); return true }, [])
        XCTAssertEqual(opened, [])
    }
    func testRenamedConfigurationPreservesTrustAndDoesNotOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fallback = Configuration(name: "fresh", receivePath: "/test/fallback")
        let legacyURL = root.appendingPathComponent("OpenOnMini/configuration.json")
        let currentURL = root.appendingPathComponent("PeerJetty/configuration.json")
        let legacy = try ConfigurationStore(url: legacyURL, fallback: fallback)
        try legacy.update {
            $0.name = "paired Mac"; $0.receivePath = "/test/inbox"
            $0.receiveBookmark = Data([1, 2, 3]); $0.onboardingComplete = true
            $0.peers = [TrustedPeer(id: "trusted-id", name: "Other Mac")]; $0.preferredPeer = "trusted-id"
        }
        let original = try Data(contentsOf: legacyURL)
        let migrated = try ConfigurationStore.forApplication(applicationSupport: root, fallback: fallback)
        XCTAssertEqual(migrated.url, currentURL)
        XCTAssertEqual(migrated.snapshot.peers, legacy.snapshot.peers)
        XCTAssertEqual(migrated.snapshot.preferredPeer, "trusted-id")
        XCTAssertEqual(migrated.snapshot.receivePath, "/test/inbox")
        XCTAssertEqual(migrated.snapshot.receiveBookmark, Data([1, 2, 3]))
        XCTAssertEqual(migrated.snapshot.onboardingComplete, true)
        XCTAssertEqual(try Data(contentsOf: legacyURL), original)
        try migrated.update { $0.name = "new settings" }
        let reopened = try ConfigurationStore.forApplication(applicationSupport: root, fallback: fallback)
        XCTAssertEqual(reopened.snapshot.name, "new settings")
        try Data("corrupt".utf8).write(to: currentURL)
        XCTAssertThrowsError(try ConfigurationStore.forApplication(applicationSupport: root, fallback: fallback))
        XCTAssertEqual(try Data(contentsOf: currentURL), Data("corrupt".utf8))
        try FileManager.default.removeItem(at: currentURL)
        try Data("corrupt legacy".utf8).write(to: legacyURL)
        XCTAssertThrowsError(try ConfigurationStore.forApplication(applicationSupport: root, fallback: fallback))
        XCTAssertFalse(FileManager.default.fileExists(atPath: currentURL.path))
        try FileManager.default.removeItem(at: legacyURL)
        let fresh = try ConfigurationStore.forApplication(applicationSupport: root, fallback: fallback)
        XCTAssertEqual(fresh.snapshot.name, "fresh")
        XCTAssertEqual(fresh.snapshot.peers, [])
    }
    func testPairingBindsBothIdentitiesNoncesAndTLSConnection() throws {
        let a = String(repeating: "a", count: 64), b = String(repeating: "b", count: 64)
        let an = Data(repeating: 1, count: 32), bn = Data(repeating: 2, count: 32), tls = Data(repeating: 3, count: 32)
        let code = PairingProof.code(localID: a, localNonce: an, remoteID: b, remoteNonce: bn, exporter: tls)
        XCTAssertEqual(code, PairingProof.code(localID: b, localNonce: bn, remoteID: a, remoteNonce: an, exporter: tls))
        XCTAssertNotEqual(code, PairingProof.code(localID: a, localNonce: an, remoteID: b, remoteNonce: bn, exporter: Data(repeating: 4, count: 32)))
        XCTAssertThrowsError(try PairingProof.verify(id: a, nonce: bn, commitment: PairingProof.commitment(id: a, nonce: an)))
    }
    func testRejectTraversalAndSymlinkParent() throws {
        for name in ["../x", "/tmp/x", "x//y", "x/../y", "x\0"] { XCTAssertThrowsError(try FileRules.validateRelative(name)) }
        XCTAssertThrowsError(try FileRules.validateLink("../../outside", from: "folder/link"))
        let manifest = TransferManifest(roots: ["folder"], entries: [
            ManifestEntry(root: 0, path: "", kind: .directory),
            ManifestEntry(root: 0, path: "link", kind: .symlink, link: "."),
            ManifestEntry(root: 0, path: "link/file", kind: .file)])
        XCTAssertThrowsError(try manifest.validate())
    }
    func testSymlinkChainEscapeAndCycles() throws {
        let entries = [ManifestEntry(root: 0, path: "", kind: .directory),
            ManifestEntry(root: 0, path: "sub", kind: .directory),
            ManifestEntry(root: 0, path: "sub/a", kind: .symlink, link: ".."),
            ManifestEntry(root: 0, path: "escape", kind: .symlink, link: "sub/a/..")]
        XCTAssertThrowsError(try TransferManifest(roots: ["root"], entries: entries).validate())
        let cycle = [ManifestEntry(root: 0, path: "", kind: .directory),
            ManifestEntry(root: 0, path: "a", kind: .symlink, link: "b"),
            ManifestEntry(root: 0, path: "b", kind: .symlink, link: "a")]
        XCTAssertThrowsError(try TransferManifest(roots: ["root"], entries: cycle).validate())
    }
    func testPromiseCompletionCountsFilesAndWaitsForAll() throws {
        var completions = 0
        let first = URL(fileURLWithPath: "/test/a"), second = URL(fileURLWithPath: "/test/b")
        let tracker = PromiseTracker(receivers: 2) { result in
            completions += 1
            if case .success(let urls) = result { XCTAssertEqual(urls.count, 3) } else { preconditionFailure("Unexpected failure") }
        }
        tracker.record(receiver: 0, url: first, error: nil)
        tracker.expect(receiver: 0, count: 2)
        tracker.expect(receiver: 1, count: 1)
        tracker.record(receiver: 1, url: second, error: nil)
        XCTAssertEqual(completions, 0)
        tracker.record(receiver: 0, url: second, error: nil)
        XCTAssertEqual(completions, 1)
        tracker.cancel(); XCTAssertEqual(completions, 1)
        var failed = false
        let partial = PromiseTracker(receivers: 1) { if case .failure = $0 { failed = true } }
        partial.expect(receiver: 0, count: 2)
        partial.record(receiver: 0, url: first, error: PeerError.message("source failure"))
        XCTAssertFalse(failed)
        partial.record(receiver: 0, url: second, error: nil)
        XCTAssertEqual(failed, true)
    }
    func testMalformedAndDuplicateManifests() throws {
        XCTAssertThrowsError(try TransferManifest(roots: ["mode"], entries: [ManifestEntry(root: 0, path: "", kind: .file, mode: 0o4755)]).validate())
        let long = String(repeating: "中", count: 85)
        let renamed = FileRules.collisionName(long, directory: false, number: 1)
        try FileRules.validateName(renamed)
        XCTAssertEqual(renamed.hasSuffix(" (1)"), true)
        let missing = TransferManifest(roots: ["root"], entries: [])
        XCTAssertThrowsError(try missing.validate())
        let duplicate = TransferManifest(roots: ["root"], entries: [ManifestEntry(root: 0, path: "", kind: .directory), ManifestEntry(root: 0, path: "", kind: .directory)])
        XCTAssertThrowsError(try duplicate.validate())
        let invalid = TransferManifest(roots: ["root"], entries: [ManifestEntry(root: 0, path: "", kind: .file, size: -1)])
        XCTAssertThrowsError(try invalid.validate())
    }
    func testCorruptionDoesNotCommitAndCancellationCleansStaging() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = TransferManifest(roots: ["a.txt"], entries: [ManifestEntry(root: 0, path: "", kind: .file, size: 3)])
        let receive = try ReceiveTransaction(manifest: manifest, destination: root)
        try receive.beginFile(index: 0); try receive.append(Data("abc".utf8))
        XCTAssertThrowsError(try receive.endFile(index: 0, expectedHash: Digest.hex(Data("xyz".utf8))))
        XCTAssertThrowsError(try receive.finish()); receive.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: receive.staging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("a.txt").path))
    }
    func testAtomicNoOverwriteAndEmptyFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("a.txt")
        try Data("original".utf8).write(to: original)
        let manifest = TransferManifest(roots: ["a.txt"], entries: [ManifestEntry(root: 0, path: "", kind: .file)])
        let receive = try ReceiveTransaction(manifest: manifest, destination: root)
        try receive.beginFile(index: 0); try receive.endFile(index: 0, expectedHash: Digest.hex(Data()))
        let paths = try receive.finish()
        XCTAssertEqual(paths.first?.lastPathComponent, "a (1).txt")
        XCTAssertEqual(try Data(contentsOf: original), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: paths[0]), Data())
    }
}

private func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Expected equal values") }
private func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a != b, "Expected different values") }
private func XCTAssertFalse(_ value: Bool) { precondition(!value, "Expected false") }
private func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T) {
    do { _ = try expression(); preconditionFailure("Expected an error") } catch {}
}
@main struct TestRunner {
    static func main() throws {
        let tests = PeerCoreTests()
        try tests.testOptionalAutoOpenDefaultsPersistsAndUsesOnlyCommittedRoots()
        try tests.testRenamedConfigurationPreservesTrustAndDoesNotOverwrite()
        try tests.testPairingBindsBothIdentitiesNoncesAndTLSConnection()
        try tests.testRejectTraversalAndSymlinkParent()
        try tests.testSymlinkChainEscapeAndCycles()
        try tests.testPromiseCompletionCountsFilesAndWaitsForAll()
        try tests.testMalformedAndDuplicateManifests()
        try tests.testCorruptionDoesNotCommitAndCancellationCleansStaging()
        try tests.testAtomicNoOverwriteAndEmptyFiles()
        print("PASS: 9 core test groups (optional auto-open, rename migration, pairing, traversal/links, malformed manifests, promises, corruption/cancellation, no-overwrite/empty files)")
    }
}
