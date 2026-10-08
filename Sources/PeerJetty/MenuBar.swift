import AppKit
import PeerCore
import CoreServices

/// Keep the native item alive; AppKit restores position and reports external visibility changes.
final class MenuBarController {
    enum Action: CaseIterable { case pair, sendFiles, sendText, updates, settings, quit }
    static let entries: [(Action, String)] = [(.pair,"application.menu_pair"), (.sendFiles,"settings.choose_files_to_send"), (.sendText,"text.send_title"), (.updates,"updates.title"), (.settings,"application.menu_settings"), (.quit,"settings.quit")]
    let item: NSStatusItem
    var onVisibility: ((Bool) -> Void)?
    private var observation: NSKeyValueObservation?
    private var lastVisibility = true
    private var settingVisibility = false
    private var commands: [MenuCommand] = []
    var isVisible: Bool { item.isVisible }
    static func activationPolicy(dockVisible: Bool) -> NSApplication.ActivationPolicy { dockVisible ? .regular : .accessory }
    init(autosaveName: String = "PeerJetty.MainStatusItem", actions: [Action: () -> Void]) {
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item.autosaveName = autosaveName
        item.behavior = [.removalAllowed] // Never terminate transfers when the icon is removed.
        item.button?.image = NSImage(systemSymbolName:"arrow.up.arrow.down.square", accessibilityDescription:L10n.text("application.file_handoff"))
        item.button?.image = item.button?.image?.withSymbolConfiguration(.init(pointSize:18, weight:.medium))
        item.button?.image?.isTemplate = true
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
            self.lastVisibility = item.isVisible
            if !self.settingVisibility { self.onVisibility?(item.isVisible) }
        }
    }
    func setVisible(_ value: Bool) {
        settingVisibility = true; defer { settingVisibility = false }
        if item.isVisible != value { item.isVisible = value }
    }
    deinit { observation?.invalidate(); NSStatusBar.system.removeStatusItem(item) }
}
private final class MenuCommand: NSObject {
    private let action: () -> Void
    init(_ action:@escaping () -> Void) { self.action=action }
    @objc func invoke() { action() }
}

/// Persist user preferences independently of AppKit restoration and per-run recovery.
final class IconVisibilityController {
    private(set) var menu: Bool
    private(set) var dock: Bool
    private(set) var temporary = false
    var effectiveMenu: Bool { menu || temporary }
    var onChange: (() -> Void)?
    private let save: (Bool, Bool) throws -> Void
    init(menu: Bool, dock: Bool, save: @escaping (Bool, Bool) throws -> Void) {
        self.menu = menu; self.dock = dock; self.save = save
    }
    static func migrated(_ config: Configuration, nativeMenu: Bool) -> (Bool, Bool) {
        (config.showMenuBarIcon ?? nativeMenu, config.showDockIcon ?? !nativeMenu)
    }
    func setMenu(_ value: Bool) throws {
        try save(value, dock); menu = value; temporary = false; onChange?()
    }
    func setDock(_ value: Bool) throws {
        try save(menu, value); dock = value; onChange?()
    }
    func recover() {
        guard !effectiveMenu && !dock else { return }
        temporary = true; onChange?()
    }
    func hideTemporary() { temporary = false; onChange?() }
    func systemChanged(_ value: Bool) throws {
        if temporary && !value { hideTemporary(); return }
        // Keep the live system choice even if persistence fails; report the failure.
        menu = value; temporary = false; defer { onChange?() }
        try save(menu, dock)
    }
}

enum IconLaunchReason {
    case user, background, unknown
    static func detect(_ event: NSAppleEventDescriptor?) -> Self {
        guard let event else { return .unknown }
        if event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem))?.booleanValue == true ||
            event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsServiceItem))?.booleanValue == true { return .background }
        if event.eventClass == AEEventClass(kCoreEventClass),
           event.eventID == AEEventID(kAEOpenApplication) || event.eventID == AEEventID(kAEReopenApplication) { return .user }
        return .unknown
    }
}
