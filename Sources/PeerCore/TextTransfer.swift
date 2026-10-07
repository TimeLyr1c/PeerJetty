import Foundation

public enum TextRetention: String, Codable, CaseIterable { case latest500, thirtyDays, forever }
public enum TextDirection: String, Codable { case sent, received }
public struct TextPayload {
    public let id: UUID
    public let peerID: String
    public let peerName: String
    public let text: String
    public init(id: UUID = UUID(), peerID: String, peerName: String, text: String) {
        self.id = id; self.peerID = peerID; self.peerName = peerName; self.text = text
    }
}
public struct TextEntry {
    public let id: UUID
    public let messageID: UUID
    public let direction: TextDirection
    public let peerID: String
    public let peerName: String
    public let date: Date
    public let text: String
    public init(id: UUID = UUID(), messageID: UUID, direction: TextDirection, peerID: String, peerName: String, date: Date = Date(), text: String) {
        self.id = id; self.messageID = messageID; self.direction = direction; self.peerID = peerID; self.peerName = peerName; self.date = date; self.text = text
    }
    public init(payload: TextPayload, direction: TextDirection) {
        self.init(messageID: payload.id, direction: direction, peerID: payload.peerID, peerName: payload.peerName, text: payload.text)
    }
}
public enum TextRules {
    public static let maxBytes = 256 * 1024
    public static func validate(_ text: String) throws {
        guard !text.isEmpty else { throw PeerError.localized("text.empty", []) }
        guard text.utf8.count <= maxBytes else { throw PeerError.localized("text.too_large", []) }
    }
}
/// Bounded, connection-local duplicate protection. Pending entries are not acknowledged twice.
struct TextInbox {
    private var digests: [UUID: String] = [:]
    private var order: [UUID] = []
    private var completed: Set<UUID> = []
    enum Arrival { case new, pending, duplicate }
    mutating func receive(_ id: UUID, text: String) throws -> Arrival {
        try TextRules.validate(text)
        let digest = Digest.hex(Data(text.utf8))
        if let old = digests[id] {
            guard old == digest else { throw PeerError.localized("text.invalid_message", []) }
            return completed.contains(id) ? .duplicate : .pending
        }
        guard order.count < 256 || order.first.map({ completed.contains($0) }) == true else { throw PeerError.localized("text.busy", []) }
        if order.count == 256 { let old = order.removeFirst(); digests.removeValue(forKey: old); completed.remove(old) }
        order.append(id); digests[id] = digest; return .new
    }
    mutating func complete(_ id: UUID) { if digests[id] != nil { completed.insert(id) } }
}
