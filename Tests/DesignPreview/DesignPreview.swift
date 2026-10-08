import AppKit
@testable import PeerCore

/// Two separately compiled native previews. Never constructs PeerEngine or a store.
@main final class DesignPreview: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var controls: NSWindow!
    private var settings: SettingsController!
    private var motion: MotionPreviewWindow!
    private let side = NSSegmentedControl(labels: [L10n.text("design.before"), L10n.text("design.after")], trackingMode: .selectOne, target: nil, action: nil)
    private let language = NSPopUpButton()
    static func main() {
        let app = NSApplication.shared
        let delegate = DesignPreview(); app.delegate = delegate
        app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(), item = NSMenuItem(), submenu = NSMenu()
        submenu.addItem(withTitle: L10n.text("design.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item); NSApp.mainMenu = menu
        var config = Configuration(name:"Preview Mac — 中文", receivePath:"/Preview/Inbox")
        config.onboardingComplete = true
        settings = SettingsController(configuration:config,displayLanguage:L10n.language == "zh-Hans" ? .simplifiedChinese : .english)
        settings.updatePeers([DiscoveredPeer(id:"preview-peer",name:"Office Mac mini — Paired device 中文",paired:true,connected:true)],preferred:"preview-peer")
        settings.connectionInfo("192.0.2.1 · 12345")
        settings.status(L10n.text("design.isolated"))
        motion = MotionPreviewWindow()
        settings.onMotionPreview = { [weak self] in self?.showMotion() }
        settings.onPreview = { [weak self] in self?.showMotion() }
        settings.onSave = { [weak self] _ in self?.settings.status(L10n.text("design.isolated")) }
        settings.onQuit = { NSApp.terminate(nil) }
        // Switches change only this isolated process, never production preferences.
        var menuVisible = true, dockVisible = false
        settings.onMenuBar = { [weak self] value in menuVisible=value; self?.settings.iconState(menu:menuVisible,dock:dockVisible,temporary:false) }
        settings.onDock = { [weak self] value in dockVisible=value; self?.settings.iconState(menu:menuVisible,dock:dockVisible,temporary:false) }
        settings.onAnimations = { value in MotionPolicy.shared.enabled=value }
        settings.onAnimationSpeed = { value in MotionPolicy.shared.speed=value }
        controls = NSWindow(contentRect:NSRect(x:0,y:0,width:650,height:115),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        controls.title = L10n.text("design.title"); controls.isReleasedWhenClosed=false; controls.delegate=self
        let content=controls.contentView!
        let status=NSTextField(wrappingLabelWithString:L10n.text("design.isolated")); status.font = .systemFont(ofSize:12); status.textColor = .secondaryLabelColor
        side.selectedSegment = Bundle.main.object(forInfoDictionaryKey:"PJComparisonSide") as? String == "Before" ? 0 : 1
        side.target=self;side.action=#selector(switchVersion)
        language.addItems(withTitles:["English","简体中文"]); language.selectItem(at:L10n.language == "zh-Hans" ? 1 : 0)
        language.target=self;language.action=#selector(switchVersion)
        let settingButton=NSButton(title:L10n.text("settings.window_title"),target:self,action:#selector(showSettings));settingButton.bezelStyle = .rounded
        let motionButton=NSButton(title:L10n.text("settings.motion_preview"),target:self,action:#selector(showMotion));motionButton.bezelStyle = .rounded
        let row=NSStackView(views:[side,language,settingButton,motionButton]);row.spacing=12
        let stack=NSStackView(views:[row,status]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-20),stack.topAnchor.constraint(equalTo:content.topAnchor,constant:16)])
        status.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        controls.center()
        if let screen=NSScreen.main { controls.setFrameOrigin(NSPoint(x:screen.visibleFrame.midX-325,y:screen.visibleFrame.maxY-controls.frame.height-20)) }
        controls.makeKeyAndOrderFront(nil); showSettings(); NSApp.activate(ignoringOtherApps:true)
    }
    @objc private func showSettings() {
        settings.showWindow(nil);settings.window?.makeKeyAndOrderFront(nil)
        if let controls { settings.window?.setFrameTopLeftPoint(NSPoint(x:controls.frame.minX,y:controls.frame.minY-14)) }
    }
    @objc private func showMotion() { motion.present() }
    @objc private func switchVersion() {
        let destination=Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(side.selectedSegment == 0 ? "Before.app" : "After.app")
        let config=NSWorkspace.OpenConfiguration(); config.createsNewApplicationInstance=true
        config.arguments=["-AppleLanguages",language.indexOfSelectedItem == 1 ? "(zh-Hans)" : "(en)"]
        NSWorkspace.shared.openApplication(at:destination,configuration:config) { _,error in
            DispatchQueue.main.async {
                if error == nil { NSApp.terminate(nil) }
                else { let alert=NSAlert();alert.messageText=L10n.text("design.launch_failed");alert.runModal() }
            }
        }
    }
    func windowWillClose(_ notification:Notification) { NSApp.terminate(nil) }
}
