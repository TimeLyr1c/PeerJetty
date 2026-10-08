import AppKit
import PeerCore

/// Keep the native status item alive: AppKit owns visibility persistence and system removal.
final class MenuBarController {
    enum Action: CaseIterable { case pair, sendFiles, sendText, updates, settings, quit }
    static let entries: [(Action, String)] = [(.pair,"application.menu_pair"), (.sendFiles,"settings.choose_files_to_send"), (.sendText,"text.send_title"), (.updates,"updates.title"), (.settings,"application.menu_settings"), (.quit,"settings.quit")]
    let item: NSStatusItem
    var onVisibility: ((Bool) -> Void)?
    private var observation: NSKeyValueObservation?
    private var lastVisibility = true
    private var commands: [MenuCommand] = []
    var isVisible: Bool { item.isVisible }
    static func activationPolicy(visible: Bool) -> NSApplication.ActivationPolicy { visible ? .accessory : .regular }
    init(autosaveName: String = "PeerJetty.MainStatusItem", actions: [Action: () -> Void]) {
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item.autosaveName = autosaveName
        item.behavior = [.removalAllowed] // Never terminate transfers when the icon is removed.
        item.button?.image = NSImage(systemSymbolName:"arrow.up.arrow.down.square", accessibilityDescription:L10n.text("application.file_handoff"))
        let menu = NSMenu()
        for (action,key) in Self.entries {
            let command = MenuCommand(actions[action] ?? {}); commands.append(command)
            let entry = NSMenuItem(title:L10n.text(key),action:#selector(MenuCommand.invoke),keyEquivalent:action == .settings ? "," : action == .quit ? "q" : "")
            entry.target = command; menu.addItem(entry)
        }
        item.menu = menu
        lastVisibility = item.isVisible
        observation = item.observe(\.isVisible, options:[.new]) { [weak self] item,_ in
            guard let self, self.lastVisibility != item.isVisible else { return }
            self.lastVisibility = item.isVisible; self.onVisibility?(item.isVisible)
        }
    }
    func setVisible(_ value: Bool) { if item.isVisible != value { item.isVisible = value } }
    deinit { observation?.invalidate(); NSStatusBar.system.removeStatusItem(item) }
}
private final class MenuCommand: NSObject {
    private let action: () -> Void
    init(_ action:@escaping () -> Void) { self.action=action }
    @objc func invoke() { action() }
}
