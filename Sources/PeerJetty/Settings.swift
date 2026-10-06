import AppKit
import PeerCore

final class SettingsController: NSWindowController {
    var onSave: ((String) -> Void)?
    var onSelect: ((String) -> Void)?
    var onPair: (() -> Void)?
    var onConnect: ((String) -> Void)?
    var onForget: ((String) -> Void)?
    var onFolder: (() -> Void)?
    var onSend: (() -> Void)?
    var onPreview: (() -> Void)?
    var onCancel: (() -> Void)?
    var onReveal: (() -> Void)?
    var onManual: (() -> Void)?
    var onPermissions: (() -> Void)?
    var onDiskAccess: (() -> Void)?
    var onAutoOpen: ((Bool) -> Void)?
    var onLogin: ((Bool) -> Void)?
    var onReset: (() -> Void)?
    var onQuit: (() -> Void)?
    private let name = NSTextField()
    private let devices = NSPopUpButton()
    private let folderLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "准备连接…")
    private let progressLabel = NSTextField(wrappingLabelWithString: "暂无传输")
    private let connectionLabel = NSTextField(wrappingLabelWithString: "")
    private let login = NSSwitch()
    private let autoOpen = NSSwitch()
    private var peers: [DiscoveredPeer] = []
    init(configuration: Configuration) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: min(810, (NSScreen.main?.visibleFrame.height ?? 900) - 70)), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "PeerJetty · 双向文件投放"; window.isReleasedWhenClosed = false; window.center()
        super.init(window: window)
        name.stringValue = configuration.name; folderLabel.stringValue = configuration.receivePath
        let title = NSTextField(labelWithString: configuration.onboardingComplete ? "设备与设置" : "欢迎使用双向文件投放")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let intro = NSTextField(wrappingLabelWithString: "两台 Mac 安装同一个 App，在同一局域网配对后即可互传。可信设备自动接收；默认只通知，可自行开启收到后自动打开。")
        intro.textColor = .secondaryLabelColor
        let version = NSTextField(labelWithString: AppVersion.summary)
        version.font = .systemFont(ofSize: 11); version.textColor = .secondaryLabelColor
        version.toolTip = AppVersion.details
        name.widthAnchor.constraint(greaterThanOrEqualToConstant: 290).isActive = true
        devices.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        folderLabel.lineBreakMode = .byTruncatingMiddle; folderLabel.maximumNumberOfLines = 2
        connectionLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular); connectionLabel.textColor = .secondaryLabelColor
        devices.target = self; devices.action = #selector(selectPeer)
        login.target = self; login.action = #selector(toggleLogin)
        autoOpen.target = self; autoOpen.action = #selector(toggleAutoOpen)
        autoOpen.state = configuration.autoOpenReceivedFiles ? .on : .off
        let openHint = NSTextField(wrappingLabelWithString: "开启后，已配对设备发来的文件保存成功就会用默认应用打开；文件夹在 Finder 打开。请只对信任的设备开启。")
        openHint.font = .systemFont(ofSize: 11); openHint.textColor = .secondaryLabelColor
        let rows: [NSView] = [title, intro,
            row([NSTextField(labelWithString: "本机名称"), name, button("保存 / 完成初始化", #selector(save))]),
            row([NSTextField(labelWithString: "接收目录"), button("选择文件夹…", #selector(chooseFolder))]), folderLabel,
            separator(), NSTextField(labelWithString: "设备列表（选择已配对设备即设为默认发送目标）"),
            row([devices, button("连接 / 配对", #selector(connect))]),
            row([button("添加设备 · 2 分钟", #selector(pair)), button("手动地址…", #selector(manual)), button("移除授权", #selector(forget))]),
            connectionLabel, separator(),
            row([button("选择文件发送…", #selector(send)), button("预览投放区", #selector(preview)), button("取消当前传输", #selector(cancel))]),
            progressLabel, button("在 Finder 中显示最近收到的文件", #selector(reveal)), separator(),
            row([NSTextField(labelWithString: "收到后自动打开"), autoOpen]), openHint,
            row([NSTextField(labelWithString: "登录时自动启动"), login, button("局域网权限…", #selector(permissions))]),
            row([button("微信文件访问权限…", #selector(diskAccess)), button("重置身份…", #selector(reset)), button("退出", #selector(quit))]),
            statusLabel, version]
        let stack = NSStackView(views: rows); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        let scroll = NSScrollView(frame: content.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let document = SettingsDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document; content.addSubview(scroll); document.addSubview(stack)
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                                     document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
                                     stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
                                     stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
                                     stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 25),
                                     stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)])
        for label in [intro, openHint, folderLabel, statusLabel, progressLabel, connectionLabel] { label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        for box in rows.compactMap({ $0 as? NSBox }) { box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        statusLabel.textColor = .secondaryLabelColor; statusLabel.maximumNumberOfLines = 3
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    private func row(_ views: [NSView]) -> NSStackView { let row = NSStackView(views: views); row.orientation = .horizontal; row.spacing = 10; row.alignment = .centerY; return row }
    private func button(_ title: String, _ action: Selector) -> NSButton { let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded; return button }
    private func separator() -> NSView { let box = NSBox(); box.boxType = .separator; return box }
    func updatePeers(_ peers: [DiscoveredPeer], preferred: String?) {
        let selected = devices.indexOfSelectedItem >= 0 && self.peers.indices.contains(devices.indexOfSelectedItem) ? self.peers[devices.indexOfSelectedItem].id : preferred
        self.peers = peers; devices.removeAllItems()
        for peer in peers { devices.addItem(withTitle: "\(peer.name) · \(peer.paired ? (peer.connected ? "已配对 / 在线" : "已配对 / 离线") : "可配对") · \(peer.id.prefix(6))") }
        if peers.isEmpty { devices.addItem(withTitle: "请在两台电脑上点击添加设备") }
        if let id = selected ?? preferred, let index = peers.firstIndex(where: { $0.id == id }) { devices.selectItem(at: index) }
    }
    private var selected: DiscoveredPeer? { peers.indices.contains(devices.indexOfSelectedItem) ? peers[devices.indexOfSelectedItem] : nil }
    func status(_ text: String) { statusLabel.stringValue = text }
    func folder(_ path: String) { folderLabel.stringValue = path }
    func connectionInfo(_ text: String) { connectionLabel.stringValue = text }
    func loginState(_ enabled: Bool) { login.state = enabled ? .on : .off }
    func autoOpenState(_ enabled: Bool) { autoOpen.state = enabled ? .on : .off }
    func progress(_ update: TransferUpdate) {
        let percent = update.total > 0 ? Int(Double(update.completed) / Double(update.total) * 100) : 0
        progressLabel.stringValue = "\(update.receiving ? "接收自" : "发送至") \(update.peerName) · \(update.status)\(update.finished ? "" : " · \(percent)%")"
    }
    @objc private func save() { onSave?(name.stringValue) }
    @objc private func selectPeer() { if let selected, selected.paired { onSelect?(selected.id) } }
    @objc private func connect() { if let selected { onConnect?(selected.id) } }
    @objc private func pair() { onPair?() }
    @objc private func forget() { if let selected, selected.paired { onForget?(selected.id) } }
    @objc private func chooseFolder() { onFolder?() }
    @objc private func send() { onSend?() }
    @objc private func preview() { onPreview?() }
    @objc private func cancel() { onCancel?() }
    @objc private func reveal() { onReveal?() }
    @objc private func manual() { onManual?() }
    @objc private func permissions() { onPermissions?() }
    @objc private func diskAccess() { onDiskAccess?() }
    @objc private func toggleAutoOpen() { onAutoOpen?(autoOpen.state == .on) }
    @objc private func toggleLogin() { onLogin?(login.state == .on) }
    @objc private func reset() { onReset?() }
    @objc private func quit() { onQuit?() }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
