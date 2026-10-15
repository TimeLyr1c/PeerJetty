import AppKit
import Sparkle
import CryptoKit

final class Driver: SPUStandardUserDriver {
    override func showUpdateFound(with appcastItem:SUAppcastItem,state:SPUUserUpdateState,reply:@escaping(SPUUserUpdateChoice)->Void) {reply(.install)}
    override func showReady(toInstallAndRelaunch reply:@escaping(SPUUserUpdateChoice)->Void) {reply(.install)}
    override func showUpdateNotFoundWithError(_ error:Error,acknowledgement:@escaping()->Void) {
        try? "PASS: signed empty feed reports no update".write(toFile:Bundle.main.object(forInfoDictionaryKey:"FixtureResult") as! String,atomically:true,encoding:.utf8)
        acknowledgement();NSApp.terminate(nil)
    }
    override func showUpdaterError(_ error:Error,acknowledgement:@escaping()->Void) {
        try? error.localizedDescription.write(toFile:Bundle.main.object(forInfoDictionaryKey:"FixtureResult") as! String,atomically:true,encoding:.utf8)
        acknowledgement();NSApp.terminate(nil)
    }
}
@main final class Fixture: NSObject,NSApplicationDelegate {
    var driver:Driver!;var updater:SPUUpdater!
    static func main() {
        if CommandLine.arguments.count == 3,CommandLine.arguments[1] == "--key" {
            let key=Curve25519.Signing.PrivateKey();let path=CommandLine.arguments[2]
            try! key.rawRepresentation.base64EncodedString().write(toFile:path,atomically:true,encoding:.utf8)
            try! FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path)
            print(key.publicKey.rawRepresentation.base64EncodedString());return
        }
        let app=NSApplication.shared;let value=Fixture();app.delegate=value;app.setActivationPolicy(.accessory);app.run()
    }
    func applicationDidFinishLaunching(_ notification:Notification) {
        let result=Bundle.main.object(forInfoDictionaryKey:"FixtureResult") as! String
        if Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String == "1001" {
            try! "PASS: Sparkle replaced and relaunched build1001".write(toFile:result,atomically:true,encoding:.utf8)
            NSApp.terminate(nil);return
        }
        driver=Driver(hostBundle:.main,delegate:nil)
        updater=SPUUpdater(hostBundle:.main,applicationBundle:.main,userDriver:driver,delegate:nil)
        do {try updater.start();updater.checkForUpdates()} catch {try? error.localizedDescription.write(toFile:result,atomically:true,encoding:.utf8);NSApp.terminate(nil)}
    }
}
