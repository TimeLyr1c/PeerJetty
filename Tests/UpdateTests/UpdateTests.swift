import AppKit
import PeerCore

private func check(_ value: Bool, _ message: String) { precondition(value, message) }
private final class MockProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    static var failure: Error?
    static var requestSeen: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestSeen = request
        if let failure = Self.failure { client?.urlProtocol(self, didFailWithError: failure); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: [:])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct UpdateChecks {
    static func main() throws {
        check(ProductVersion("0.3.10")! > ProductVersion("v0.3.2")!, "Numeric ordering")
        check(ProductVersion("1.0.0")! > ProductVersion("0.99.99")!, "Major ordering")
        check(ProductVersion("0.3.2") == ProductVersion("v0.3.2"), "Tag prefix")
        for version in ["0.3", "0.3.2-beta", "01.2.3", "-1.0.0", "０.3.2", "1.2.99999999999999999999999999"] {
            check(ProductVersion(version) == nil, "Reject malformed version")
        }
        let release: [String: Any] = ["tag_name":"v0.3.10", "draft":false, "prerelease":false,
            "body":"English notes / 中文说明", "html_url":"https://github.com/TimeLyr1c/PeerJetty/releases/tag/v0.3.10",
            "assets":[["name":"PeerJetty-0.3.10-build12-arm64.dmg", "state":"uploaded", "browser_download_url":"https://github.com/TimeLyr1c/PeerJetty/releases/download/v0.3.10/PeerJetty-0.3.10-build12-arm64.dmg"]]]
        func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
        func reject(_ value: [String: Any], _ label: String) throws {
            do { _ = try UpdateResponse.parse(data: data(value), status: 200); fatalError(label) } catch is PeerError {}
        }
        let parsed = try UpdateResponse.parse(data: data(release), status: 200)!
        check(parsed.version > ProductVersion("0.3.2")! && parsed.hasInstaller && parsed.notes.contains("中文"), "Stable release and DMG")
        var altered = release; altered["prerelease"] = true; try reject(altered, "Reject prerelease")
        altered = release; altered["draft"] = true; try reject(altered, "Reject draft")
        for url in ["http://github.com/TimeLyr1c/PeerJetty/releases/tag/v0.3.10", "https://evil.example/releases/tag/v0.3.10", "https://github.com/Other/PeerJetty/releases/tag/v0.3.10", "https://user@github.com/TimeLyr1c/PeerJetty/releases/tag/v0.3.10", "https://github.com/TimeLyr1c/PeerJetty/releases/tag/v0.3.11"] {
            altered = release; altered["html_url"] = url; try reject(altered, "Reject untrusted/mismatched page")
        }
        altered = release; altered["assets"] = []; check(try UpdateResponse.parse(data: data(altered), status: 200)?.hasInstaller == false, "Missing DMG")
        altered = release; altered["assets"] = [["name":"PeerJetty-0.3.10-build12-arm64.dmg", "state":"uploaded", "browser_download_url":"https://evil.example/fake.dmg"]]
        check(try UpdateResponse.parse(data: data(altered), status: 200)?.hasInstaller == false, "Untrusted installer")
        altered = release; altered["body"] = String(repeating: "x", count: 30_000)
        check(try UpdateResponse.parse(data: data(altered), status: 200)?.notes.count == 20_000, "Bound notes")
        check(try UpdateResponse.parse(data: Data(), status: 404) == nil, "No stable releases")
        for (bytes, status) in [(Data("broken".utf8),200), (Data(repeating: 1,count:1_048_577),200), (Data(),403), (Data(),429), (Data(),500)] {
            do { _ = try UpdateResponse.parse(data: bytes, status: status); fatalError("Expected failure") } catch is PeerError {}
        }
        print("PASS: version comparison, stable release policy, bounded content and trusted repository URLs")
        MockProtocol.body = try data(release)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
        let client = UpdateClient(configuration: configuration)
        func run(_ checkingClient: UpdateClient = client) -> Result<PublicRelease?, Error> {
            var result: Result<PublicRelease?, Error>?
            checkingClient.check { result = $0 }
            let deadline = Date().addingTimeInterval(5)
            while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            guard let result else { fatalError("Completion timeout") }; return result
        }
        check(try run().get()?.hasInstaller == true, "Mock HTTP success")
        check(MockProtocol.requestSeen?.url == UpdateResponse.endpoint, "Only configured endpoint")
        check(MockProtocol.requestSeen?.value(forHTTPHeaderField: "Authorization") == nil, "No login token")
        MockProtocol.status = 404; check(try run().get() == nil, "Mock no releases")
        MockProtocol.status = 429
        if case .success = run() { fatalError("Rate limit must fail") }
        MockProtocol.failure = URLError(.timedOut)
        if case .success = run() { fatalError("Timeout must fail") }
        print("PASS: isolated URLSession responses, rate limit, timeout and main-run-loop completion")
        if CommandLine.arguments.contains("--live") {
            let live = try run(UpdateClient()).get()
            print("PASS: live GitHub latest endpoint: " + (live?.version.description ?? "no stable release"))
        }
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let ui = UpdateWindow(version: "0.3.2")
        ui.display(.success(parsed))
        check(ui.window?.contentView?.subviews.count == 5, "Update window controls")
        if let content = ui.window?.contentView {
            content.wantsLayer = true; content.layer?.backgroundColor = NSColor.white.cgColor
            content.layoutSubtreeIfNeeded()
            for item in content.subviews { check(content.bounds.contains(item.frame), "Update window layout") }
        }
        if let content = ui.window?.contentView {
            let buttons = content.subviews.compactMap { $0 as? NSButton }
            check(buttons.count == 2 && !buttons[1].isHidden, "New release shows page action")
            let current = UpdateWindow(version: "0.3.10"); current.display(.success(parsed))
            check(current.window!.contentView!.subviews.compactMap { $0 as? NSButton }[1].isHidden, "Equal version does not offer update")
            let ahead = UpdateWindow(version: "0.4.0"); ahead.display(.success(parsed))
            check(ahead.window!.contentView!.subviews.compactMap { $0 as? NSButton }[1].isHidden, "Never offer downgrade")
            ui.display(.failure(URLError(.notConnectedToInternet)))
            check(buttons[1].isHidden, "Failure clears stale download action")
            ui.display(.success(nil)); check(!buttons[1].isHidden, "No release can open repository releases")
            ui.display(.success(parsed))
            if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
                let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]))
            }
        }
        print("PASS: " + L10n.language + " update window layout and UI result states")
    }
}
