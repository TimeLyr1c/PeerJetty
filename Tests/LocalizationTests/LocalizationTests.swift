import AppKit
@testable import PeerCore

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

@main
struct LocalizationChecks {
    static func main() throws {
        let en = TranslationCatalog(preferences: ["en-GB"])
        let zh = TranslationCatalog(preferences: ["zh-CN"])
        check(en.language == "en" && zh.language == "zh-Hans", "Regional language matching")
        check(TranslationCatalog(preferences: ["fr"]).language == "en", "English fallback")
        check(TranslationCatalog(preferences: ["fr", "zh-SG"]).language == "zh-Hans", "Second preferred supported language")
        check(en.text("receive.notification_count", 1) == "Received 1 item", "English singular")
        check(en.text("receive.notification_count", 2) == "Received 2 items", "English plural")
        check(zh.text("receive.notification_count", 1) == "收到 1 项文件", "Chinese count")
        check(en.text("receive.open_failures", 3, 1).contains("3 items saved; could not open 1 item"), "Independent plural variables")
        check(en.text("receive.partial_error", 2, "Example") == "Example (2 items saved)", "Positional plural")
        let device = "Mac 中文 %1$@ 🧪"
        check(en.text("drop.sending_peer", device) == "To " + device, "Device names and percent signs stay literal")
        check(zh.text("drop.sending_peer", device) == "发往 " + device, "No translation of user data")
        check(en.text("no.such.key") == "no.such.key", "Unknown key remains diagnosable")
        check(!L10n.percent(37).isEmpty, "Region-aware percent formatting")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("PeerJetty-Locale-\(UUID()).bundle")
        defer { try? FileManager.default.removeItem(at: scratch) }
        for language in ["en", "zh-Hans"] {
            let folder = scratch.appendingPathComponent("Contents/Resources/" + language + ".lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let table = language == "en" ? "\"fallback.test\" = \"English fallback\";" : "\"another.key\" = \"其他\";"
            try table.write(to: folder.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        }
        guard let partial = Bundle(url: scratch) else { fatalError("No partial catalog") }
        check(TranslationCatalog(bundle: partial, preferences: ["zh-Hans"]).text("fallback.test") == "English fallback", "Missing translation falls back to English")
        let suite = "PeerJetty-Language-Test-" + UUID().uuidString
        let isolatedDefaults = UserDefaults(suiteName: suite)!
        defer { isolatedDefaults.removePersistentDomain(forName: suite) }
        let preference = LanguagePreferences(defaults: isolatedDefaults)
        check(preference.selection == .system, "Existing installations follow system")
        preference.save(.english)
        check(LanguagePreferences(defaults: isolatedDefaults).selection == .english, "Language survives recreation")
        check(TranslationCatalog(preferences: preference.selection.preferences(systemLanguages: ["zh-Hans"])).language == "en", "App preference overrides system")
        preference.save(.simplifiedChinese)
        check(TranslationCatalog(preferences: preference.selection.preferences(systemLanguages: ["en"])).language == "zh-Hans", "Chinese override")
        preference.save(.system)
        check(preference.selection == .system && preference.selection.preferences(systemLanguages: ["en"]) == ["en"], "Restore system selection")
        isolatedDefaults.set("unknown-language", forKey: "PeerJettyDisplayLanguage")
        check(preference.selection == .system, "Invalid preference safely follows system")
        print("PASS: language selection, fallback, plurals, positional fields and literal user data")

        let diagnostic = "filestore.the_receive_folder_is_not_writable"
        check(en.remoteError(key: diagnostic, arguments: [], fallback: "legacy") == "The receive folder is not writable", "English remote error")
        check(zh.remoteError(key: diagnostic, arguments: [], fallback: "legacy") == "接收目录无法写入", "Chinese remote error")
        check(en.remoteError(key: diagnostic, arguments: ["extra"], fallback: "legacy") == "legacy", "Reject wrong argument count")
        check(en.remoteError(key: "receive.notification_count", arguments: ["%n"], fallback: "legacy") == "legacy", "Reject untrusted plural/type key")
        check(en.remoteError(key: "filestore.could_not_read_file", arguments: [String(repeating: "x", count: 4097)], fallback: "legacy") == "legacy", "Bound remote arguments")
        check(en.remoteError(key: nil, arguments: nil, fallback: "Old error") == "Old error", "Legacy text fallback")
        var reject = Message("reject"); reject.transfer = UUID(); reject.text = "The receive folder is not writable"
        reject.errorKey = diagnostic; reject.errorArguments = []
        struct LegacyMessage: Codable { let kind: String; let transfer: UUID?; let text: String? }
        let encoded = try JSONEncoder().encode(reject)
        let legacy = try JSONDecoder().decode(LegacyMessage.self, from: encoded)
        check(legacy.kind == "reject" && legacy.text == reject.text, "Legacy decoder ignores new optional fields")
        let old = try JSONEncoder().encode(LegacyMessage(kind: "reject", transfer: reject.transfer, text: "Old error"))
        let current = try JSONDecoder().decode(Message.self, from: old)
        check(current.errorKey == nil && current.errorArguments == nil && current.text == "Old error", "New decoder accepts legacy message")
        print("PASS: bounded bilingual diagnostics and legacy JSON compatibility")

        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        var configuration = Configuration(name: device, receivePath: "/isolated-test/Inbox")
        configuration.onboardingComplete = CommandLine.arguments.contains("--snapshot")
        let settings = SettingsController(configuration: configuration, displayLanguage: .english)
        guard let window = settings.window, let content = window.contentView else { fatalError("No settings view") }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        func page(_ section: SettingsSection) -> NSScrollView {
            descendants(content).first { $0.identifier?.rawValue == "settingsPage." + section.rawValue } as! NSScrollView
        }
        func control<T: NSView>(_ identifier: String, as type: T.Type) -> T {
            descendants(content).first { $0.identifier?.rawValue == identifier } as! T
        }
        let expectedGroups: [SettingsSection:Int] = [.general:4,.devices:3,.transfers:3,.text:3,.about:1]
        for section in SettingsSection.allCases {
            let groups = descendants(page(section)).filter { $0.identifier?.rawValue.hasPrefix("settingsGroup.") == true }
            check(groups.count == expectedGroups[section], "Settings pages retain intentional native groups")
        }
        let languagePicker = control("displayLanguage", as: NSPopUpButton.self)
        check(languagePicker.indexOfSelectedItem == 1, "Picker shows saved English preference")
        var changed: DisplayLanguage?
        settings.onLanguage = { changed = $0 }
        languagePicker.selectItem(at: 2)
        NSApp.sendAction(languagePicker.action!, to: languagePicker.target, from: languagePicker)
        check(changed == .simplifiedChinese, "Picker dispatches selected language")
        let historyEntry = control("textHistoryEntry", as: NSButton.self)
        let historyVisibility = control("textHistoryVisibility", as: NSSwitch.self)
        let retentionControl = control("textRetention", as: NSPopUpButton.self)
        check(!historyEntry.isHidden && historyVisibility.state == .on && retentionControl.indexOfSelectedItem == 0, "History upgrade defaults")
        settings.textHistoryState(false, retention: .thirtyDays)
        check(historyEntry.isHidden && historyVisibility.state == .off && retentionControl.indexOfSelectedItem == 1, "History callbacks survive category layout")
        settings.textHistoryState(true, retention: .latest500)
        var loginChanged: Bool?, autoOpenChanged: Bool?
        settings.onLogin = { loginChanged = $0 }; settings.onAutoOpen = { autoOpenChanged = $0 }
        for toggle in descendants(content).compactMap({ $0 as? NSSwitch }) {
            if let action = toggle.action, ["toggleLogin", "toggleAutoOpen"].contains(NSStringFromSelector(action)) {
                toggle.state = .on; NSApp.sendAction(action, to: toggle.target, from: toggle)
            }
        }
        check(loginChanged == true && autoOpenChanged == true, "General and transfer switches retain callbacks")
        let draft = control("deviceName", as: NSTextField.self)
        draft.stringValue = "Unsaved name 中文 🧪"
        check(window.makeFirstResponder(draft), "Name field accepts keyboard focus")
        let editor = draft.currentEditor() as! NSTextView
        editor.string = "Unsaved name 中文 🧪"
        for section in SettingsSection.allCases { settings.selectSection(section) }
        check(draft.stringValue == "Unsaved name 中文 🧪", "Switching pages retains unsaved edits")
        check(settings.selectedSection == .about, "Last page remains selected")
        for item in window.toolbar!.items {
            NSApp.sendAction(item.action!, to: item.target, from: item)
            check(window.toolbar!.selectedItemIdentifier == item.itemIdentifier, "Toolbar changes selected page")
        }
        check(window.toolbar!.items.count == 5, "Five native toolbar categories")
        let animationSwitch = control("interfaceAnimations", as:NSSwitch.self)
        check(animationSwitch.state == .on, "Animations enabled by default")
        var changedAnimation: Bool?
        settings.onAnimations = { changedAnimation=$0 }
        animationSwitch.state = .off; NSApp.sendAction(animationSwitch.action!,to:animationSwitch.target,from:animationSwitch)
        check(changedAnimation == false, "Animation switch callback")
        settings.animationState(true); check(animationSwitch.state == .on, "Failed save can restore animation choice")
        check(!descendants(window.contentView!).contains { $0.identifier?.rawValue == "animationSpeed" }, "speed selector removed")
        check(window.styleMask.contains(.resizable), "Settings can resize")
        check(window.contentMinSize == NSSize(width:640,height:440), "Readable minimum size")
        let titles = descendants(window.contentView!).compactMap {($0 as? NSButton)?.title}
        check(!titles.contains("Preview animations…") && !titles.contains("预览动画…") && !titles.contains("Preview drop card") && !titles.contains("预览投放区"), "No production preview entries")
        let menuSwitch = control("menuBarVisibility", as:NSSwitch.self)
        check(menuSwitch.state == .on, "Menu icon defaults visible")
        var visibilityChanged:Bool?
        settings.onMenuBar = { visibilityChanged=$0 }
        menuSwitch.state = .off; NSApp.sendAction(menuSwitch.action!,to:menuSwitch.target,from:menuSwitch)
        check(visibilityChanged == false, "Visibility control callback")
        settings.iconState(menu:false,dock:false,temporary:true)
        let dockSwitch = control("dockVisibility",as:NSSwitch.self)
        check(menuSwitch.state == .off && dockSwitch.state == .off && !control("temporaryIconNotice",as:NSStackView.self).isHidden,"temporary visibility does not change saved switches")
        var dockChanged:Bool?; settings.onDock = {dockChanged=$0}
        dockSwitch.state = .on; NSApp.sendAction(dockSwitch.action!,to:dockSwitch.target,from:dockSwitch)
        check(dockChanged == true && menuSwitch.state == .off,"Dock callback is independent")
        var hiddenTemporary=false; settings.onHideTemporary = {hiddenTemporary=true}
        control("hideTemporaryIcon",as:NSButton.self).performClick(nil)
        check(hiddenTemporary,"temporary hide action available")
        settings.iconState(menu:true,dock:false,temporary:false)
        check(menuSwitch.state == .on && control("temporaryIconNotice",as:NSStackView.self).isHidden,"preference UI rollback")
        let connectionGroup = control("connectionInfoGroup",as:NSStackView.self)
        let connectionToggle = control("connectionInfoToggle",as:NSButton.self)
        check(connectionGroup.isHidden && control("connectionInfo",as:NSTextField.self).stringValue == L10n.text("settings.connection_not_ready"), "Connection info starts collapsed and nonempty")
        connectionToggle.performClick(nil); check(!connectionGroup.isHidden, "Connection details disclosure")
        connectionToggle.performClick(nil)
        let latest = control("latestTextEntry",as:NSButton.self)
        check(!latest.isEnabled,"No recent text before receipt")
        settings.latestTextState(true); check(latest.isEnabled,"Received text entry available")
        settings.status(String(repeating:"Long warning 中文🙂 ",count:100))
        check(!control("settingsStatusDetails",as:NSButton.self).isHidden,"Full long-warning details are accessible")
        let fullWarning = String(repeating:"Long warning 中文🙂\n",count:100)
        let details = SettingsController.detailContent(fullWarning)
        let detailsText = details.documentView as! NSTextView
        check(detailsText.string == fullWarning && !detailsText.isEditable && !detailsText.isRichText && details.hasVerticalScroller && !detailsText.isAutomaticLinkDetectionEnabled,"Full warning retains plain Unicode text in a scrollable read-only view")
        settings.status("Ready");check(control("settingsStatusDetails",as:NSButton.self).isHidden,"Short status stays compact")
        check(control("productVersion",as:NSTextField.self).stringValue == AppVersion.summary && AppVersion.summary(info:["CFBundleShortVersionString":"0.4.0","CFBundleVersion":"15"]) == L10n.text("appversion.version","0.4.0"),"Normal version is compact")
        let maintenance = control("settingsMaintenance", as: NSStackView.self)
        let disclosure = control("settingsMaintenanceToggle", as: NSButton.self)
        check(maintenance.isHidden, "Maintenance starts collapsed")
        disclosure.performClick(nil); check(!maintenance.isHidden, "Maintenance opens")
        disclosure.performClick(nil); check(maintenance.isHidden, "Maintenance closes")
        let peer = DiscoveredPeer(id: "isolated-peer", name: "Office Mac — Shared workspace 中文 🧪", paired: true, connected: false)
        settings.updatePeers([], preferred: nil)
        settings.updatePeers([peer], preferred: peer.id)
        check(control("devicePicker", as: NSPopUpButton.self).titleOfSelectedItem?.contains(peer.name) == true, "Offline trusted device remains visible")
        settings.folder("/isolated-test/Very long folder name/Design resources/Received files/中文目录")
        settings.connectionInfo("192.0.2.1 / 2001:db8::1 · 12345")
        settings.progress(TransferUpdate(id: UUID(), peerName: peer.name, receiving: false, completed: 50, total: 100, status: "Transferring", finished: false, succeeded: false))
        settings.status("Isolated UI check")
        var fired = Set<String>()
        settings.onSave = { check($0 == draft.stringValue, "Save receives retained draft"); fired.insert("save") }
        settings.onPair = { fired.insert("pair") }; settings.onManual = { fired.insert("manual") }
        settings.onConnect = { check($0 == peer.id, "Connect ID"); fired.insert("connect") }
        settings.onForget = { check($0 == peer.id, "Forget ID"); fired.insert("forget") }
        settings.onFolder = { fired.insert("folder") }; settings.onSend = { fired.insert("send") }
        settings.onCancel = { fired.insert("cancel") }
        settings.onReveal = { fired.insert("reveal") }; settings.onPermissions = { fired.insert("permissions") }
        settings.onTextHistory = { fired.insert("history") }; settings.onClearTextHistory = { fired.insert("clearHistory") }
        settings.onLatestText = { fired.insert("latestText") }; settings.onSendText = { fired.insert("sendText") }; settings.onUpdates = { fired.insert("updates") }
        settings.onReset = { fired.insert("reset") }; settings.onQuit = { fired.insert("quit") }
        let expected: [String: String] = ["save":"save", "pair":"pair", "manual":"manual", "connect":"connect", "forget":"forget",
            "chooseFolder":"folder", "send":"send", "cancel":"cancel", "reveal":"reveal", "permissions":"permissions",
            "openLatestText":"latestText", "openTextHistory":"history", "clearTextHistory":"clearHistory", "sendText":"sendText", "checkUpdates":"updates", "reset":"reset", "quit":"quit"]
        for button in descendants(content).compactMap({ $0 as? NSButton }) {
            if let action = button.action, expected[NSStringFromSelector(action)] != nil { NSApp.sendAction(action, to: button.target, from: button) }
        }
        check(fired == Set(expected.values), "All existing action buttons remain wired to callbacks")
        var hiddenHistory: Bool?, selectedRetention: TextRetention?
        settings.onTextHistoryVisibility = { hiddenHistory = $0 }; settings.onTextRetention = { selectedRetention = $0 }
        historyVisibility.state = .off; NSApp.sendAction(historyVisibility.action!, to: historyVisibility.target, from: historyVisibility)
        retentionControl.selectItem(at: 1); NSApp.sendAction(retentionControl.action!, to: retentionControl.target, from: retentionControl)
        check(hiddenHistory == false && selectedRetention == .thirtyDays, "Text preferences dispatch callbacks")
        settings.textHistoryState(true, retention: .latest500)
        let snapshotIndex = CommandLine.arguments.firstIndex(of: "--snapshot")
        let snapshot = snapshotIndex.flatMap { CommandLine.arguments.count > $0 + 1 ? URL(fileURLWithPath: CommandLine.arguments[$0 + 1]) : nil }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for height: CGFloat in [580, 440] {
                window.setContentSize(NSSize(width: height == 580 ? 720 : 640, height: height))
                window.displayIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
                check(abs(content.bounds.height - height) <= 1, "Window keeps requested content height")
                for section in SettingsSection.allCases {
                    settings.selectSection(section); window.displayIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                    content.layoutSubtreeIfNeeded()
                    let scroll = page(section), document = scroll.documentView!
                    document.layoutSubtreeIfNeeded()
                    let stack = document.subviews.first as! NSStackView
                    check(document.frame.width <= scroll.contentView.bounds.width + 1, "No horizontal scrolling")
                    check(abs(scroll.contentView.bounds.minY) <= 1, "Selected page starts at its top")
                    check(document.frame.height >= scroll.contentView.bounds.height - 1, "Short screens scroll vertically")
                    for view in descendants(stack) where !view.isHiddenOrHasHiddenAncestor {
                        let frame = view.convert(view.bounds, to: document)
                        check(frame.minX >= -1 && frame.maxX <= document.bounds.maxX + 1, "Category control fits document: " + section.rawValue)
                        if let button = view as? NSButton {
                            check(button.frame.width >= button.intrinsicContentSize.width - 1, "Translated button is not clipped: " + button.title)
                        }
                    }
                    check(SettingsSection.allCases.filter { !page($0).isHidden } == [section], "Exactly one page is visible")
                    if let snapshot {
                        let frameView = content.superview ?? content
                        frameView.layoutSubtreeIfNeeded()
                        let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds)!
                        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
                        let suffix = appearance == .aqua ? "light" : "dark"
                        let filename = snapshot.deletingPathExtension().lastPathComponent + "-" + section.rawValue + "-" + suffix + (height == 440 ? "-short" : "") + ".png"
                        try bitmap.representation(using: .png, properties: [:])!.write(to: snapshot.deletingLastPathComponent().appendingPathComponent(filename))
                    }
                }
            }
        }
        settings.selectSection(.general)
        check(draft.stringValue == "Unsaved name 中文 🧪", "Layout and callbacks do not replace draft")
        print("PASS: " + L10n.language + " categorized settings, callbacks, drafts, history, toolbar and 20 light/dark/short-screen layouts")
        if let index = CommandLine.arguments.firstIndex(of: "--app"), CommandLine.arguments.count > index + 1 {
            check(L10n.resources.bundleURL == Bundle.main.bundleURL, "Relocated app uses main resources, not build resources")
            guard let app = Bundle(path: CommandLine.arguments[index + 1]) else { fatalError("No packaged bundle") }
            for language in ["en", "zh-Hans"] {
                let catalog = TranslationCatalog(bundle: app, preferences: [language])
                check(catalog.text("receive.notification_count", 2) == (language == "en" ? "Received 2 items" : "收到 2 项文件"), "Packaged plural resources")
                for resource in ["Localizable.strings", "Localizable.stringsdict", "InfoPlist.strings"] {
                    check(FileManager.default.fileExists(atPath: app.resourceURL!.appendingPathComponent(language + ".lproj/" + resource).path), "Packaged language resource")
                }
            }
            check(app.infoDictionary?["CFBundleDevelopmentRegion"] as? String == "en", "Packaged fallback language")
            let purpose = Bundle.main.localizedInfoDictionary?["NSLocalNetworkUsageDescription"] as? String
            check(purpose?.contains(L10n.language == "en" ? "Discover" : "发现") == true, "Native localized permission description")
            print("PASS: relocated app runtime language and native permission resources")
        }
    }
}
