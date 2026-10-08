import AppKit
import PeerCore

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
        precondition(bar.item.menu!.items.count == 6,"exactly six menu entries")
        precondition(bar.item.menu!.items.map(\.title) == MenuBarController.entries.map {L10n.text($0.1)})
        precondition(bar.item.behavior.contains(.removalAllowed) && !bar.item.behavior.contains(.terminationOnRemoval))
        for entry in bar.item.menu!.items { NSApp.sendAction(entry.action!,to:entry.target,from:entry) }
        precondition(fired == MenuBarController.Action.allCases,"all six actions wired")
        var values:[Bool] = [];bar.onVisibility = {values.append($0)}
        bar.setVisible(true);bar.item.isVisible = false;bar.setVisible(true)
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        precondition(values.suffix(2) == [false,true],"system and settings changes observed")
        precondition(MenuBarController.activationPolicy(visible:false) == .regular && MenuBarController.activationPolicy(visible:true) == .accessory,"Dock recovery policy")
        if let id=Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName:id) }
        print("PASS: six native menu actions, removability, visibility KVO and Dock policy")
    }
}
