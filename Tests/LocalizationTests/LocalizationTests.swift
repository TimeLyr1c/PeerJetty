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
        let settings = SettingsController(configuration: Configuration(name: device, receivePath: "/isolated-test/Inbox"), displayLanguage: .english)
        guard let window = settings.window, let content = window.contentView else { fatalError("No settings view") }
        window.appearance = NSAppearance(named: .aqua)
        content.wantsLayer = true; content.layer?.backgroundColor = NSColor.white.cgColor
        window.setContentSize(NSSize(width: 650, height: 600))
        content.layoutSubtreeIfNeeded()
        guard let scroll = content.subviews.first as? NSScrollView, let document = scroll.documentView,
              let stack = document.subviews.first as? NSStackView else { fatalError("No scrolling form") }
        document.layoutSubtreeIfNeeded()
        check(document.frame.width <= scroll.contentView.bounds.width + 1, "Settings must not scroll horizontally")
        check(stack.frame.width <= document.bounds.width, "Form fits document")
        for row in stack.arrangedSubviews {
            let rowInDocument = stack.convert(row.frame, to: document)
            check(rowInDocument.minX >= -1 && rowInDocument.maxX <= document.bounds.maxX + 1, "Row fits visible document")
            if let horizontal = row as? NSStackView {
                for item in horizontal.arrangedSubviews {
                    let itemInDocument = item.convert(item.bounds, to: document)
                    check(itemInDocument.minX >= -1 && itemInDocument.maxX <= document.bounds.maxX + 1, "Control fits visible document")
                    if let button = item as? NSButton {
                        check(button.frame.width >= button.intrinsicContentSize.width - 1, "Translated button is not clipped")
                    }
                }
            }
        }
        let languagePicker = stack.arrangedSubviews.compactMap { $0 as? NSStackView }
            .flatMap { $0.arrangedSubviews }.first { $0.identifier?.rawValue == "displayLanguage" } as? NSPopUpButton
        check(languagePicker?.indexOfSelectedItem == 1, "Picker shows saved English preference")
        var changed: DisplayLanguage?
        settings.onLanguage = { changed = $0 }
        languagePicker?.selectItem(at: 2)
        if let picker = languagePicker, let action = picker.action { NSApp.sendAction(action, to: picker.target, from: picker) }
        check(changed == .simplifiedChinese, "Picker dispatches selected language")
        check(document.frame.height >= scroll.contentView.bounds.height, "Scrollable short screen")
        func descendants(_ view:NSView) -> [NSView] { [view] + view.subviews.flatMap {descendants($0)} }
        let controls = descendants(document)
        let historyEntry = controls.first {$0.identifier?.rawValue == "textHistoryEntry"} as! NSButton
        let historyVisibility = controls.first {$0.identifier?.rawValue == "textHistoryVisibility"} as! NSSwitch
        let retentionControl = controls.first {$0.identifier?.rawValue == "textRetention"} as! NSPopUpButton
        check(!historyEntry.isHidden && historyVisibility.state == .on && retentionControl.indexOfSelectedItem == 0,"History settings upgrade defaults")
        settings.textHistoryState(false,retention:.thirtyDays)
        check(historyEntry.isHidden && historyVisibility.state == .off && retentionControl.indexOfSelectedItem == 1,"Hidden history entry and persisted retention selection")
        settings.textHistoryState(true,retention:.latest500)
        print("PASS: " + L10n.language + " settings layout at 650×600")
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot-bottom"), CommandLine.arguments.count > index+1 {
            content.layoutSubtreeIfNeeded()
            scroll.contentView.scroll(to:NSPoint(x:0,y:max(0,document.bounds.height-scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
            let bitmap = content.bitmapImageRepForCachingDisplay(in:content.bounds)!
            content.cacheDisplay(in:content.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
            guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { fatalError("No bitmap") }
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
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
