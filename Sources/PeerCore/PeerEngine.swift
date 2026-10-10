import Foundation
import Network
import CryptoKit

private struct PendingFile {
    let id: UUID
    let peerID: String
    let peerName: String
    let prepared: PreparedTransfer
}
private final class Outgoing {
    let id: UUID
    let prepared: PreparedTransfer
    var file: FileHandle?
    var index = -1
    var remaining: Int64 = 0
    var completed: Int64 = 0
    var hash = SHA256()
    var waitingForReceipt = false
    init(_ pending: PendingFile) { self.id = pending.id; self.prepared = pending.prepared }
    deinit { try? file?.close() }
}

private final class Session {
    let id = UUID()
    let wire: FramedConnection
    let nonce: Data
    var expectedID: String?
    var peerID = ""
    var name = L10n.text("peerengine.device")
    var exporter = Data()
    var commitment: String?
    var remoteNonce: Data?
    var localConfirmed = false
    var remoteConfirmed = false
    var authorized = false
    var supportsUnpair = false
    var unpairing = false
    var unpairRequest: (UUID, Date)?
    var supportsText = false
    var textInbox = TextInbox()
    var textPending: [TextPayload] = []
    var textOutgoing: (TextPayload, Date)?
    var retiredText: [UUID] = []
    var outgoing: Outgoing?
    var incoming: ReceiveTransaction?
    var incomingID: UUID?
    // Cancelled incoming frames may already be in flight; drain until the next ordered offer.
    var cancelledTransfers: [UUID] = []
    var drainingCancelledIncoming = false
    var pending: [PendingFile] = []
    var transportReady = false
    var automatic = false
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
    /// Peer ID, display name, remotely initiated, and remote persistence confirmed.
    public var onUnpaired: ((String, String, Bool, Bool) -> Void)?
    public var onPeers: (([DiscoveredPeer]) -> Void)?
    public var onStatus: ((String) -> Void)?
    public var onPairing: ((UUID, String, String) -> Void)?
    public var onPairingEnded: ((UUID) -> Void)?
    public var onTransfer: ((TransferUpdate) -> Void)?
    public var onReceived: ((String, [URL]) -> Void)?
    public var onTextReceived: ((TextPayload, @escaping () -> Void) -> Void)?
    public var onTextResult: ((TextPayload, Error?) -> Void)?
    public var onListening: ((UInt16) -> Void)?
    public var onRejectedConnection: ((String) -> Void)?
    public var onFileSendEvent: ((FileSendEvent) -> Void)?
    public var onPreparation: ((Bool) -> Void)?
    // Internal capability override supports isolated legacy-compatibility tests.
    var advertisedCapabilities: [String]? = ["text-v1", "unpair-v1"]
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
    private var serviceGeneration = 0
    private var startupTarget: String?
    private var startupAttempts = 0
    private var startupEndpoint: NWEndpoint?

    public init(identity: DeviceIdentity, store: ConfigurationStore) { self.identity = identity; self.store = store }
    private func emit(_ text: String) { DispatchQueue.main.async { self.onStatus?(text) } }

    public func start(discovery: Bool = true) {
        queue.async { [self] in
            resetStartupConnection()
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
                        DispatchQueue.main.async { self.onListening?(port) }; self.emit(L10n.text("peerengine.ready_to_add_a_device"))
                    } else if case .failed(let error) = state { self.emit(L10n.text("peerengine.receive_service_failed", String(describing: error.localizedDescription))) }
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
            self.serviceGeneration += 1; self.startupTarget = nil; self.gate.close(); self.browser?.cancel(); self.browser = nil; self.listener?.cancel(); self.listener = nil
            self.timer?.cancel(); self.timer = nil
            for session in Array(self.sessions.values) { self.fail(session, PeerError.localized("peerengine.service_stopped", [])) }
            self.receiveAccess?.stopAccessingSecurityScopedResource(); self.receiveAccess = nil
        }
    }
    public func openPairing() { queue.async { self.gate.open(); self.pairingWasOpen = true; self.advertise(); self.emit(L10n.text("peerengine.pairing_is_open_for_two_minutes_add_this")) } }
    public func closePairing() {
        queue.async {
            self.gate.close(); self.advertise()
            for session in Array(self.sessions.values) where !session.authorized { self.fail(session, PeerError.localized("peerengine.pairing_cancelled", [])) }
        }
    }
    public func refresh() { queue.async { self.advertise(); self.publishPeers() } }
    private func resetStartupConnection() {
        let config=store.snapshot
        startupTarget=config.autoConnectLastPeer && config.peers.contains(where:{$0.id == config.lastConnectedPeer}) ? config.lastConnectedPeer : nil
        startupAttempts=0; startupEndpoint=nil
    }
    private func stopStartupAttempts(except peerID:String? = nil) {
        startupTarget=nil
        for session in Array(sessions.values) where session.automatic && !session.authorized && session.pending.isEmpty && session.expectedID != peerID {
            fail(session,PeerError.localized("peerengine.connection_closed",[]))
        }
    }
    public func autoConnectPreferenceChanged() {
        queue.async {
            // Preference changes never interrupt authorized sessions or explicit file work.
            for session in Array(self.sessions.values) where session.automatic && !session.authorized && session.pending.isEmpty {
                self.fail(session,PeerError.localized("peerengine.connection_closed",[]))
            }
            self.resetStartupConnection(); self.considerStartupConnection()
        }
    }
    private func considerStartupConnection() {
        guard let target=startupTarget,store.snapshot.autoConnectLastPeer,
              store.snapshot.peers.contains(where:{$0.id == target}) else {return}
        guard let endpoint=endpoints[target]?.0 else {startupEndpoint=nil;return}
        let appeared=startupEndpoint != endpoint; startupEndpoint=endpoint
        guard appeared,startupAttempts < 2,
              !sessions.values.contains(where:{$0.peerID == target || $0.expectedID == target}) else {return}
        startupAttempts += 1
        dial(endpoint,expected:target,automatic:true)
    }
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
            if case .waiting(let error) = state { self?.emit(L10n.text("peerengine.discovery_is_unavailable_check_local_network_access_and", String(describing: error.localizedDescription))) }
            if case .failed(let error) = state { self?.emit(L10n.text("peerengine.discovery_failed", String(describing: error.localizedDescription))) }
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
            self.endpoints = next; self.considerStartupConnection(); self.publishPeers()
        }
        self.browser = browser; advertise(); browser.start(queue: queue)
    }
    private func publishPeers() {
        let config = store.snapshot
        let ids = Set(endpoints.keys).union(config.peers.map(\.id)).union(sessions.values.filter(\.authorized).map(\.peerID))
        let peers = ids.map { id -> DiscoveredPeer in
            let connected = sessions.values.contains { $0.peerID == id && $0.authorized && $0.transportReady && !$0.unpairing }
            return DiscoveredPeer(id: id, name: config.peers.first { $0.id == id }?.name ?? endpoints[id]?.1 ?? "Mac",
                                  paired: config.peers.contains { $0.id == id }, connected: connected, supportsText: sessions.values.first(where: { $0.peerID == id && $0.authorized && $0.transportReady && !$0.unpairing }).map { $0.supportsText })
        }.sorted { $0.name < $1.name }
        DispatchQueue.main.async { self.onPeers?(peers) }
    }
    public func connect(peerID: String) {
        queue.async {
            guard let endpoint = self.endpoints[peerID]?.0 else { self.emit(L10n.text("peerengine.device_offline_or_not_discovered")); return }
            self.stopStartupAttempts()
            self.dial(endpoint, expected: peerID)
        }
    }
    // Used by the advanced manual address UI and isolated loopback harness; still performs TLS and SAS verification.
    public func connect(host: String, port: UInt16) {
        queue.async {
            guard !host.isEmpty, host.count <= 255, !host.contains(where: { $0.isWhitespace }), let port = NWEndpoint.Port(rawValue: port) else { self.emit(L10n.text("peerengine.invalid_address_or_port")); return }
            self.stopStartupAttempts()
            self.dial(.hostPort(host: NWEndpoint.Host(host), port: port), expected: nil)
        }
    }
    private func dial(_ endpoint: NWEndpoint, expected: String?, automatic: Bool = false) {
        if let expected, sessions.values.contains(where: { $0.peerID == expected || $0.expectedID == expected }) { emit(L10n.text("peerengine.device_already_connected_or_pairing")); return }
        let parameters = TLS.parameters(identity: identity, store: store, gate: gate, expected: expected, queue: queue)
        attach(NWConnection(to: endpoint, using: parameters), expected: expected, automatic: automatic)
    }
    private func attach(_ connection: NWConnection, expected: String? = nil, automatic: Bool = false) {
        guard sessions.count < 8 else { connection.cancel(); return }
        do {
            let session = try Session(FramedConnection(connection)); session.expectedID = expected; session.automatic=automatic; sessions[session.id] = session
            if automatic {
                queue.asyncAfter(deadline:.now()+5) { [weak self,weak session] in
                    guard let self,let session,self.sessions[session.id] != nil,session.automatic,!session.authorized else {return}
                    self.fail(session,PeerError.localized("file.connection_timeout",[]))
                }
            }
            session.wire.onFailure = { [weak self, weak session] error in if let session { self?.fail(session, error) } }
            session.wire.onMessage = { [weak self, weak session] message in if let session { self?.handle(message, session: session) } }
            session.wire.onChunk = { [weak self, weak session] data in if let session { self?.chunk(data, session: session) } }
            connection.stateUpdateHandler = { [weak self, weak session] state in
                guard let self, let session, self.sessions[session.id] != nil else { return }
                switch state {
                case .ready:
                    guard !session.transportReady else { return }
                    session.transportReady = true
                    do {
                        session.peerID = try TLS.peerFingerprint(connection); session.exporter = try TLS.exporter(connection)
                        if !self.store.snapshot.peers.contains(where: { $0.id == session.peerID }) {
                            self.pairingAttempts.removeAll { Date().timeIntervalSince($0) > 120 }
                            guard self.gate.isOpen, self.pairingAttempts.count < 5,
                                  !self.sessions.values.contains(where: { $0.id != session.id && !$0.authorized && !$0.peerID.isEmpty }) else {
                                throw PeerError.localized("peerengine.too_many_pairing_requests_or_another_pairing_is", [])
                            }
                            self.pairingAttempts.append(Date())
                        }
                        var hello = Message("hello"); hello.id = self.identity.fingerprint; hello.name = self.store.snapshot.name
                        hello.capabilities = self.advertisedCapabilities; hello.version = 1; hello.commitment = PairingProof.commitment(id: self.identity.fingerprint, nonce: session.nonce)
                        session.wire.send(hello); session.wire.begin()
                    } catch { self.fail(session, error) }
                case .failed(let error): self.fail(session, error)
                case .waiting(let error):
                    self.transportWaiting(session,error:error)
                case .cancelled: self.fail(session, PeerError.localized("peerengine.connection_closed", []))
                default: break
                }
            }
            connection.start(queue: queue)
        } catch { connection.cancel(); if !automatic {emit(error.localizedDescription)} }
    }
    private func transportWaiting(_ session:Session,error:Error) {
        if session.transportReady { fail(session,error) }
        else { if !session.automatic {emit(L10n.text("peerengine.waiting_to_connect",error.localizedDescription))}; publishPeers() }
    }
    #if DEBUG
    private var testingReceiveIO: ReceiveStorageIO?
    func testingStorage(_ io: ReceiveStorageIO?) { queue.async { self.testingReceiveIO = io } }
    // Deterministic isolated discovery/path tests; never available in release apps.
    func testingEndpoint(peerID:String,port:UInt16) {
        queue.async {self.endpoints[peerID] = (.hostPort(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:port)!),"Fixture");self.considerStartupConnection();self.publishPeers()}
    }
    func testingRemoveEndpoint(peerID:String) {queue.async {self.endpoints.removeValue(forKey:peerID);self.considerStartupConnection();self.publishPeers()}}
    func testingWaiting(peerID:String) {
        queue.async {if let session=self.sessions.values.first(where:{$0.peerID == peerID && $0.authorized}) {self.transportWaiting(session,error:NWError.posix(.ENETDOWN))}}
    }
    #endif
    public func confirm(sessionID: UUID, approved: Bool) {
        queue.async {
            guard let session = self.sessions[sessionID], session.remoteNonce != nil, !session.authorized else { return }
            guard approved, self.gate.isOpen else { self.fail(session, PeerError.localized("peerengine.pairing_was_not_confirmed", [])); return }
            session.localConfirmed = true; session.wire.send(Message("confirm")); self.authorizeIfReady(session)
        }
    }
    private func removeTrust(_ id:String) throws {
        try store.update { config in
            config.peers.removeAll { $0.id == id }
            if config.lastConnectedPeer == id {config.lastConnectedPeer=nil}
            if config.preferredPeer == id { config.preferredPeer = config.peers.first?.id }
        }
        if startupTarget == id {startupTarget=nil}
    }
    private func unpaired(_ id:String, name:String, remote:Bool, confirmed:Bool) {
        DispatchQueue.main.async { self.onUnpaired?(id,name,remote,confirmed) }
    }
    public func forget(_ id: String) {
        queue.async {
            do {
                let name = self.store.snapshot.peers.first { $0.id == id }?.name ?? "Mac"
                try self.removeTrust(id)
                let candidates = self.sessions.values.filter { $0.peerID == id || $0.expectedID == id }
                let notify = candidates.first { $0.authorized && $0.supportsUnpair && !$0.unpairing }
                for session in candidates where session.id != notify?.id { self.fail(session, PeerError.localized("peerengine.device_trust_removed", [])) }
                if let session = notify {
                    session.unpairing = true; session.unpairRequest = (UUID(),Date())
                    self.abortTransfers(session, PeerError.localized("peerengine.device_trust_removed", []))
                    var request = Message("unpair"); request.id = self.identity.fingerprint; request.transfer = session.unpairRequest!.0
                    session.wire.send(request)
                } else { self.unpaired(id,name:name,remote:false,confirmed:false) }
                self.publishPeers()
            } catch { self.emit(error.localizedDescription) }
        }
    }
    private func handleUnpair(_ message:Message, session:Session) throws {
        guard session.authorized, session.supportsUnpair, message.id == session.peerID, let request = message.transfer else {
            throw PeerError.localized("text.invalid_message", [])
        }
        if message.kind == "unpairReceipt" {
            guard session.unpairRequest?.0 == request else { throw PeerError.localized("text.invalid_message", []) }
            session.unpairRequest = nil
            unpaired(session.peerID,name:session.name,remote:false,confirmed:message.errorKey == nil)
            fail(session,PeerError.localized("peerengine.device_trust_removed", [])); return
        }
        guard !session.unpairing else { throw PeerError.localized("text.invalid_message", []) }
        var receipt = Message("unpairReceipt"); receipt.id = identity.fingerprint; receipt.transfer = request
        do { try removeTrust(session.peerID) }
        catch {
            receipt.errorKey = "unpair.save_failed"
            session.wire.send(receipt); emit(error.localizedDescription); return
        }
        session.unpairing = true
        for other in Array(sessions.values) where other.peerID == session.peerID && other.id != session.id {
            fail(other,PeerError.localized("peerengine.device_trust_removed", []))
        }
        abortTransfers(session,PeerError.localized("peerengine.device_trust_removed", []))
        unpaired(session.peerID,name:session.name,remote:true,confirmed:true); publishPeers()
        session.wire.send(receipt) { [weak self, weak session] _ in
            guard let self, let session else { return }
            self.fail(session,PeerError.localized("peerengine.device_trust_removed", []))
        }
    }
    private func authorizeIfReady(_ session: Session) {
        guard session.localConfirmed, session.remoteConfirmed, !session.authorized, session.remoteNonce != nil else { return }
        guard store.snapshot.peers.contains(where: { $0.id == session.peerID }) || gate.isOpen else { fail(session, PeerError.localized("peerengine.pairing_is_closed", [])); return }
        do {
            try store.update { config in
                if let index = config.peers.firstIndex(where: { $0.id == session.peerID }) { config.peers[index].name = session.name }
                else { config.peers.append(TrustedPeer(id: session.peerID, name: session.name)) }
                if config.preferredPeer == nil { config.preferredPeer = session.peerID }
                config.lastConnectedPeer=session.peerID
            }
            session.authorized = true; session.automatic=false
            if startupTarget == session.peerID {startupTarget=nil}
            DispatchQueue.main.async { self.onPairingEnded?(session.id) }
            publishPeers(); emit(L10n.text("peerengine.connected", String(describing: session.name))); sendNext(session)
        } catch { fail(session, error) }
    }
    private func handle(_ message: Message, session: Session) {
        session.lastActivity = Date()
        do {
            switch message.kind {
            case "hello":
                guard session.commitment == nil, message.version == 1, message.id == session.peerID,
                      let name = message.name, !name.isEmpty, name.utf8.count <= 256,
                      let commitment = message.commitment, commitment.count == 64 else { throw PeerError.localized("peerengine.device_identity_or_protocol_does_not_match", []) }
                guard (message.capabilities?.count ?? 0) <= 32, message.capabilities?.allSatisfy({ $0.utf8.count <= 64 }) ?? true else { throw PeerError.localized("text.invalid_message", []) }
                session.supportsUnpair = message.capabilities?.contains("unpair-v1") == true
                session.supportsText = message.capabilities?.contains("text-v1") == true
                session.name = name; session.commitment = commitment
                var reveal = Message("reveal"); reveal.nonce = session.nonce; session.wire.send(reveal)
            case "reveal":
                guard let commitment = session.commitment, session.remoteNonce == nil, let nonce = message.nonce else { throw PeerError.localized("peerengine.invalid_pairing_step", []) }
                try PairingProof.verify(id: session.peerID, nonce: nonce, commitment: commitment); session.remoteNonce = nonce
                if store.snapshot.peers.contains(where: { $0.id == session.peerID }) {
                    session.localConfirmed = true; session.wire.send(Message("confirm")); authorizeIfReady(session)
                } else {
                    guard gate.isOpen else { throw PeerError.localized("peerengine.pairing_is_closed", []) }
                    let code = PairingProof.code(localID: identity.fingerprint, localNonce: session.nonce,
                                                 remoteID: session.peerID, remoteNonce: nonce, exporter: session.exporter)
                    DispatchQueue.main.async { self.onPairing?(session.id, session.name, code) }
                }
            case "confirm":
                guard session.remoteNonce != nil, !session.remoteConfirmed else { throw PeerError.localized("peerengine.duplicate_or_premature_pairing_confirmation", []) }
                session.remoteConfirmed = true; authorizeIfReady(session)
            default:
                if message.kind == "unpair" || message.kind == "unpairReceipt" { try handleUnpair(message,session:session); return }
                if session.authorized && session.unpairing { return } // Drain data while waiting for the bounded revocation receipt.
                guard session.authorized, !session.unpairing else { throw PeerError.localized("peerengine.unpaired_devices_cannot_send_files", []) }
                if message.kind == "text" || message.kind == "textReceipt" { try handleText(message, session: session) }
                else { try handleTransfer(message, session: session) }
            }
        } catch {
            if message.transfer == session.incomingID, ReceiveStorageError.isFull(error), session.incoming != nil {
                rejectIncoming(session, error: error)
            } else { fail(session, error) }
        }
    }
    @discardableResult
    public func sendText(_ text: String, peerID: String) -> UUID {
        let id = UUID()
        queue.async {
            let session = self.sessions.values.first { $0.peerID == peerID && $0.authorized && $0.transportReady && !$0.unpairing }
            let payload = TextPayload(id: id, peerID: peerID, peerName: session?.name ?? "Mac", text: text)
            do {
                try TextRules.validate(text)
                guard let session else { throw PeerError.localized("text.offline", []) }
                guard session.supportsText else { throw PeerError.localized("text.upgrade", []) }
                guard session.textPending.count < 20 else { throw PeerError.localized("text.busy", []) }
                session.textPending.append(payload); self.sendNextText(session)
            } catch { self.textResult(payload, error) }
        }
        return id
    }
    private func textResult(_ payload: TextPayload, _ error: Error?) { DispatchQueue.main.async { self.onTextResult?(payload, error) } }
    private func sendNextText(_ session: Session) {
        guard session.authorized, session.transportReady, !session.unpairing, session.textOutgoing == nil, !session.textPending.isEmpty else { return }
        let payload = session.textPending.removeFirst(); session.textOutgoing = (payload, Date())
        var message = Message("text"); message.transfer = payload.id; message.text = payload.text
        session.wire.send(message)
    }
    private func handleText(_ message: Message, session: Session) throws {
        guard session.supportsText, let id = message.transfer else { throw PeerError.localized("text.invalid_message", []) }
        if message.kind == "textReceipt" {
            if session.retiredText.contains(id) { return }
            guard let outgoing = session.textOutgoing, outgoing.0.id == id else { throw PeerError.localized("text.invalid_message", []) }
            session.textOutgoing = nil; session.retiredText.append(id); if session.retiredText.count > 256 { session.retiredText.removeFirst() }
            textResult(outgoing.0, nil); sendNextText(session); return
        }
        guard let text = message.text else { throw PeerError.localized("text.invalid_message", []) }
        switch try session.textInbox.receive(id, text: text) {
        case .duplicate:
            var receipt = Message("textReceipt"); receipt.transfer = id; session.wire.send(receipt)
        case .pending: break
        case .new:
            let payload = TextPayload(id: id, peerID: session.peerID, peerName: session.name, text: text)
            DispatchQueue.main.async { [weak self, weak session] in
                guard let self, let session, let callback = self.onTextReceived else { return }
                callback(payload) { [weak self, weak session] in
                    guard let self, let session else { return }
                    self.queue.async {
                        guard self.sessions[session.id] != nil, session.authorized, !session.unpairing else { return }
                        session.textInbox.complete(id)
                        var receipt = Message("textReceipt"); receipt.transfer = id; session.wire.send(receipt)
                    }
                }
            }
        }
    }
    @discardableResult
    public func send(urls: [URL], peerID: String, cleanup: (() -> Void)? = nil) -> UUID {
        let id = UUID()
        queue.async {
            let name = self.store.snapshot.peers.first {$0.id == peerID}?.name ?? "Mac"
            self.stopStartupAttempts(except:peerID)
            let generation = self.serviceGeneration
            self.fileEvent(id,peerID:peerID,name:name,phase:.preparing)
            DispatchQueue.main.async { self.onPreparation?(true) }
            DispatchQueue.global(qos:.userInitiated).async {
                do {
                    let prepared = try PreparedTransfer(urls:urls,cleanup:cleanup)
                    self.queue.async { [self] in
                        DispatchQueue.main.async { self.onPreparation?(false) }
                        guard generation == self.serviceGeneration else {
                            self.fileEvent(id,peerID:peerID,name:name,phase:.failed,error:PeerError.localized("peerengine.service_stopped",[])); return
                        }
                        guard self.store.snapshot.peers.contains(where:{$0.id == peerID}) else {
                            self.fileEvent(id,peerID:peerID,name:name,phase:.failed,error:PeerError.localized("peerengine.pair_with_the_destination_first",[])); return
                        }
                        let pending = PendingFile(id:id,peerID:peerID,peerName:name,prepared:prepared)
                        var session = self.sessions.values.first {$0.peerID == peerID && $0.authorized && $0.transportReady && !$0.unpairing}
                        if session == nil { session = self.sessions.values.first {($0.peerID == peerID || $0.expectedID == peerID) && !$0.unpairing} }
                        if session == nil, let endpoint = self.endpoints[peerID]?.0 {
                            let before = Set(self.sessions.keys); self.dial(endpoint,expected:peerID)
                            session = self.sessions.values.first {!before.contains($0.id)}
                        }
                        guard let session else {
                            self.fileEvent(id,peerID:peerID,name:name,phase:.failed,error:PeerError.localized("peerengine.destination_offline_retry_when_it_is_available",[]),notConnected:true); return
                        }
                        guard session.pending.count < 20 else {
                            self.fileEvent(id,peerID:peerID,name:name,phase:.failed,error:PeerError.localized("peerengine.the_send_queue_is_full",[])); return
                        }
                        session.automatic=false
                        session.pending.append(pending)
                        if session.authorized && session.transportReady {
                            self.fileEvent(id,peerID:peerID,name:name,phase:.queued); self.sendNext(session)
                        } else {
                            self.fileEvent(id,peerID:peerID,name:name,phase:.connecting)
                            self.queue.asyncAfter(deadline:.now()+5) { [weak self,weak session] in
                                guard let self,let session,self.sessions[session.id] != nil,
                                      !(session.authorized && session.transportReady), session.pending.contains(where:{$0.id == id}) else { return }
                                self.fail(session,PeerError.localized("file.connection_timeout",[]))
                            }
                        }
                    }
                } catch {
                    cleanup?()
                    self.queue.async { [self] in
                        DispatchQueue.main.async { self.onPreparation?(false) }
                        self.fileEvent(id,peerID:peerID,name:name,phase:.failed,error:error)
                    }
                }
            }
        }
        return id
    }
    private func fileEvent(_ id:UUID,peerID:String,name:String,phase:FileSendPhase,error:Error?=nil,notConnected:Bool=false) {
        let event=FileSendEvent(id:id,peerID:peerID,peerName:name,phase:phase,error:error,notConnected:notConnected)
        DispatchQueue.main.async { self.onFileSendEvent?(event) }
    }
    private func sendNext(_ session: Session) {
        guard session.authorized, session.transportReady, !session.unpairing, session.outgoing == nil, !session.pending.isEmpty else { return }
        let pending = session.pending.removeFirst()
        let outgoing = Outgoing(pending); session.outgoing = outgoing
        fileEvent(pending.id,peerID:pending.peerID,name:pending.peerName,phase:.started)
        var offer = Message("offer"); offer.transfer = outgoing.id; offer.manifest = outgoing.prepared.manifest
        session.lastActivity = Date(); session.wire.send(offer); update(session, outgoing: outgoing, status: L10n.text("peerengine.waiting_for_the_receiver"))
    }
    private func handleTransfer(_ message: Message, session: Session) throws {
        guard let transferID = message.transfer else { throw PeerError.localized("peerengine.transfer_identifier_is_missing", []) }
        if session.cancelledTransfers.contains(transferID), message.kind != "offer" { return }
        switch message.kind {
        case "offer":
            guard !session.cancelledTransfers.contains(transferID) else { throw PeerError.localized("peerengine.invalid_transfer_end_message", []) }
            session.drainingCancelledIncoming = false
            guard session.incoming == nil, let manifest = message.manifest,
                  sessions.values.filter({ $0.incoming != nil }).count < 4 else { throw PeerError.localized("peerengine.receiver_busy_or_invalid_manifest", []) }
            do {
                let destination = URL(fileURLWithPath: store.snapshot.receivePath)
                #if DEBUG
                session.incoming = try ReceiveTransaction(manifest: manifest, destination: destination, io: testingReceiveIO ?? ReceiveStorageIO())
                #else
                session.incoming = try ReceiveTransaction(manifest: manifest, destination: destination)
                #endif
                session.incomingID = transferID
                var accept = Message("accept"); accept.transfer = transferID; session.wire.send(accept)
                updateIncoming(session, status: L10n.text("peerengine.receiving"))
            } catch {
                sendRejection(error, id: transferID, session: session)
                let update = TransferUpdate(id: transferID, peerName: session.name, receiving: true, completed: 0,
                                            total: manifest.byteCount, status: error.localizedDescription, finished: true, succeeded: false)
                DispatchQueue.main.async { self.onTransfer?(update) }
                emit(error.localizedDescription)
            }
        case "accept":
            guard let outgoing = session.outgoing, outgoing.id == transferID, outgoing.index == -1 else { throw PeerError.localized("peerengine.invalid_acceptance_message", []) }
            advanceFile(session, outgoing: outgoing)
        case "file":
            guard session.incomingID == transferID, let incoming = session.incoming, let index = message.index else { throw PeerError.localized("peerengine.invalid_file_start_message", []) }
            try incoming.beginFile(index: index)
        case "endFile":
            guard session.incomingID == transferID, let incoming = session.incoming, let index = message.index, let hash = message.hash else { throw PeerError.localized("peerengine.invalid_file_end_message", []) }
            try incoming.endFile(index: index, expectedHash: hash)
        case "finish":
            guard session.incomingID == transferID, let incoming = session.incoming else { throw PeerError.localized("peerengine.invalid_transfer_end_message", []) }
            let paths = try incoming.finish()
            var receipt = Message("receipt"); receipt.transfer = transferID; receipt.paths = paths.map(\.lastPathComponent); session.wire.send(receipt)
            updateIncoming(session, status: L10n.text("receive.completed", paths.count), finished: true, succeeded: true)
            session.incoming = nil; session.incomingID = nil
            DispatchQueue.main.async { self.onReceived?(session.name, paths) }
        case "receipt":
            guard let outgoing = session.outgoing, outgoing.id == transferID, outgoing.waitingForReceipt,
                  message.paths?.count == outgoing.prepared.manifest.roots.count else { throw PeerError.localized("peerengine.invalid_save_receipt", []) }
            update(session, outgoing: outgoing, status: L10n.text("peerengine.saved_by_the_other_mac"), finished: true, succeeded: true)
            session.outgoing = nil; sendNext(session)
        case "reject":
            guard let outgoing = session.outgoing, outgoing.id == transferID else { throw PeerError.localized("peerengine.invalid_rejection_message", []) }
            let reason = L10n.remoteError(key: message.errorKey, arguments: message.errorArguments, fallback: message.text ?? L10n.text("peerengine.the_other_device_could_not_receive_the_files"))
            update(session, outgoing: outgoing, status: reason, finished: true)
            emit(reason)
            retireCancelled(transferID, session: session)
            session.outgoing = nil; sendNext(session)
        case "cancel":
            retireCancelled(transferID,session:session)
            if session.incomingID == transferID {
                updateIncoming(session, status: L10n.text("peerengine.transfer_cancelled"), finished: true); session.incoming?.cancel(); session.incoming = nil; session.incomingID = nil
            } else if let outgoing = session.outgoing, outgoing.id == transferID {
                update(session, outgoing: outgoing, status: L10n.text("peerengine.transfer_cancelled"), finished: true); session.outgoing = nil; sendNext(session)
            }
        default: throw PeerError.localized("peerengine.unknown_protocol_message", [])
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
                update(session, outgoing: outgoing, status: L10n.text("peerengine.verifying_and_saving")); return
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
                guard (try file.read(upToCount: 1) ?? Data()).isEmpty else { throw PeerError.localized("peerengine.the_file_changed_during_sending_try_again", []) }
                try file.close(); outgoing.file = nil
                var end = Message("endFile"); end.transfer = outgoing.id; end.index = outgoing.index
                end.hash = outgoing.hash.finalize().map { String(format: "%02x", $0) }.joined()
                session.wire.send(end) { [weak self, weak session, weak outgoing] error in
                    if error == nil, let session, let outgoing { self?.advanceFile(session, outgoing: outgoing) }
                }; return
            }
            let data = try file.read(upToCount: Int(min(outgoing.remaining, 65536))) ?? Data()
            guard !data.isEmpty else { throw PeerError.localized("peerengine.the_source_file_became_shorter_or_unreadable", []) }
            outgoing.hash.update(data: data); outgoing.remaining -= Int64(data.count); outgoing.completed += Int64(data.count)
            session.lastActivity = Date()
            update(session, outgoing: outgoing, status: L10n.text("peerengine.sending"), throttle: true)
            session.wire.sendChunk(data) { [weak self, weak session, weak outgoing] error in
                if error == nil, let session, let outgoing { self?.pump(session, outgoing: outgoing) }
            }
        } catch { fail(session, error) }
    }
    private func chunk(_ data: Data, session: Session) {
        do {
            if session.authorized && session.unpairing { return }
            if session.incoming == nil, session.drainingCancelledIncoming { return }
            guard session.authorized, !session.unpairing, let incoming = session.incoming else { throw PeerError.localized("peerengine.invalid_file_data", []) }
            try incoming.append(data); session.lastActivity = Date(); updateIncoming(session, status: L10n.text("peerengine.receiving"))
        } catch {
            if session.incoming != nil, ReceiveStorageError.isFull(error) { rejectIncoming(session, error: error) }
            else { fail(session, error) }
        }
    }
    private func sendRejection(_ error: Error, id: UUID, session: Session) {
        var reject = Message("reject"); reject.transfer = id
        if let peerError = error as? PeerError, case .localized(let key, let arguments) = peerError {
            reject.errorKey = key; reject.errorArguments = arguments
            reject.text = TranslationCatalog(preferences: ["en"]).format(key, arguments: arguments.map { $0 as CVarArg })
        } else { reject.text = error.localizedDescription }
        session.wire.send(reject)
    }
    private func rejectIncoming(_ session: Session, error: Error) {
        guard let incoming = session.incoming, let id = session.incomingID else { return }
        let failure = ReceiveStorageError.normalize(error, saved: incoming.committed.count)
        updateIncoming(session, status: failure.localizedDescription, finished: true)
        incoming.cancel(); session.incoming = nil; session.incomingID = nil
        retireCancelled(id, session: session)
        // Ordered old frames are drained until the next offer, without touching reverse traffic.
        session.drainingCancelledIncoming = true
        sendRejection(failure, id: id, session: session); emit(failure.localizedDescription)
    }
    private func retireCancelled(_ id:UUID,session:Session) {
        if !session.cancelledTransfers.contains(id) { session.cancelledTransfers.append(id) }
        if session.cancelledTransfers.count > 256 { session.cancelledTransfers.removeFirst() }
    }
    public func cancel(transferID: UUID) {
        queue.async {
            for session in Array(self.sessions.values) {
                if session.outgoing?.id == transferID || session.incomingID == transferID {
                    self.retireCancelled(transferID,session:session)
                    var message = Message("cancel"); message.transfer = transferID
                    session.wire.send(message)
                    if session.incomingID == transferID {
                        self.updateIncoming(session,status:L10n.text("peerengine.transfer_cancelled"),finished:true)
                        session.incoming?.cancel(); session.incoming = nil; session.incomingID = nil
                        session.drainingCancelledIncoming = true
                    } else if let outgoing = session.outgoing, outgoing.id == transferID {
                        self.update(session,outgoing:outgoing,status:L10n.text("peerengine.transfer_cancelled"),finished:true)
                        session.outgoing = nil; self.sendNext(session)
                    }
                }
            }
        }
    }
    private func update(_ session: Session, outgoing: Outgoing, status: String, finished: Bool = false, succeeded: Bool = false, throttle: Bool = false) {
        let now = Date.timeIntervalSinceReferenceDate
        if !finished, throttle, now - (session.uiUpdates[outgoing.id] ?? 0) < 0.1 { return }
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
        if session.unpairRequest != nil {
            session.unpairRequest = nil; unpaired(session.peerID,name:session.name,remote:false,confirmed:false)
        }
        abortTransfers(session,error)
        session.wire.close(); DispatchQueue.main.async { self.onPairingEnded?(session.id) }
        if !session.automatic {emit(error.localizedDescription)}; publishPeers()
    }
    private func abortTransfers(_ session:Session, _ error:Error) {
        if let text = session.textOutgoing { textResult(text.0, error) }
        for text in session.textPending { textResult(text, error) }
        session.textOutgoing = nil; session.textPending.removeAll()
        if let outgoing = session.outgoing { update(session, outgoing: outgoing, status: error.localizedDescription, finished: true) }
        if session.incoming != nil {
            let count = session.incoming?.committed.count ?? 0
            updateIncoming(session, status: count > 0 ? L10n.text("receive.partial_error", count, error.localizedDescription) : error.localizedDescription, finished: true)
        }
        for pending in session.pending {
            fileEvent(pending.id,peerID:pending.peerID,name:pending.peerName,phase:.failed,error:error,notConnected:true)
        }
        session.incoming?.cancel(); session.incoming = nil; session.outgoing = nil; session.pending.removeAll()
    }
    private func tick() {
        if pairingWasOpen, !gate.isOpen { pairingWasOpen = false; advertise(); emit(L10n.text("peerengine.pairing_is_closed")) }
        for session in Array(sessions.values) {
            if let pending = session.unpairRequest, Date().timeIntervalSince(pending.1) >= 5 { fail(session,PeerError.localized("unpair.timeout", [])); continue }
            if let outgoing = session.textOutgoing, Date().timeIntervalSince(outgoing.1) >= 30 {
                session.textOutgoing = nil; session.retiredText.append(outgoing.0.id)
                if session.retiredText.count > 256 { session.retiredText.removeFirst() }
                textResult(outgoing.0, PeerError.localized("text.unconfirmed", [])); sendNextText(session)
            }
            if !session.authorized, Date().timeIntervalSince(session.created) > 120 { fail(session, PeerError.localized("peerengine.pairing_timed_out", [])) }
            else if (session.outgoing != nil || session.incoming != nil || !session.pending.isEmpty), Date().timeIntervalSince(session.lastActivity) > 60 {
                fail(session, PeerError.localized("peerengine.transfer_timed_out_check_the_network_and_retry", []))
            }
        }
    }
}
