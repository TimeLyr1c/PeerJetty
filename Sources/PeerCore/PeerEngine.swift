import Foundation
import Network
import CryptoKit

private final class Outgoing {
    let id = UUID()
    let prepared: PreparedTransfer
    var file: FileHandle?
    var index = -1
    var remaining: Int64 = 0
    var completed: Int64 = 0
    var hash = SHA256()
    var waitingForReceipt = false
    init(_ prepared: PreparedTransfer) { self.prepared = prepared }
    deinit { try? file?.close() }
}

private final class Session {
    let id = UUID()
    let wire: FramedConnection
    let nonce: Data
    var expectedID: String?
    var peerID = ""
    var name = "设备"
    var exporter = Data()
    var commitment: String?
    var remoteNonce: Data?
    var localConfirmed = false
    var remoteConfirmed = false
    var authorized = false
    var outgoing: Outgoing?
    var incoming: ReceiveTransaction?
    var incomingID: UUID?
    var pending: [PreparedTransfer] = []
    var lastActivity = Date()
    var uiUpdates: [UUID: TimeInterval] = [:]
    let created = Date()
    init(_ wire: FramedConnection) throws { self.wire = wire; nonce = try DeviceIdentity.random(32) }
}

public final class PeerEngine {
    // Keep discovery compatible with existing OpenOnMini installations.
    public static let serviceType = "_openonmini._tcp"
    public let identity: DeviceIdentity
    public let store: ConfigurationStore
    public var onPeers: (([DiscoveredPeer]) -> Void)?
    public var onStatus: ((String) -> Void)?
    public var onPairing: ((UUID, String, String) -> Void)?
    public var onPairingEnded: ((UUID) -> Void)?
    public var onTransfer: ((TransferUpdate) -> Void)?
    public var onReceived: ((String, [URL]) -> Void)?
    public var onListening: ((UInt16) -> Void)?
    public var onRejectedConnection: ((String) -> Void)?
    public var onPreparation: ((Bool) -> Void)?
    private let queue = DispatchQueue(label: "PeerJetty.Network")
    private let gate = PairingGate()
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var timer: DispatchSourceTimer?
    private var sessions: [UUID: Session] = [:]
    private var endpoints: [String: (NWEndpoint, String)] = [:]
    private var receiveAccess: URL?
    private var pairingAttempts: [Date] = []
    private var pairingWasOpen = false

    public init(identity: DeviceIdentity, store: ConfigurationStore) { self.identity = identity; self.store = store }
    private func emit(_ text: String) { DispatchQueue.main.async { self.onStatus?(text) } }

    public func start(discovery: Bool = true) {
        queue.async { [self] in
            do {
                if let bookmark = self.store.snapshot.receiveBookmark {
                    var stale = false
                    let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
                    if url.startAccessingSecurityScopedResource() { self.receiveAccess = url }
                }
                let parameters = TLS.parameters(identity: self.identity, store: self.store, gate: self.gate, queue: self.queue) { [weak self] id in
                    DispatchQueue.main.async { self?.onRejectedConnection?(id) }
                }
                let listener = try NWListener(using: parameters, on: .any)
                listener.newConnectionHandler = { [weak self] connection in self?.attach(connection) }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self else { return }
                    if case .ready = state, let port = listener?.port?.rawValue {
                        DispatchQueue.main.async { self.onListening?(port) }; self.emit("已就绪，可以添加设备")
                    } else if case .failed(let error) = state { self.emit("接收服务失败：\(error.localizedDescription)") }
                }
                self.listener = listener
                if discovery { self.advertise(); self.startBrowser() }
                listener.start(queue: self.queue)
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now() + 1, repeating: 1)
                timer.setEventHandler { [weak self] in self?.tick() }
                self.timer = timer; timer.resume()
            } catch { self.emit(error.localizedDescription) }
        }
    }
    public func stop() {
        queue.async {
            self.gate.close(); self.browser?.cancel(); self.browser = nil; self.listener?.cancel(); self.listener = nil
            self.timer?.cancel(); self.timer = nil
            for session in Array(self.sessions.values) { self.fail(session, PeerError.message("服务已停止")) }
            self.receiveAccess?.stopAccessingSecurityScopedResource(); self.receiveAccess = nil
        }
    }
    public func openPairing() { queue.async { self.gate.open(); self.pairingWasOpen = true; self.advertise(); self.emit("配对窗口已开启，两分钟内在另一台设备上添加设备") } }
    public func closePairing() {
        queue.async {
            self.gate.close(); self.advertise()
            for session in Array(self.sessions.values) where !session.authorized { self.fail(session, PeerError.message("配对已取消")) }
        }
    }
    public func refresh() { queue.async { self.advertise(); self.publishPeers() } }
    private func advertise() {
        guard browser != nil || listener?.service != nil else { return }
        let name = gate.isOpen ? store.snapshot.name : "Mac"
        var record = NWTXTRecord()
        record.setEntry(.string(identity.fingerprint), for: "id")
        record.setEntry(.string(String(name.prefix(64))), for: "name")
        record.setEntry(.string(gate.isOpen ? "1" : "0"), for: "pairing")
        listener?.service = NWListener.Service(name: String(identity.fingerprint.prefix(20)), type: Self.serviceType, txtRecord: record)
    }
    private func startBrowser() {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            if case .waiting(let error) = state { self?.emit("设备发现暂不可用：\(error.localizedDescription)。请检查局域网权限和网络隔离。") }
            if case .failed(let error) = state { self?.emit("设备发现失败：\(error.localizedDescription)") }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            var next: [String: (NWEndpoint, String)] = [:]
            for result in results {
                guard case .bonjour(let txt) = result.metadata, case .string(let id)? = txt.getEntry(for: "id"),
                      id.count == 64, id != self.identity.fingerprint else { continue }
                let paired = self.store.snapshot.peers.first { $0.id == id }
                let pairing = txt.getEntry(for: "pairing") == .string("1")
                guard paired != nil || pairing else { continue }
                let name: String
                if let paired { name = paired.name }
                else if case .string(let value)? = txt.getEntry(for: "name") { name = String(value.prefix(64)) }
                else { name = "Mac" }
                next[id] = (result.endpoint, name)
            }
            self.endpoints = next; self.publishPeers()
        }
        self.browser = browser; advertise(); browser.start(queue: queue)
    }
    private func publishPeers() {
        let config = store.snapshot
        let ids = Set(endpoints.keys).union(config.peers.map(\.id)).union(sessions.values.filter(\.authorized).map(\.peerID))
        let peers = ids.map { id -> DiscoveredPeer in
            let connected = sessions.values.contains { $0.peerID == id && $0.authorized }
            return DiscoveredPeer(id: id, name: config.peers.first { $0.id == id }?.name ?? endpoints[id]?.1 ?? "Mac",
                                  paired: config.peers.contains { $0.id == id }, connected: connected || endpoints[id] != nil)
        }.sorted { $0.name < $1.name }
        DispatchQueue.main.async { self.onPeers?(peers) }
    }
    public func connect(peerID: String) {
        queue.async {
            guard let endpoint = self.endpoints[peerID]?.0 else { self.emit("设备离线或未被发现"); return }
            self.dial(endpoint, expected: peerID)
        }
    }
    // Used by the advanced manual address UI and isolated loopback harness; still performs TLS and SAS verification.
    public func connect(host: String, port: UInt16) {
        queue.async {
            guard !host.isEmpty, host.count <= 255, !host.contains(where: { $0.isWhitespace }), let port = NWEndpoint.Port(rawValue: port) else { self.emit("地址或端口无效"); return }
            self.dial(.hostPort(host: NWEndpoint.Host(host), port: port), expected: nil)
        }
    }
    private func dial(_ endpoint: NWEndpoint, expected: String?) {
        if let expected, sessions.values.contains(where: { $0.peerID == expected || $0.expectedID == expected }) { emit("设备已连接或正在配对"); return }
        let parameters = TLS.parameters(identity: identity, store: store, gate: gate, expected: expected, queue: queue)
        attach(NWConnection(to: endpoint, using: parameters), expected: expected)
    }
    private func attach(_ connection: NWConnection, expected: String? = nil) {
        guard sessions.count < 8 else { connection.cancel(); return }
        do {
            let session = try Session(FramedConnection(connection)); session.expectedID = expected; sessions[session.id] = session
            session.wire.onFailure = { [weak self, weak session] error in if let session { self?.fail(session, error) } }
            session.wire.onMessage = { [weak self, weak session] message in if let session { self?.handle(message, session: session) } }
            session.wire.onChunk = { [weak self, weak session] data in if let session { self?.chunk(data, session: session) } }
            connection.stateUpdateHandler = { [weak self, weak session] state in
                guard let self, let session, self.sessions[session.id] != nil else { return }
                switch state {
                case .ready:
                    do {
                        session.peerID = try TLS.peerFingerprint(connection); session.exporter = try TLS.exporter(connection)
                        if !self.store.snapshot.peers.contains(where: { $0.id == session.peerID }) {
                            self.pairingAttempts.removeAll { Date().timeIntervalSince($0) > 120 }
                            guard self.gate.isOpen, self.pairingAttempts.count < 5,
                                  !self.sessions.values.contains(where: { $0.id != session.id && !$0.authorized && !$0.peerID.isEmpty }) else {
                                throw PeerError.message("配对请求过多或另一个配对正在进行")
                            }
                            self.pairingAttempts.append(Date())
                        }
                        var hello = Message("hello"); hello.id = self.identity.fingerprint; hello.name = self.store.snapshot.name
                        hello.version = 1; hello.commitment = PairingProof.commitment(id: self.identity.fingerprint, nonce: session.nonce)
                        session.wire.send(hello); session.wire.begin()
                    } catch { self.fail(session, error) }
                case .failed(let error): self.fail(session, error)
                case .waiting(let error): self.emit("连接等待中：\(error.localizedDescription)")
                case .cancelled: self.fail(session, PeerError.message("连接已关闭"))
                default: break
                }
            }
            connection.start(queue: queue)
        } catch { connection.cancel(); emit(error.localizedDescription) }
    }
    public func confirm(sessionID: UUID, approved: Bool) {
        queue.async {
            guard let session = self.sessions[sessionID], session.remoteNonce != nil, !session.authorized else { return }
            guard approved, self.gate.isOpen else { self.fail(session, PeerError.message("配对未获确认")); return }
            session.localConfirmed = true; session.wire.send(Message("confirm")); self.authorizeIfReady(session)
        }
    }
    public func forget(_ id: String) {
        queue.async {
            do {
                try self.store.update { $0.peers.removeAll { $0.id == id }; if $0.preferredPeer == id { $0.preferredPeer = $0.peers.first?.id } }
                for session in Array(self.sessions.values) where session.peerID == id { self.fail(session, PeerError.message("设备授权已撤销")) }
                self.publishPeers(); self.emit("设备授权已撤销")
            } catch { self.emit(error.localizedDescription) }
        }
    }
    private func authorizeIfReady(_ session: Session) {
        guard session.localConfirmed, session.remoteConfirmed, !session.authorized, session.remoteNonce != nil else { return }
        guard store.snapshot.peers.contains(where: { $0.id == session.peerID }) || gate.isOpen else { fail(session, PeerError.message("配对窗口已关闭")); return }
        do {
            try store.update { config in
                if let index = config.peers.firstIndex(where: { $0.id == session.peerID }) { config.peers[index].name = session.name }
                else { config.peers.append(TrustedPeer(id: session.peerID, name: session.name)) }
                if config.preferredPeer == nil { config.preferredPeer = session.peerID }
            }
            session.authorized = true
            DispatchQueue.main.async { self.onPairingEnded?(session.id) }
            publishPeers(); emit("已连接：\(session.name)"); sendNext(session)
        } catch { fail(session, error) }
    }
    private func handle(_ message: Message, session: Session) {
        session.lastActivity = Date()
        do {
            switch message.kind {
            case "hello":
                guard session.commitment == nil, message.version == 1, message.id == session.peerID,
                      let name = message.name, !name.isEmpty, name.utf8.count <= 256,
                      let commitment = message.commitment, commitment.count == 64 else { throw PeerError.message("设备身份或协议不匹配") }
                session.name = name; session.commitment = commitment
                var reveal = Message("reveal"); reveal.nonce = session.nonce; session.wire.send(reveal)
            case "reveal":
                guard let commitment = session.commitment, session.remoteNonce == nil, let nonce = message.nonce else { throw PeerError.message("配对步骤无效") }
                try PairingProof.verify(id: session.peerID, nonce: nonce, commitment: commitment); session.remoteNonce = nonce
                if store.snapshot.peers.contains(where: { $0.id == session.peerID }) {
                    session.localConfirmed = true; session.wire.send(Message("confirm")); authorizeIfReady(session)
                } else {
                    guard gate.isOpen else { throw PeerError.message("配对窗口已关闭") }
                    let code = PairingProof.code(localID: identity.fingerprint, localNonce: session.nonce,
                                                 remoteID: session.peerID, remoteNonce: nonce, exporter: session.exporter)
                    DispatchQueue.main.async { self.onPairing?(session.id, session.name, code) }
                }
            case "confirm":
                guard session.remoteNonce != nil, !session.remoteConfirmed else { throw PeerError.message("重复或过早的配对确认") }
                session.remoteConfirmed = true; authorizeIfReady(session)
            default:
                guard session.authorized else { throw PeerError.message("未配对设备不能发送文件") }
                try handleTransfer(message, session: session)
            }
        } catch { fail(session, error) }
    }
    public func send(urls: [URL], peerID: String, cleanup: (() -> Void)? = nil) {
        DispatchQueue.main.async { self.onPreparation?(true) }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let prepared = try PreparedTransfer(urls: urls, cleanup: cleanup)
                self.queue.async {
                    DispatchQueue.main.async { self.onPreparation?(false) }
                    guard self.store.snapshot.peers.contains(where: { $0.id == peerID }) else { self.emit("请先配对目标设备"); return }
                    if let session = self.sessions.values.first(where: { $0.peerID == peerID || $0.expectedID == peerID }) {
                        guard session.pending.count < 20 else { self.emit("发送队列已满"); return }
                        session.pending.append(prepared); self.sendNext(session)
                    } else if let endpoint = self.endpoints[peerID]?.0 {
                        let before = Set(self.sessions.keys); self.dial(endpoint, expected: peerID)
                        if let session = self.sessions.values.first(where: { !before.contains($0.id) }) { session.pending.append(prepared) }
                    } else { self.emit("目标设备离线；请等它上线后重试") }
                }
            } catch { cleanup?(); DispatchQueue.main.async { self.onPreparation?(false) }; self.emit(error.localizedDescription) }
        }
    }
    private func sendNext(_ session: Session) {
        guard session.authorized, session.outgoing == nil, !session.pending.isEmpty else { return }
        let outgoing = Outgoing(session.pending.removeFirst()); session.outgoing = outgoing
        var offer = Message("offer"); offer.transfer = outgoing.id; offer.manifest = outgoing.prepared.manifest
        session.lastActivity = Date(); session.wire.send(offer); update(session, outgoing: outgoing, status: "等待接收端确认")
    }
    private func handleTransfer(_ message: Message, session: Session) throws {
        guard let transferID = message.transfer else { throw PeerError.message("缺少传输标识") }
        switch message.kind {
        case "offer":
            guard session.incoming == nil, let manifest = message.manifest,
                  sessions.values.filter({ $0.incoming != nil }).count < 4 else { throw PeerError.message("接收任务繁忙或清单无效") }
            do {
                session.incoming = try ReceiveTransaction(manifest: manifest, destination: URL(fileURLWithPath: store.snapshot.receivePath))
                session.incomingID = transferID
                var accept = Message("accept"); accept.transfer = transferID; session.wire.send(accept)
                updateIncoming(session, status: "正在接收")
            } catch {
                var reject = Message("reject"); reject.transfer = transferID; reject.text = error.localizedDescription; session.wire.send(reject)
                emit(error.localizedDescription)
            }
        case "accept":
            guard let outgoing = session.outgoing, outgoing.id == transferID, outgoing.index == -1 else { throw PeerError.message("无效接收确认") }
            advanceFile(session, outgoing: outgoing)
        case "file":
            guard session.incomingID == transferID, let incoming = session.incoming, let index = message.index else { throw PeerError.message("无效文件起始消息") }
            try incoming.beginFile(index: index)
        case "endFile":
            guard session.incomingID == transferID, let incoming = session.incoming, let index = message.index, let hash = message.hash else { throw PeerError.message("无效文件完成消息") }
            try incoming.endFile(index: index, expectedHash: hash)
        case "finish":
            guard session.incomingID == transferID, let incoming = session.incoming else { throw PeerError.message("无效传输完成消息") }
            let paths = try incoming.finish()
            var receipt = Message("receipt"); receipt.transfer = transferID; receipt.paths = paths.map(\.lastPathComponent); session.wire.send(receipt)
            updateIncoming(session, status: "已接收 \(paths.count) 项", finished: true, succeeded: true)
            session.incoming = nil; session.incomingID = nil
            DispatchQueue.main.async { self.onReceived?(session.name, paths) }
        case "receipt":
            guard let outgoing = session.outgoing, outgoing.id == transferID, outgoing.waitingForReceipt,
                  message.paths?.count == outgoing.prepared.manifest.roots.count else { throw PeerError.message("无效保存确认") }
            update(session, outgoing: outgoing, status: "对方已保存", finished: true, succeeded: true)
            session.outgoing = nil; sendNext(session)
        case "reject":
            guard let outgoing = session.outgoing, outgoing.id == transferID else { throw PeerError.message("无效拒绝消息") }
            update(session, outgoing: outgoing, status: message.text ?? "对方无法接收", finished: true)
            session.outgoing = nil; sendNext(session)
        case "cancel":
            if session.incomingID == transferID {
                updateIncoming(session, status: "传输已取消", finished: true); session.incoming?.cancel(); session.incoming = nil; session.incomingID = nil
            } else if let outgoing = session.outgoing, outgoing.id == transferID {
                update(session, outgoing: outgoing, status: "传输已取消", finished: true); session.outgoing = nil; sendNext(session)
            }
        default: throw PeerError.message("未知协议消息")
        }
    }
    private func advanceFile(_ session: Session, outgoing: Outgoing) {
        guard session.outgoing === outgoing else { return }
        do {
            var index = outgoing.index + 1
            while index < outgoing.prepared.manifest.entries.count, outgoing.prepared.manifest.entries[index].kind != .file { index += 1 }
            outgoing.index = index
            if index == outgoing.prepared.manifest.entries.count {
                outgoing.waitingForReceipt = true
                var finish = Message("finish"); finish.transfer = outgoing.id; session.wire.send(finish)
                update(session, outgoing: outgoing, status: "正在校验并保存"); return
            }
            outgoing.file = try outgoing.prepared.openFile(index: index)
            outgoing.remaining = outgoing.prepared.manifest.entries[index].size; outgoing.hash = SHA256()
            var begin = Message("file"); begin.transfer = outgoing.id; begin.index = index
            session.wire.send(begin) { [weak self, weak session, weak outgoing] error in
                if error == nil, let session, let outgoing { self?.pump(session, outgoing: outgoing) }
            }
        } catch { fail(session, error) }
    }
    private func pump(_ session: Session, outgoing: Outgoing) {
        guard session.outgoing === outgoing, let file = outgoing.file else { return }
        do {
            if outgoing.remaining == 0 {
                guard (try file.read(upToCount: 1) ?? Data()).isEmpty else { throw PeerError.message("发送期间文件发生变化，请重试") }
                try file.close(); outgoing.file = nil
                var end = Message("endFile"); end.transfer = outgoing.id; end.index = outgoing.index
                end.hash = outgoing.hash.finalize().map { String(format: "%02x", $0) }.joined()
                session.wire.send(end) { [weak self, weak session, weak outgoing] error in
                    if error == nil, let session, let outgoing { self?.advanceFile(session, outgoing: outgoing) }
                }; return
            }
            let data = try file.read(upToCount: Int(min(outgoing.remaining, 65536))) ?? Data()
            guard !data.isEmpty else { throw PeerError.message("发送文件变短或无法读取") }
            outgoing.hash.update(data: data); outgoing.remaining -= Int64(data.count); outgoing.completed += Int64(data.count)
            session.lastActivity = Date()
            update(session, outgoing: outgoing, status: "正在发送")
            session.wire.sendChunk(data) { [weak self, weak session, weak outgoing] error in
                if error == nil, let session, let outgoing { self?.pump(session, outgoing: outgoing) }
            }
        } catch { fail(session, error) }
    }
    private func chunk(_ data: Data, session: Session) {
        do {
            guard session.authorized, let incoming = session.incoming else { throw PeerError.message("无效文件数据") }
            try incoming.append(data); session.lastActivity = Date(); updateIncoming(session, status: "正在接收")
        } catch { fail(session, error) }
    }
    public func cancel(transferID: UUID) {
        queue.async {
            for session in Array(self.sessions.values) {
                if session.outgoing?.id == transferID || session.incomingID == transferID {
                    // Closing prevents already-buffered chunks from being confused with the next task.
                    self.fail(session, PeerError.message("传输已取消，请重新投放以重试"))
                }
            }
        }
    }
    private func update(_ session: Session, outgoing: Outgoing, status: String, finished: Bool = false, succeeded: Bool = false) {
        let now = Date.timeIntervalSinceReferenceDate
        if !finished, status == "正在发送", now - (session.uiUpdates[outgoing.id] ?? 0) < 0.1 { return }
        session.uiUpdates[outgoing.id] = now
        let update = TransferUpdate(id: outgoing.id, peerName: session.name, receiving: false, completed: outgoing.completed,
                                    total: outgoing.prepared.manifest.byteCount, status: status, finished: finished, succeeded: succeeded)
        DispatchQueue.main.async { self.onTransfer?(update) }
    }
    private func updateIncoming(_ session: Session, status: String, finished: Bool = false, succeeded: Bool = false) {
        guard let incoming = session.incoming, let id = session.incomingID else { return }
        let now = Date.timeIntervalSinceReferenceDate
        if !finished, now - (session.uiUpdates[id] ?? 0) < 0.1 { return }
        session.uiUpdates[id] = now
        let update = TransferUpdate(id: id, peerName: session.name, receiving: true, completed: incoming.received,
                                    total: incoming.manifest.byteCount, status: status, finished: finished, succeeded: succeeded)
        DispatchQueue.main.async { self.onTransfer?(update) }
    }
    private func fail(_ session: Session, _ error: Error) {
        guard sessions.removeValue(forKey: session.id) != nil else { return }
        if let outgoing = session.outgoing { update(session, outgoing: outgoing, status: error.localizedDescription, finished: true) }
        if session.incoming != nil {
            let count = session.incoming?.committed.count ?? 0
            updateIncoming(session, status: error.localizedDescription + (count > 0 ? "（已保存 \(count) 项）" : ""), finished: true)
        }
        if !session.pending.isEmpty { emit("\(session.pending.count) 项排队任务未发送，请重新投放") }
        session.incoming?.cancel(); session.incoming = nil; session.outgoing = nil; session.pending.removeAll()
        session.wire.close(); DispatchQueue.main.async { self.onPairingEnded?(session.id) }
        emit(error.localizedDescription); publishPeers()
    }
    private func tick() {
        if pairingWasOpen, !gate.isOpen { pairingWasOpen = false; advertise(); emit("配对窗口已关闭") }
        for session in Array(sessions.values) {
            if !session.authorized, Date().timeIntervalSince(session.created) > 120 { fail(session, PeerError.message("配对超时")) }
            else if (session.outgoing != nil || session.incoming != nil || !session.pending.isEmpty), Date().timeIntervalSince(session.lastActivity) > 60 {
                fail(session, PeerError.message("传输超时，请检查网络后重试"))
            }
        }
    }
}
