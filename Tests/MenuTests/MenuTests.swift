import AppKit
import PeerCore
import CoreServices

@main struct MenuTests {
    static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        var fired:[MenuBarController.Action] = []
        let actions = Dictionary(uniqueKeysWithValues:MenuBarController.Action.allCases.map { action in (action,{fired.append(action)}) })
        let bar = MenuBarController(autosaveName:"PeerJetty.IsolatedMenuTest",actions:actions)
        if CommandLine.arguments.contains("--save-hidden") {
            precondition(bar.isVisible,"isolated first launch defaults visible")
            bar.setVisible(false); RunLoop.main.run(until:Date().addingTimeInterval(0.1)); UserDefaults.standard.synchronize()
            precondition(!bar.isVisible); print("PASS: native hidden preference saved"); return
        }
        if CommandLine.arguments.contains("--restore-hidden") {
            precondition(!bar.isVisible,"native visibility restores on another process")
            print("PASS: hidden survives process restart without forced restoration")
        }
        precondition(bar.item.button?.image?.isTemplate == true,"native template symbol")
        precondition(bar.item.menu!.items.count == 9,"activity line and separator, six actions plus destination submenu")
        let actionItems=bar.item.menu!.items.filter{$0.submenu == nil && $0.action != nil}
        precondition(actionItems.map(\.title) == MenuBarController.entries.map {L10n.text($0.1)})
        precondition(bar.activityText == nil && bar.currentSymbol == MenuBarController.idleSymbol,"idle menu has no activity line")
        precondition(bar.item.behavior.contains(.removalAllowed) && !bar.item.behavior.contains(.terminationOnRemoval))
        for entry in actionItems { NSApp.sendAction(entry.action!,to:entry.target,from:entry) }
        precondition(fired == MenuBarController.Action.allCases,"all six actions wired")
        var chosen:String?;bar.onSelectTarget={chosen=$0}
        let peers=[DiscoveredPeer(id:"a",name:"Same",paired:true,connected:false),DiscoveredPeer(id:"b",name:"Same",paired:true,connected:true),DiscoveredPeer(id:"u",name:"Unknown",paired:false,connected:true)]
        bar.updateTargets(peers,preferred:"b")
        let submenu=bar.item.menu!.items.first{$0.submenu != nil}!.submenu!
        precondition(submenu.items.count == 2 && submenu.items[1].state == .on,"paired IDs and default mark")
        NSApp.sendAction(submenu.items[0].action!,to:submenu.items[0].target,from:submenu.items[0])
        precondition(chosen == "a","offline device selection routes by ID")
        precondition(submenu.items.allSatisfy{$0.title.hasSuffix(" · a") || $0.title.hasSuffix(" · b")},"duplicate names keep their short IDs")
        bar.updateTargets([DiscoveredPeer(id:"unique-id",name:"Studio",paired:true,connected:true)],preferred:nil)
        let unique=bar.item.menu!.items.first{$0.submenu != nil}!.submenu!.items[0].title
        precondition(!unique.contains("unique"),"a unique name hides the ID")
        let id=UUID()
        bar.activity(TransferUpdate(id:id,peerName:"Studio",receiving:false,completed:42,total:100,status:"Sending",finished:false,succeeded:false))
        precondition(bar.activityText == L10n.text("settings.sending_progress","Studio",L10n.percent(42)) && bar.currentSymbol == MenuBarController.busySymbol,"active transfer shows progress and the busy symbol")
        precondition(bar.item.menu!.items[0].isEnabled == false && bar.item.menu!.items[0].action == nil,"activity line is read-only")
        bar.activity(TransferUpdate(id:id,peerName:"Studio",receiving:true,completed:100,total:100,status:"Saving",finished:false,succeeded:false))
        precondition(bar.activityText == L10n.text("settings.receiving_progress","Studio",L10n.text("drop.waiting_confirmation")),"full bytes still wait for confirmation")
        bar.activity(TransferUpdate(id:id,peerName:"Studio",receiving:true,completed:100,total:100,status:"Done",finished:true,succeeded:true))
        precondition(bar.activityText == nil && bar.currentSymbol == MenuBarController.idleSymbol && bar.item.button?.image?.isTemplate == true,"finished transfer restores the idle template symbol")
        var values:[Bool] = [];bar.onVisibility = {values.append($0)}
        bar.setVisible(true);bar.item.isVisible = false;bar.setVisible(true)
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        precondition(values == [false],"only external system changes are observed")
        precondition(MenuBarController.activationPolicy(dockVisible:true) == .regular && MenuBarController.activationPolicy(dockVisible:false) == .accessory,"Dock recovery policy")
        checkIndependentPreferences()
        if let id=Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName:id) }
        print("PASS: six native menu actions, removability, visibility KVO and Dock policy")
    }
    static func checkIndependentPreferences() {
        enum Failure: Error { case denied }
        let fresh = Configuration(name:"test",receivePath:"/tmp")
        precondition(fresh.showMenuBarIcon == true && fresh.showDockIcon == false)
        let oldData = Data(#"{"name":"test","receivePath":"/tmp","peers":[],"onboardingComplete":true}"#.utf8)
        let old = try! JSONDecoder().decode(Configuration.self,from:oldData)
        for native in [false,true] {
            let flags = IconVisibilityController.migrated(old,nativeMenu:native)
            precondition(flags == (native,!native))
        }
        for menu in [false,true] { for dock in [false,true] {
            var saved = fresh; var saves = 0; var fail = false
            let state = IconVisibilityController(menu:menu,dock:dock) { m,d in
                if fail { throw Failure.denied }
                saved.showMenuBarIcon=m; saved.showDockIcon=d; saves += 1
            }
            state.recover()
            precondition(state.temporary == (!menu && !dock) && state.dock == dock && saves == 0)
            state.hideTemporary(); precondition(!state.temporary && state.effectiveMenu == menu)
            try! state.setMenu(menu); try! state.setDock(dock)
            let decoded = try! JSONDecoder().decode(Configuration.self,from:JSONEncoder().encode(saved))
            precondition(decoded.showMenuBarIcon == menu && decoded.showDockIcon == dock)
            state.recover()
            let restarted = IconVisibilityController(menu:decoded.showMenuBarIcon!,dock:decoded.showDockIcon!) {_,_ in}
            precondition(!restarted.temporary && restarted.effectiveMenu == menu)
            fail = true
            do { try state.setDock(!dock); preconditionFailure("save must fail") } catch {}
            precondition(state.dock == dock)
            do { try state.setMenu(!menu); preconditionFailure("save must fail") } catch {}
            precondition(state.menu == menu)
            fail = false; try! state.systemChanged(false)
            precondition(!state.menu && !state.temporary && state.dock == dock)
            state.recover(); let before=saves; try! state.systemChanged(false)
            precondition(!state.temporary && saves == before + (dock ? 1 : 0))
            try! state.setMenu(true); precondition(state.menu && !state.temporary && state.dock == dock)
        }}
        let event = NSAppleEventDescriptor(eventClass:AEEventClass(kCoreEventClass),eventID:AEEventID(kAEOpenApplication),targetDescriptor:nil,returnID:AEReturnID(kAutoGenerateReturnID),transactionID:AETransactionID(kAnyTransactionID))
        precondition(IconLaunchReason.detect(event) == .user && IconLaunchReason.detect(nil) == .unknown)
        event.setParam(NSAppleEventDescriptor(boolean:true),forKeyword:AEKeyword(keyAELaunchedAsLogInItem))
        precondition(IconLaunchReason.detect(event) == .background)
        event.setParam(NSAppleEventDescriptor(boolean:false),forKeyword:AEKeyword(keyAELaunchedAsLogInItem))
        precondition(IconLaunchReason.detect(event) == .user)
        event.setParam(NSAppleEventDescriptor(boolean:true),forKeyword:AEKeyword(keyAELaunchedAsServiceItem))
        precondition(IconLaunchReason.detect(event) == .background)
        let failing = IconVisibilityController(menu:true,dock:true) {_,_ in throw Failure.denied}
        var notified = false; failing.onChange = {notified=true}
        do { try failing.systemChanged(false); preconditionFailure("external save must fail") } catch {}
        precondition(!failing.menu && failing.dock && notified,"external removal remains live on failed save")
        print("PASS: four independent combinations, legacy migration, temporary recovery, restart, save failure, system removal and login event")
    }
}
