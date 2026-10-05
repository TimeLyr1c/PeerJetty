import AppKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

private enum AppConfig {
    static let targetKey = "sshTarget"
    static let defaultTarget = "username@Mac-mini.local"
    static let fallbackNotchWidth: CGFloat = 210
    static let fallbackNotchHeight: CGFloat = 32
    static let extensionHeight: CGFloat = 46
}

private enum TransferError: LocalizedError {
    case commandFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message), .invalidResponse(let message):
            return message
        }
    }
}

private enum DragDiagnostics {
    static let logURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("OpenOnMini-drag.log")

    static func reset() {
        try? Data().write(to: logURL, options: .atomic)
        record("launch")
    }

    static func record(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: data)
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            NSLog("OpenOnMini diagnostics failed: %@", error.localizedDescription)
        }
    }

    static func describe(_ pasteboard: NSPasteboard) -> String {
        let types = pasteboard.types?.map(\.rawValue).sorted().joined(separator: ", ") ?? "none"
        return "pasteboard types=[\(types)] items=\(pasteboard.pasteboardItems?.count ?? 0)"
    }

}

private enum DragPayload {
    private static let fileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true
    ]

    private static let filePromiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map {
        NSPasteboard.PasteboardType($0)
    }

    static var registeredTypes: [NSPasteboard.PasteboardType] {
        [.fileURL] + filePromiseTypes
    }

    static func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: fileURLReadingOptions
        ) {
            return true
        }

        return pasteboard.availableType(from: filePromiseTypes) != nil
    }
}

private final class CommandRunner {
    struct Output {
        let standardOutput: String
        let standardError: String
    }

    static func run(
        _ executable: String,
        arguments: [String],
        standardInput: Data? = nil
    ) throws -> Output {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        if standardInput != nil {
            process.standardInput = stdin
        }

        try process.run()

        if let standardInput {
            stdin.fileHandleForWriting.write(standardInput)
            try? stdin.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        let outputText = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let errorText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TransferError.commandFailed(
                detail.isEmpty ? "命令执行失败（状态码 \(process.terminationStatus)）" : detail
            )
        }

        return Output(standardOutput: outputText, standardError: errorText)
    }
}

private final class TransferService {
    enum Result {
        case opened
        case revealed
        case sentButCouldNotOpen
    }

    private let sshOptions = [
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=8"
    ]

    func testConnection(target: String) throws {
        _ = try CommandRunner.run(
            "/usr/bin/ssh",
            arguments: sshOptions + [target, "true"]
        )
    }

    func send(_ localURL: URL, target: String) throws -> Result {
        let didAccess = localURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                localURL.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw TransferError.invalidResponse("找不到文件：\(localURL.lastPathComponent)")
        }

        let tempOutput = try CommandRunner.run(
            "/usr/bin/ssh",
            arguments: sshOptions + [target, "mktemp -d /tmp/open-from-macbook.XXXXXX"]
        )
        let remoteTemp = tempOutput.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard remoteTemp.hasPrefix("/tmp/open-from-macbook.") else {
            throw TransferError.invalidResponse("Mac mini 没有返回有效的临时目录")
        }

        do {
            _ = try CommandRunner.run(
                "/usr/bin/scp",
                arguments: [
                    "-p", "-r", "-q", "--",
                    localURL.path,
                    "\(target):\(remoteTemp)/"
                ]
            )
        } catch {
            try? cleanup(remoteTemp: remoteTemp, target: target)
            throw error
        }

        let encodedName = Data(localURL.lastPathComponent.utf8).base64EncodedString()
        let remoteScript = #"""
        set -e

        temp_dir="$1"
        encoded_name="$2"
        filename="$(printf '%s' "$encoded_name" | /usr/bin/base64 -D)"
        source_path="$temp_dir/$filename"
        downloads="$HOME/Downloads"
        destination="$downloads/$filename"

        mkdir -p "$downloads"

        if [[ -e "$destination" || -L "$destination" ]]; then
            if [[ -d "$source_path" ]]; then
                stem="$filename"
                suffix=""
            elif [[ "$filename" == .* || "$filename" != *.* ]]; then
                stem="$filename"
                suffix=""
            else
                stem="${filename%.*}"
                suffix=".${filename##*.}"
            fi

            number=1
            destination="$downloads/$stem ($number)$suffix"
            while [[ -e "$destination" || -L "$destination" ]]; do
                (( number++ ))
                destination="$downloads/$stem ($number)$suffix"
            done
        fi

        mv "$source_path" "$destination"
        rmdir "$temp_dir"
        lowercase_name="${filename:l}"
        reveal_only=false

        case "$lowercase_name" in
            *.app|*.pkg|*.mpkg|*.dmg|*.command|*.tool)
                reveal_only=true
                ;;
        esac

        if [[ -f "$destination" && -x "$destination" ]]; then
            reveal_only=true
        fi

        if [[ "$reveal_only" == true ]]; then
            if open -R -- "$destination" >/dev/null 2>&1; then
                printf 'revealed\n'
            else
                printf 'sent-only\n'
            fi
        else
            if open -- "$destination" >/dev/null 2>&1; then
                printf 'opened\n'
            else
                # The transfer itself succeeded. Show the file in Finder when
                # possible, but do not turn an open failure into a send failure.
                open -R -- "$destination" >/dev/null 2>&1 || true
                printf 'sent-only\n'
            fi
        fi
        """#

        let result = try CommandRunner.run(
            "/usr/bin/ssh",
            arguments: sshOptions + [
                target,
                "/bin/zsh", "-s", "--", remoteTemp, encodedName
            ],
            standardInput: Data(remoteScript.utf8)
        )

        switch result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "opened":
            return .opened
        case "revealed":
            return .revealed
        case "sent-only":
            return .sentButCouldNotOpen
        default:
            throw TransferError.invalidResponse("Mac mini 没有返回有效的打开结果")
        }
    }

    private func cleanup(remoteTemp: String, target: String) throws {
        _ = try CommandRunner.run(
            "/usr/bin/ssh",
            arguments: sshOptions + [target, "rm -rf -- \(remoteTemp)"]
        )
    }

}

private final class NotchDropView: NSView {
    enum State {
        case idle
        case hovering
        case transferring(String)
        case success(String)
        case revealed(String)
        case sentButCouldNotOpen(String)
        case failure(String)
    }

    var onFilesDropped: (([URL]) -> Void)?
    var onDropAccepted: (() -> Void)?
    var onDropFailed: ((String) -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "拖到这里")
    private let subtitleLabel = NSTextField(labelWithString: "发送到 Mac mini")
    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "OpenOnMini.FilePromises"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        iconView.image = NSImage(systemSymbolName: "arrow.down.doc.fill", accessibilityDescription: nil)
        iconView.contentTintColor = .white

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)

        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        subtitleLabel.font = .systemFont(ofSize: 10)

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)

        registerForDraggedTypes(DragPayload.registeredTypes)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let iconSize: CGFloat = 22
        let iconY = (AppConfig.extensionHeight - iconSize) / 2
        let textX: CGFloat = 50
        let textWidth = max(0, bounds.width - textX - 12)

        iconView.frame = NSRect(x: 17, y: iconY, width: iconSize, height: iconSize)
        titleLabel.frame = NSRect(x: textX, y: 24, width: textWidth, height: 16)
        subtitleLabel.frame = NSRect(x: textX, y: 7, width: textWidth, height: 14)
    }

    func show(_ state: State) {
        switch state {
        case .idle:
            iconView.image = NSImage(systemSymbolName: "arrow.down.doc.fill", accessibilityDescription: nil)
            iconView.contentTintColor = .white
            titleLabel.stringValue = "拖到这里"
            subtitleLabel.stringValue = "发送到 Mac mini"
        case .hovering:
            iconView.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: nil)
            iconView.contentTintColor = .systemBlue
            titleLabel.stringValue = "松开发送"
            subtitleLabel.stringValue = "存入下载目录"
        case .transferring(let name):
            iconView.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: nil)
            iconView.contentTintColor = .systemBlue
            titleLabel.stringValue = "正在发送"
            subtitleLabel.stringValue = name
        case .success(let name):
            iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            iconView.contentTintColor = .systemGreen
            titleLabel.stringValue = "Mac mini 已打开"
            subtitleLabel.stringValue = name
        case .revealed(let message):
            iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            iconView.contentTintColor = .systemGreen
            titleLabel.stringValue = "已发送到 Mac mini"
            subtitleLabel.stringValue = message
        case .sentButCouldNotOpen(let name):
            iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            iconView.contentTintColor = .systemOrange
            titleLabel.stringValue = "已发送，无法打开"
            subtitleLabel.stringValue = name
        case .failure(let message):
            iconView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            iconView.contentTintColor = .systemRed
            titleLabel.stringValue = "发送失败"
            subtitleLabel.stringValue = message
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        let accepted = canAccept(pasteboard)
        DragDiagnostics.record("draggingEntered accepted=\(accepted) \(DragDiagnostics.describe(pasteboard))")
        guard accepted else { return [] }
        show(.hovering)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        show(.idle)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        DragDiagnostics.record("performDragOperation \(DragDiagnostics.describe(pasteboard))")
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL], !urls.isEmpty {
            DragDiagnostics.record(
                "accepted=fileURL count=\(urls.count) names=[\(urls.map(\.lastPathComponent).joined(separator: ", "))]"
            )
            onDropAccepted?()
            onFilesDropped?(urls)
            return true
        }

        let receivers = filePromiseReceivers(from: pasteboard)
        guard !receivers.isEmpty else {
            DragDiagnostics.record("rejected=no-file-url-or-file-promise")
            show(.failure("拖入的内容不是文件"))
            return false
        }

        DragDiagnostics.record(
            "accepted=filePromise count=\(receivers.count) types=[\(receivers.flatMap(\.fileTypes).joined(separator: ", "))]"
        )
        onDropAccepted?()
        receivePromisedFiles(receivers)
        return true
    }

    private func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        DragPayload.canAccept(pasteboard)
    }

    private func filePromiseReceivers(from pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
        pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver] ?? []
    }

    private func receivePromisedFiles(_ receivers: [NSFilePromiseReceiver]) {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenOnMini-Promises-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
        } catch {
            let message = "无法创建临时目录"
            show(.failure(message))
            onDropFailed?(message)
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var receivedURLs: [URL] = []
        var firstError: Error?

        for receiver in receivers {
            group.enter()
            receiver.receivePromisedFiles(
                atDestination: destination,
                options: [:],
                operationQueue: promiseQueue
            ) { url, error in
                lock.lock()
                if error == nil, FileManager.default.fileExists(atPath: url.path) {
                    receivedURLs.append(url)
                }
                if firstError == nil, let error {
                    firstError = error
                }
                lock.unlock()
                DragDiagnostics.record(
                    "filePromise completed name=\(url.lastPathComponent) exists=\(FileManager.default.fileExists(atPath: url.path)) error=\(error?.localizedDescription ?? "none")"
                )
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            if !receivedURLs.isEmpty {
                DragDiagnostics.record("filePromise ready count=\(receivedURLs.count)")
                self?.onFilesDropped?(receivedURLs)
            } else {
                let message = firstError?.localizedDescription ?? "微信没有提供可读取的文件"
                DragDiagnostics.record("filePromise failed error=\(firstError?.localizedDescription ?? "none")")
                self?.show(.failure(message))
                self?.onDropFailed?(message)
            }
        }
    }
}

private final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onSaveTarget: ((String) -> Bool)?
    var onTestConnection: ((String) -> Void)?
    var onToggleLaunchAtLogin: ((Bool) -> Void)?
    var onShowDropZone: (() -> Void)?
    var onQuit: (() -> Void)?

    private let targetField = NSTextField()
    private let launchAtLoginSwitch = NSSwitch()
    private let statusLabel = NSTextField(labelWithString: "")
    private let testButton = NSButton(title: "测试连接", target: nil, action: nil)

    init(target: String, launchAtLoginEnabled: Bool) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 350),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "投到 Mac mini 设置"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        configureView(target: target, launchAtLoginEnabled: launchAtLoginEnabled)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(target: String, launchAtLoginEnabled: Bool) {
        targetField.stringValue = target
        launchAtLoginSwitch.state = launchAtLoginEnabled ? .on : .off
        showStatus("")
    }

    func showStatus(_ message: String, isError: Bool = false) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    func setTesting(_ testing: Bool) {
        testButton.isEnabled = !testing
        testButton.title = testing ? "正在测试…" : "测试连接"
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginSwitch.state = enabled ? .on : .off
    }

    private func configureView(target: String, launchAtLoginEnabled: Bool) {
        guard let contentView = window?.contentView else { return }

        let iconView = NSImageView(frame: NSRect(x: 28, y: 252, width: 64, height: 64))
        iconView.image = NSApplication.shared.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "投到 Mac mini")
        titleLabel.frame = NSRect(x: 108, y: 282, width: 370, height: 28)
        titleLabel.font = .systemFont(ofSize: 21, weight: .semibold)
        contentView.addSubview(titleLabel)

        let descriptionLabel = NSTextField(labelWithString: "从刘海投放文件，并在 Mac mini 上打开")
        descriptionLabel.frame = NSRect(x: 108, y: 258, width: 370, height: 20)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.font = .systemFont(ofSize: 13)
        contentView.addSubview(descriptionLabel)

        let separator = NSBox(frame: NSRect(x: 24, y: 236, width: 472, height: 1))
        separator.boxType = .separator
        contentView.addSubview(separator)

        let targetLabel = NSTextField(labelWithString: "Mac mini SSH 地址")
        targetLabel.frame = NSRect(x: 28, y: 202, width: 180, height: 18)
        targetLabel.font = .systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(targetLabel)

        targetField.frame = NSRect(x: 28, y: 166, width: 355, height: 28)
        targetField.stringValue = target
        targetField.placeholderString = AppConfig.defaultTarget
        targetField.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        targetField.target = self
        targetField.action = #selector(saveTarget)
        contentView.addSubview(targetField)

        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveTarget))
        saveButton.frame = NSRect(x: 395, y: 165, width: 101, height: 30)
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        statusLabel.frame = NSRect(x: 28, y: 139, width: 468, height: 18)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11.5)
        statusLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(statusLabel)

        let loginLabel = NSTextField(labelWithString: "登录时自动启动")
        loginLabel.frame = NSRect(x: 28, y: 103, width: 250, height: 20)
        loginLabel.font = .systemFont(ofSize: 13)
        contentView.addSubview(loginLabel)

        launchAtLoginSwitch.frame = NSRect(x: 443, y: 101, width: 42, height: 24)
        launchAtLoginSwitch.state = launchAtLoginEnabled ? .on : .off
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(toggleLaunchAtLogin)
        contentView.addSubview(launchAtLoginSwitch)

        let bottomSeparator = NSBox(frame: NSRect(x: 24, y: 83, width: 472, height: 1))
        bottomSeparator.boxType = .separator
        contentView.addSubview(bottomSeparator)

        let quitButton = NSButton(title: "退出应用", target: self, action: #selector(quitApplication))
        quitButton.frame = NSRect(x: 24, y: 26, width: 100, height: 32)
        quitButton.contentTintColor = .systemRed
        contentView.addSubview(quitButton)

        let showButton = NSButton(title: "显示投放区", target: self, action: #selector(showDropZone))
        showButton.frame = NSRect(x: 273, y: 26, width: 110, height: 32)
        contentView.addSubview(showButton)

        testButton.frame = NSRect(x: 391, y: 26, width: 105, height: 32)
        testButton.target = self
        testButton.action = #selector(testConnection)
        contentView.addSubview(testButton)
    }

    private var trimmedTarget: String {
        targetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc private func saveTarget() {
        if onSaveTarget?(trimmedTarget) == true {
            showStatus("地址已保存")
        }
    }

    @objc private func testConnection() {
        onTestConnection?(trimmedTarget)
    }

    @objc private func toggleLaunchAtLogin() {
        onToggleLaunchAtLogin?(launchAtLoginSwitch.state == .on)
    }

    @objc private func showDropZone() {
        onShowDropZone?()
    }

    @objc private func quitApplication() {
        onQuit?()
    }
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var dropView: NotchDropView!
    private var settingsWindowController: SettingsWindowController?
    private let transferService = TransferService()
    private var dragPollTimer: Timer?
    private var panelIsVisible = false
    private var panelKeepsVisible = false
    private var panelVisibilityRevision = 0
    private var leftMouseWasDown = false
    private var mouseDownLocation = NSPoint.zero
    private var handledDragPasteboardChangeCount = 0
    private var activeDragPasteboardChangeCount: Int?
    private var finishedInitialLaunch = false

    private struct PanelGeometry {
        let screen: NSScreen
        let size: NSSize
        let hiddenOrigin: NSPoint
        let visibleOrigin: NSPoint
        let notchHeight: CGFloat
    }

    private var target: String {
        get {
            UserDefaults.standard.string(forKey: AppConfig.targetKey)
                ?? AppConfig.defaultTarget
        }
        set {
            UserDefaults.standard.set(newValue, forKey: AppConfig.targetKey)
        }
    }

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DragDiagnostics.reset()
        configurePanel()
        startWatchingForFileDrags()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        DispatchQueue.main.async { [weak self] in
            self?.finishedInitialLaunch = true
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dragPollTimer?.invalidate()
    }

    private func configurePanel() {
        let geometry = panelGeometry()
        let contentRect = NSRect(
            x: 0,
            y: 0,
            width: geometry?.size.width ?? AppConfig.fallbackNotchWidth,
            height: geometry?.size.height
                ?? AppConfig.fallbackNotchHeight + AppConfig.extensionHeight
        )

        panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary
        ]

        dropView = NotchDropView(frame: contentRect)
        dropView.onDropAccepted = { [weak self] in
            guard let self else { return }
            self.panelKeepsVisible = true
            self.dropView.show(.transferring("正在接收文件"))
        }
        dropView.onDropFailed = { [weak self] message in
            guard let self else { return }
            self.panelKeepsVisible = true
            self.dropView.show(.failure(message))
            self.resetDropView(after: 5)
        }
        dropView.onFilesDropped = { [weak self] urls in
            self?.send(urls)
        }
        panel.contentView = dropView

        panel.alphaValue = 1
        positionPanel(visible: false)
        panel.orderOut(nil)

        if let geometry {
            let leftArea = geometry.screen.auxiliaryTopLeftArea.map(NSStringFromRect) ?? "none"
            let rightArea = geometry.screen.auxiliaryTopRightArea.map(NSStringFromRect) ?? "none"
            DragDiagnostics.record(
                "panel geometry screen=\(NSStringFromRect(geometry.screen.frame)) "
                    + "visibleFrame=\(NSStringFromRect(geometry.screen.visibleFrame)) "
                    + "safeTop=\(geometry.screen.safeAreaInsets.top) "
                    + "leftArea=\(leftArea) rightArea=\(rightArea) "
                    + "size=\(NSStringFromSize(geometry.size)) "
                    + "hidden=\(NSStringFromPoint(geometry.hiddenOrigin)) "
                    + "visible=\(NSStringFromPoint(geometry.visibleOrigin))"
            )
        }
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.max { first, second in
            first.safeAreaInsets.top < second.safeAreaInsets.top
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func panelGeometry() -> PanelGeometry? {
        guard let screen = targetScreen() else { return nil }
        let frame = screen.frame
        let auxiliaryNotchHeight = screen.auxiliaryTopLeftArea?.height
        let notchHeight = max(
            auxiliaryNotchHeight
                ?? max(screen.safeAreaInsets.top, frame.maxY - screen.visibleFrame.maxY),
            AppConfig.fallbackNotchHeight
        )
        let detectedNotchFrame: NSRect? = {
            guard let leftArea = screen.auxiliaryTopLeftArea,
                  let rightArea = screen.auxiliaryTopRightArea else { return nil }
            let width = rightArea.minX - leftArea.maxX
            guard width >= 120, width <= 400 else { return nil }
            return NSRect(
                x: leftArea.maxX,
                y: frame.maxY - notchHeight,
                width: width,
                height: notchHeight
            )
        }()
        let onePhysicalPixel = 1 / max(screen.backingScaleFactor, 1)
        let baseNotchWidth = detectedNotchFrame?.width ?? AppConfig.fallbackNotchWidth
        let notchWidth = baseNotchWidth + onePhysicalPixel
        let notchX = detectedNotchFrame?.minX ?? frame.midX - baseNotchWidth / 2
        let panelHeight = notchHeight + AppConfig.extensionHeight
        let size = NSSize(width: notchWidth, height: panelHeight)

        return PanelGeometry(
            screen: screen,
            size: size,
            hiddenOrigin: NSPoint(x: notchX, y: frame.maxY - notchHeight),
            visibleOrigin: NSPoint(x: notchX, y: frame.maxY - panelHeight),
            notchHeight: notchHeight
        )
    }

    private func positionPanel(visible: Bool) {
        guard let geometry = panelGeometry() else { return }
        let origin = visible ? geometry.visibleOrigin : geometry.hiddenOrigin
        panel?.setFrame(NSRect(origin: origin, size: geometry.size), display: true)
    }

    private func revealPanel(animated: Bool = true) {
        guard !panelIsVisible else { return }
        guard let geometry = panelGeometry() else { return }

        panelVisibilityRevision += 1
        panelIsVisible = true
        DragDiagnostics.record("panel revealed")
        panel.setFrame(
            NSRect(origin: geometry.hiddenOrigin, size: geometry.size),
            display: true
        )
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(
                    NSRect(origin: geometry.visibleOrigin, size: geometry.size),
                    display: true
                )
            }
        } else {
            panel.setFrame(
                NSRect(origin: geometry.visibleOrigin, size: geometry.size),
                display: true
            )
        }
    }

    private func concealPanel(animated: Bool = true) {
        guard panelIsVisible, !panelKeepsVisible else { return }
        guard let geometry = panelGeometry() else { return }

        panelVisibilityRevision += 1
        let revision = panelVisibilityRevision
        panelIsVisible = false
        DragDiagnostics.record("panel concealed")

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrame(
                    NSRect(origin: geometry.hiddenOrigin, size: geometry.size),
                    display: true
                )
            } completionHandler: { [weak self] in
                guard let self,
                      self.panelVisibilityRevision == revision,
                      !self.panelIsVisible else { return }
                self.panel.orderOut(nil)
            }
        } else {
            panel.setFrame(
                NSRect(origin: geometry.hiddenOrigin, size: geometry.size),
                display: true
            )
            panel.orderOut(nil)
        }
    }

    private func startWatchingForFileDrags() {
        handledDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.pollForFileDrag()
        }
        RunLoop.main.add(timer, forMode: .common)
        dragPollTimer = timer
    }

    private func pollForFileDrag() {
        let leftMouseButtonIsDown = NSEvent.pressedMouseButtons & 1 == 1
        let dragPasteboard = NSPasteboard(name: .drag)

        if leftMouseButtonIsDown, !leftMouseWasDown {
            mouseDownLocation = NSEvent.mouseLocation
        }

        if leftMouseButtonIsDown {
            let location = NSEvent.mouseLocation
            let distance = hypot(
                location.x - mouseDownLocation.x,
                location.y - mouseDownLocation.y
            )
            let changeCount = dragPasteboard.changeCount

            if activeDragPasteboardChangeCount == nil,
               distance >= 4,
               changeCount != handledDragPasteboardChangeCount,
               DragPayload.canAccept(dragPasteboard) {
                activeDragPasteboardChangeCount = changeCount
                handledDragPasteboardChangeCount = changeCount
                dropView.show(.idle)
                revealPanel()
            }
        } else if leftMouseWasDown {
            activeDragPasteboardChangeCount = nil
            concealPanel()
        }

        leftMouseWasDown = leftMouseButtonIsDown
    }

    private func send(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        panelKeepsVisible = true
        revealPanel()
        let currentTarget = target
        dropView.show(.transferring(urls.first?.lastPathComponent ?? "文件"))

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            defer { self.cleanUpTemporaryDropFiles(urls) }

            do {
                var revealedCount = 0
                var couldNotOpenCount = 0

                for url in urls {
                    DispatchQueue.main.async {
                        self.dropView.show(.transferring(url.lastPathComponent))
                    }
                    let result = try self.transferService.send(url, target: currentTarget)
                    switch result {
                    case .opened:
                        break
                    case .revealed:
                        revealedCount += 1
                    case .sentButCouldNotOpen:
                        couldNotOpenCount += 1
                    }
                }

                DispatchQueue.main.async {
                    if couldNotOpenCount > 0 {
                        let message = urls.count == 1
                            ? urls[0].lastPathComponent
                            : "\(couldNotOpenCount) 个文件无法自动打开"
                        self.dropView.show(.sentButCouldNotOpen(message))
                        self.resetDropView(after: 4)
                    } else if revealedCount > 0 {
                        let message = urls.count == 1
                            ? "已在 Finder 中显示：\(urls[0].lastPathComponent)"
                            : "共 \(urls.count) 个文件，已在 Finder 中显示"
                        self.dropView.show(.revealed(message))
                        self.resetDropView(after: 0.5)
                    } else {
                        let message = urls.count == 1
                            ? urls[0].lastPathComponent
                            : "共 \(urls.count) 个文件"
                        self.dropView.show(.success(message))
                        self.resetDropView(after: 0.5)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.dropView.show(.failure(error.localizedDescription))
                    self.presentError(error)
                    self.resetDropView(after: 5)
                }
            }
        }
    }

    private func cleanUpTemporaryDropFiles(_ urls: [URL]) {
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let parentDirectories = Set(urls.map { $0.deletingLastPathComponent() })

        for directory in parentDirectories {
            let normalized = directory.standardizedFileURL
            guard normalized.path.hasPrefix(temporaryRoot),
                  normalized.lastPathComponent.hasPrefix("OpenOnMini-Promises-") else {
                continue
            }
            try? FileManager.default.removeItem(at: normalized)
        }
    }

    private func resetDropView(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.dropView.show(.idle)
            self.panelKeepsVisible = false
            self.concealPanel()
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "没有发送成功"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showPanel() {
        panelKeepsVisible = true
        dropView.show(.idle)
        revealPanel()
        resetDropView(after: 5)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if finishedInitialLaunch {
            showSettings()
        }
        return true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if finishedInitialLaunch {
            showSettings()
        }
        return true
    }

    private func showSettings() {
        let launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        let controller: SettingsWindowController

        if let existing = settingsWindowController {
            controller = existing
            controller.update(target: target, launchAtLoginEnabled: launchAtLoginEnabled)
        } else {
            controller = SettingsWindowController(
                target: target,
                launchAtLoginEnabled: launchAtLoginEnabled
            )
            configureSettingsCallbacks(controller)
            settingsWindowController = controller
        }

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func configureSettingsCallbacks(_ controller: SettingsWindowController) {
        controller.onSaveTarget = { [weak self, weak controller] value in
            guard let self else { return false }
            guard self.isValidTarget(value) else {
                controller?.showStatus("请输入“用户名@主机名”格式的地址", isError: true)
                return false
            }
            self.target = value
            return true
        }

        controller.onTestConnection = { [weak self, weak controller] value in
            guard let self, let controller else { return }
            guard self.isValidTarget(value) else {
                controller.showStatus("请输入“用户名@主机名”格式的地址", isError: true)
                return
            }

            self.target = value
            controller.setTesting(true)
            controller.showStatus("正在连接…")
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak controller] in
                guard let self else { return }
                do {
                    try self.transferService.testConnection(target: value)
                    DispatchQueue.main.async {
                        controller?.setTesting(false)
                        controller?.showStatus("连接正常")
                    }
                } catch {
                    DispatchQueue.main.async {
                        controller?.setTesting(false)
                        controller?.showStatus("连接失败：\(error.localizedDescription)", isError: true)
                    }
                }
            }
        }

        controller.onToggleLaunchAtLogin = { [weak self, weak controller] enabled in
            self?.setLaunchAtLogin(enabled, controller: controller)
        }
        controller.onShowDropZone = { [weak self] in self?.showPanel() }
        controller.onQuit = { NSApp.terminate(nil) }
    }

    private func isValidTarget(_ value: String) -> Bool {
        !value.isEmpty && value.contains("@")
    }

    private func setLaunchAtLogin(
        _ enabled: Bool,
        controller: SettingsWindowController?
    ) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }

            let isEnabled = SMAppService.mainApp.status == .enabled
            controller?.setLaunchAtLogin(isEnabled)
            controller?.showStatus(isEnabled ? "已开启登录时自动启动" : "已关闭登录时自动启动")
        } catch {
            controller?.setLaunchAtLogin(SMAppService.mainApp.status == .enabled)
            controller?.showStatus("无法更改开机启动：\(error.localizedDescription)", isError: true)
        }
    }

    @objc private func screenConfigurationChanged() {
        positionPanel(visible: panelIsVisible)
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}
