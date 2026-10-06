import AppKit
import PeerCore

final class UpdateWindow: NSWindowController {
    private let client = UpdateClient()
    private let currentVersion: ProductVersion?
    private let status = NSTextField(wrappingLabelWithString: "")
    private let notes = NSTextView()
    private let action = NSButton()
    private let retry = NSButton()
    private var destination: URL?
    private var task: URLSessionDataTask?
    init(version: String) {
        currentVersion = ProductVersion(version)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 450), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L10n.text("updates.title"); window.isReleasedWhenClosed = false; window.center()
        super.init(window: window)
        status.frame = NSRect(x: 24, y: 350, width: 472, height: 76)
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 100, width: 472, height: 235))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        notes.isEditable = false; notes.isRichText = false
        notes.font = .systemFont(ofSize: 13); notes.textContainerInset = NSSize(width: 10, height: 10)
        notes.isVerticallyResizable = true; notes.isHorizontallyResizable = false
        notes.autoresizingMask = [.width]; notes.frame = scroll.bounds
        notes.textContainer?.widthTracksTextView = true; scroll.documentView = notes
        let hint = NSTextField(wrappingLabelWithString: L10n.text("updates.install_hint"))
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 24, y: 54, width: 472, height: 38)
        retry.title = L10n.text("updates.retry"); retry.bezelStyle = .rounded
        retry.frame = NSRect(x: 24, y: 14, width: 145, height: 32); retry.target = self; retry.action = #selector(check)
        action.title = L10n.text("updates.open_release"); action.bezelStyle = .rounded
        action.frame = NSRect(x: 225, y: 14, width: 271, height: 32); action.target = self; action.action = #selector(openRelease)
        [status, scroll, hint, retry, action].forEach { window.contentView?.addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    func present() {
        showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
        if task == nil { check() }
    }
    @objc private func check() {
        guard task == nil else { return }
        action.isHidden = true; destination = nil; retry.isEnabled = false; notes.string = ""
        status.stringValue = L10n.text("updates.checking")
        guard currentVersion != nil else {
            status.stringValue = L10n.text("updates.invalid_local_version"); retry.isEnabled = true; return
        }
        task = client.check { [weak self] result in
            guard let self else { return }; self.task = nil; self.retry.isEnabled = true
            self.display(result)
        }
    }
    func display(_ result: Result<PublicRelease?, Error>) {
        guard let currentVersion else { return }
        action.isHidden = true; destination = nil; notes.string = ""
        switch result {
        case .failure(let error):
            status.stringValue = L10n.text("updates.failed", error.localizedDescription)
        case .success(nil):
            status.stringValue = L10n.text("updates.no_release")
            destination = UpdateResponse.releasesPage; action.isHidden = false
        case .success(let release?):
            notes.string = release.notes.isEmpty ? L10n.text("updates.no_notes") : release.notes
            if release.version > currentVersion {
                status.stringValue = L10n.text(release.hasInstaller ? "updates.available" : "updates.installer_pending", currentVersion.description, release.version.description)
                destination = release.page; action.isHidden = false
            } else {
                status.stringValue = L10n.text(release.version == currentVersion ? "updates.current" : "updates.ahead", currentVersion.description, release.version.description)
            }
        }
    }
    @objc private func openRelease() { if let destination { NSWorkspace.shared.open(destination) } }
}
