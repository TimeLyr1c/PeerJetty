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
    var onSelectTarget: ((String) -> Void)?
    private let destinations = NSMenuItem(title:L10n.text("targets.menu"),action:nil,keyEquivalent:"")
    private var targetCommands: [MenuCommand] = []
    /// A read-only line above the actions; hidden while nothing is moving.
    private let activityItem = NSMenuItem(title:"",action:nil,keyEquivalent:"")
    private let activitySeparator = NSMenuItem.separator()
    static let idleSymbol = "arrow.up.arrow.down.square", busySymbol = "arrow.up.arrow.down.square.fill"
    var isVisible: Bool { item.isVisible }
    static func activationPolicy(dockVisible: Bool) -> NSApplication.ActivationPolicy { dockVisible ? .regular : .accessory }
    init(autosaveName: String = "PeerJetty.MainStatusItem", actions: [Action: () -> Void]) {
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item.autosaveName = autosaveName
        item.behavior = [.removalAllowed] // Never terminate transfers when the icon is removed.
        setSymbol(Self.idleSymbol)
        let menu = NSMenu()
        for (action,key) in Self.entries {
            let command = MenuCommand(actions[action] ?? {}); commands.append(command)
            let entry = NSMenuItem(title:L10n.text(key),action:#selector(MenuCommand.invoke),keyEquivalent:action == .settings ? "," : action == .quit ? "q" : "")
            entry.target = command; menu.addItem(entry)
        }
        destinations.submenu=NSMenu();menu.insertItem(destinations,at:2)
        activityItem.isEnabled = false; activityItem.isHidden = true; activitySeparator.isHidden = true
        menu.insertItem(activitySeparator,at:0); menu.insertItem(activityItem,at:0)
        updateTargets([],preferred:nil)
        item.menu = menu
        lastVisibility = item.isVisible
        observation = item.observe(\.isVisible, options:[.new]) { [weak self] item,_ in
            guard let self, self.lastVisibility != item.isVisible else { return }
            self.lastVisibility = item.isVisible
            if !self.settingVisibility { self.onVisibility?(item.isVisible) }
        }
    }
    func updateTargets(_ peers:[DiscoveredPeer],preferred:String?) {
        targetCommands=[];let submenu=NSMenu()
        let paired=peers.filter(\.paired).sorted{$0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending}
        for peer in paired {
            let command=MenuCommand { [weak self] in self?.onSelectTarget?(peer.id) };targetCommands.append(command)
            // The short ID only tells apart devices that share a name.
            let duplicate=paired.filter{$0.name == peer.name}.count > 1
            let entry=NSMenuItem(title:peer.name+" · "+L10n.text(peer.connected ? "targets.connected" : "targets.offline")+(duplicate ? " · "+String(peer.id.prefix(6)) : ""),action:#selector(MenuCommand.invoke),keyEquivalent:"")
            entry.target=command;entry.state=peer.id == preferred ? .on : .off;submenu.addItem(entry)
        }
        if paired.isEmpty {let entry=NSMenuItem(title:L10n.text("targets.empty"),action:nil,keyEquivalent:"");entry.isEnabled=false;submenu.addItem(entry)}
        destinations.submenu=submenu
    }
    /// Shows the newest active transfer, or hides the line and restores the idle symbol.
    func activity(_ update: TransferUpdate?) {
        guard let update, !update.finished else {
            activityItem.isHidden = true; activitySeparator.isHidden = true; setSymbol(Self.idleSymbol); return
        }
        let waiting = update.total > 0 && update.completed >= update.total
        let detail = waiting ? L10n.text("drop.waiting_confirmation") : update.total > 0 ? L10n.percent(Int(Double(update.completed) / Double(update.total) * 100)) : update.status
        activityItem.title = L10n.text(update.receiving ? "settings.receiving_progress" : "settings.sending_progress", update.peerName, detail)
        activityItem.isHidden = false; activitySeparator.isHidden = false; setSymbol(Self.busySymbol)
    }
    var activityText: String? { activityItem.isHidden ? nil : activityItem.title }
    private func setSymbol(_ name: String) {
        guard currentSymbol != name else { return }
        currentSymbol = name
        let image = NSImage(systemSymbolName:name, accessibilityDescription:L10n.text("application.file_handoff"))?.withSymbolConfiguration(.init(pointSize:18, weight:.medium))
        image?.isTemplate = true; item.button?.image = image
    }
    private(set) var currentSymbol = ""
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
