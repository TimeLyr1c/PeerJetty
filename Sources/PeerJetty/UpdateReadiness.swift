import Foundation

/// Main-thread ownership of update admission. Work survives cancellation; tickets do not.
struct UpdateReadiness {
    struct Ticket: Equatable { let session: UUID; let check: UUID }
    private(set) var session: UUID?
    private var ticket: Ticket?
    private var coreIdle = false
    private(set) var authorized = false
    private(set) var promises: [UUID: String] = [:]
    private(set) var historyWrites = Set<UUID>()
    var blocksNewWork: Bool { session != nil }
    var waiting: Bool { session != nil && !authorized }

    mutating func begin() { session = UUID(); ticket = nil; coreIdle = false; authorized = false }
    mutating func arm() -> Ticket? {
        guard let session, !authorized else { return nil }
        let value = Ticket(session: session, check: UUID())
        ticket = value; coreIdle = false; return value
    }
    @discardableResult mutating func accept(_ value: Ticket) -> Bool {
        guard waiting, ticket == value else { return false }
        coreIdle = true; return true
    }
    mutating func claimInstallation(otherWork: Bool) -> Bool {
        guard waiting, coreIdle, promises.isEmpty, historyWrites.isEmpty, !otherWork else { return false }
        authorized = true; ticket = nil; return true
    }
    mutating func cancel() { session = nil; ticket = nil; coreIdle = false; authorized = false }
    mutating func beginPromise(_ id: UUID, peer: String) { promises[id] = peer }
    mutating func endPromise(_ id: UUID) { promises.removeValue(forKey: id) }
    mutating func beginHistory() -> UUID { let id = UUID(); historyWrites.insert(id); return id }
    mutating func endHistory(_ id: UUID) { historyWrites.remove(id) }
}

enum DropFileSource: Equatable { case files, promise(UUID) }
