import Foundation
import SQLite3
import Darwin

/// SQLite operations are serialized; callers use a background queue to keep AppKit responsive.
public final class TextHistory {
    private var db: OpaquePointer?
    private let lock = NSLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public init(url: URL) throws {
        let fm = FileManager.default; let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var stat = stat()
        if lstat(url.path, &stat) == 0 { guard stat.st_mode & S_IFMT == S_IFREG else { throw PeerError.localized("text.history_error", []) } }
        else {
            let fd = open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw PeerError.localized("text.history_error", []) }; close(fd)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(db); db = nil; throw PeerError.localized("text.history_error", [])
        }
        do {
            try execute("PRAGMA journal_mode=DELETE")
            try execute("PRAGMA secure_delete=ON")
            try execute("CREATE TABLE IF NOT EXISTS entries (id TEXT PRIMARY KEY, message TEXT NOT NULL, direction TEXT NOT NULL, peer TEXT NOT NULL, name TEXT NOT NULL, time REAL NOT NULL, body TEXT NOT NULL, UNIQUE(message,direction,peer))")
            try execute("CREATE INDEX IF NOT EXISTS entries_time ON entries(time DESC)")
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw PeerError.localized("text.history_error", []) }
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw PeerError.localized("text.history_error", []) }; return stmt
    }
    private func bind(_ value: String, _ index: Int32, _ stmt: OpaquePointer) {
        _ = value.withCString { sqlite3_bind_text(stmt, index, $0, Int32(value.utf8.count), transient) }
    }
    private func string(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(stmt, index) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: pointer, count: Int(sqlite3_column_bytes(stmt, index))), as: UTF8.self)
    }
    private func prune(_ retention: TextRetention, now: Date) throws {
        if retention == .latest500 { try execute("DELETE FROM entries WHERE id NOT IN (SELECT id FROM entries ORDER BY time DESC,rowid DESC LIMIT 500)") }
        if retention == .thirtyDays {
            let stmt = try statement("DELETE FROM entries WHERE time < ?"); defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, now.addingTimeInterval(-30 * 86400).timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw PeerError.localized("text.history_error", []) }
        }
    }
    public func clean(retention: TextRetention, now: Date = Date()) throws {
        lock.lock(); defer { lock.unlock() }; try prune(retention, now: now)
    }
    @discardableResult
    public func add(_ entry: TextEntry, retention: TextRetention, now: Date = Date()) throws -> UUID {
        try TextRules.validate(entry.text)
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            let stmt = try statement("INSERT OR IGNORE INTO entries VALUES (?,?,?,?,?,?,?)"); defer { sqlite3_finalize(stmt) }
            for (index, value) in [entry.id.uuidString,entry.messageID.uuidString,entry.direction.rawValue,entry.peerID,entry.peerName].enumerated() { bind(value, Int32(index+1), stmt) }
            sqlite3_bind_double(stmt, 6, entry.date.timeIntervalSince1970); bind(entry.text, 7, stmt)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw PeerError.localized("text.history_error", []) }
            let lookup = try statement("SELECT id,body FROM entries WHERE message=? AND direction=? AND peer=?"); defer { sqlite3_finalize(lookup) }
            bind(entry.messageID.uuidString,1,lookup); bind(entry.direction.rawValue,2,lookup); bind(entry.peerID,3,lookup)
            guard sqlite3_step(lookup) == SQLITE_ROW, let id = UUID(uuidString:string(lookup,0)), Data(string(lookup,1).utf8) == Data(entry.text.utf8) else { throw PeerError.localized("text.history_error", []) }
            try prune(retention, now: now); try execute("COMMIT"); return id
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func list(retention: TextRetention, limit: Int = 100, offset: Int = 0, now: Date = Date()) throws -> [TextEntry] {
        lock.lock(); defer { lock.unlock() }; try prune(retention, now: now)
        let stmt = try statement("SELECT * FROM entries ORDER BY time DESC,rowid DESC LIMIT ? OFFSET ?"); defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(min(500, max(1, limit)))); sqlite3_bind_int64(stmt, 2, Int64(max(0,offset)))
        var result: [TextEntry] = []
        while true {
            let state = sqlite3_step(stmt); if state == SQLITE_DONE { break }
            guard state == SQLITE_ROW, let id = UUID(uuidString: string(stmt,0)), let message = UUID(uuidString: string(stmt,1)), let direction = TextDirection(rawValue: string(stmt,2)) else { throw PeerError.localized("text.history_error", []) }
            result.append(TextEntry(id: id, messageID: message, direction: direction, peerID: string(stmt,3), peerName: string(stmt,4), date: Date(timeIntervalSince1970: sqlite3_column_double(stmt,5)), text: string(stmt,6)))
        }
        return result
    }
    public func get(_ id: UUID, retention: TextRetention) throws -> TextEntry? {
        lock.lock(); defer { lock.unlock() }; try prune(retention, now: Date())
        let stmt = try statement("SELECT * FROM entries WHERE id=?"); defer { sqlite3_finalize(stmt) }; bind(id.uuidString,1,stmt)
        let state = sqlite3_step(stmt); if state == SQLITE_DONE { return nil }
        guard state == SQLITE_ROW, let message = UUID(uuidString: string(stmt,1)), let direction = TextDirection(rawValue: string(stmt,2)) else { throw PeerError.localized("text.history_error", []) }
        return TextEntry(id:id,messageID:message,direction:direction,peerID:string(stmt,3),peerName:string(stmt,4),date:Date(timeIntervalSince1970:sqlite3_column_double(stmt,5)),text:string(stmt,6))
    }
    public func delete(_ id: UUID? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        if let id {
            let stmt = try statement("DELETE FROM entries WHERE id=?"); defer { sqlite3_finalize(stmt) }; bind(id.uuidString,1,stmt)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw PeerError.localized("text.history_error", []) }
        } else { try execute("DELETE FROM entries") }
    }
}
