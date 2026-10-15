import AppKit
import Sparkle
import PeerCore

func check(_ condition:Bool,_ message:String) {if !condition {fatalError(message)}}
func labels(_ view:NSView) -> [String] {
    let own=(view as? NSTextField).map{[$0.stringValue]} ?? []
    return own + view.subviews.flatMap(labels)
}
@main struct UpdateInterfaceTests {
    static func main() {
        if CommandLine.arguments.contains("--seed-language") {
            UserDefaults.standard.set("zh-Hans",forKey:"PeerJettyDisplayLanguage")
            UserDefaults.standard.removeObject(forKey:"AppleLanguages")
            UserDefaults.standard.removeObject(forKey:"PeerJettyManagesNativeLanguage")
            UserDefaults.standard.synchronize();return
        }
        LanguagePreferences().applyNativeLanguage()
        defer {UserDefaults.standard.removePersistentDomain(forName:"app.peerjetty.test.update-ui")}
        let app=NSApplication.shared;app.setActivationPolicy(.accessory)
        let chinese=L10n.language == "zh-Hans"
        let framework=Bundle(for:SPUUpdater.self)
        let checking=framework.localizedString(forKey:"Checking for updates…",value:nil,table:"Sparkle")
        check(chinese ? checking != "Checking for updates…" : checking == "Checking for updates…","Sparkle must follow app language")
        let suite="PeerJetty.Test.NativeLanguage."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!;defer {defaults.removePersistentDomain(forName:suite)}
        let prefs=LanguagePreferences(defaults:defaults)
        prefs.save(.simplifiedChinese);check((defaults.persistentDomain(forName:suite)?["AppleLanguages"] as? [String])==["zh-Hans"],"persist native Chinese")
        prefs.save(.english);check((defaults.persistentDomain(forName:suite)?["AppleLanguages"] as? [String])==["en"],"persist native English")
        prefs.save(.system);check(defaults.persistentDomain(forName:suite)?["AppleLanguages"] == nil,"restore system without stale native override")
        defaults.set(["fr"],forKey:"AppleLanguages");prefs.applyNativeLanguage()
        check((defaults.persistentDomain(forName:suite)?["AppleLanguages"] as? [String])==["fr"],"do not delete unmanaged system app preference")
        let error=NSError(domain:SUSparkleErrorDomain,code:1002,userInfo:[NSLocalizedDescriptionKey:"Provider diagnostic in English"])
        let alert=TransferAwareUpdateDriver.failureAlert(error)
        check(alert.informativeText.hasPrefix(L10n.text("updates.feed_failed")) && alert.informativeText.contains(L10n.text("updates.diagnostics_hint")),"owned localized feed explanation")
        let details=(alert.accessoryView as? NSScrollView)?.documentView as? NSTextView
        check(details?.string==error.localizedDescription,"provider details preserved separately")
        let driver=TransferAwareUpdateDriver(hostBundle:.main,delegate:nil)
        driver.showUserInitiatedUpdateCheck(cancellation:{})
        RunLoop.main.run(until:Date().addingTimeInterval(0.15))
        let checkingWindows=NSApp.windows.filter{$0.isVisible && labels($0.contentView ?? NSView()).contains(checking)}
        check(!checkingWindows.isEmpty,"actual native checking window visible")
        var acknowledged=false,inspected=false
        DispatchQueue.main.asyncAfter(deadline:.now()+0.15) {
            check(checkingWindows.allSatisfy{!$0.isVisible},"checking window must close before failure alert")
            let failures=NSApp.windows.filter{$0.isVisible && labels($0.contentView ?? NSView()).contains(L10n.text("updates.failed_help"))}
            check(failures.count==1,"single native error alert")
            inspected=true;NSApp.abortModal()
        }
        driver.showUpdaterError(error,acknowledgement:{acknowledged=true})
        check(inspected && acknowledged,"error acknowledgement exactly after presentation")
        driver.dismissUpdateInstallation();NSApp.windows.forEach{$0.orderOut(nil)}
        print("PASS: \(L10n.language) actual Sparkle language/check window, terminal cleanup, single localized error, diagnostics and native preference migration")
    }
}
