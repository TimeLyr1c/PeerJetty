import Foundation
import Network

struct Message: Codable {
    var kind: String
    var id: String?
    var name: String?
    var version: Int?
    var commitment: String?
    var nonce: Data?
    var transfer: UUID?
    var manifest: TransferManifest?
    var index: Int?
    var hash: String?
    var text: String?
    var errorKey: String?
    var errorArguments: [String]?
    var paths: [String]?
    init(_ kind: String) { self.kind = kind }
}

final class FramedConnection {
    static let maxFrame = 8 * 1024 * 1024
    let connection: NWConnection
    var onMessage: ((Message) -> Void)?
    var onChunk: ((Data) -> Void)?
    var onFailure: ((Error) -> Void)?
    private var closed = false
    init(_ connection: NWConnection) { self.connection = connection }
    func begin() { readHeader() }
    func close() { closed = true; connection.cancel() }
    func send(_ message: Message, completion: ((Error?) -> Void)? = nil) {
        do { send(try JSONEncoder().encode(message), type: 0, completion: completion) }
        catch { completion?(error); onFailure?(error) }
    }
    func sendChunk(_ data: Data, completion: @escaping (Error?) -> Void) { send(data, type: 1, completion: completion) }
    private func send(_ body: Data, type: UInt8, completion: ((Error?) -> Void)?) {
        guard !closed, body.count < Self.maxFrame else { completion?(PeerError.localized("framing.connection_closed_or_message_too_large", [])); return }
        var length = UInt32(body.count + 1).bigEndian
        var packet = withUnsafeBytes(of: &length) { Data($0) }
        packet.append(type); packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            completion?(error)
            if let error { self?.onFailure?(error) }
        })
    }
    private func readHeader() {
        readExact(4) { [weak self] data in
            guard let self else { return }
            let count = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard count > 1, count <= Self.maxFrame else { self.fail(PeerError.localized("framing.invalid_message_length", [])); return }
            self.readExact(Int(count)) { [weak self] data in
                guard let self else { return }
                do {
                    if data[0] == 0 { self.onMessage?(try JSONDecoder().decode(Message.self, from: data.dropFirst())) }
                    else if data[0] == 1, data.count <= 65537 { self.onChunk?(Data(data.dropFirst())) }
                    else { throw PeerError.localized("framing.invalid_message_type", []) }
                    if !self.closed { self.readHeader() }
                } catch { self.fail(error) }
            }
        }
    }
    private func readExact(_ count: Int, accumulated: Data = Data(), completion: @escaping (Data) -> Void) {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let error { self.fail(error); return }
            var buffer = accumulated
            if let data { buffer.append(data) }
            if buffer.count == count { completion(buffer) }
            else if isComplete { self.fail(PeerError.localized("framing.the_other_device_disconnected", [])) }
            else { self.readExact(count, accumulated: buffer, completion: completion) }
        }
    }
    private func fail(_ error: Error) { guard !closed else { return }; close(); onFailure?(error) }
}
