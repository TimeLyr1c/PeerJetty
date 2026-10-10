import Foundation
import CryptoKit
import Darwin

public final class PreparedTransfer {
    public let manifest: TransferManifest
    let sources: [Int: URL]
    private let accesses: [URL]
    private let cleanup: (() -> Void)?
    public init(urls: [URL], cleanup: (() -> Void)? = nil) throws {
        var accesses: [URL] = []
        for url in urls { if url.startAccessingSecurityScopedResource() { accesses.append(url) } }
        do {
            var entries: [ManifestEntry] = []; var sources: [Int: URL] = [:]
            func visit(_ url: URL, root: Int, path: String, depth: Int) throws {
                guard depth < 128, entries.count < 100_000 else { throw PeerError.localized("filestore.directory_depth_or_file_count_exceeds_the_limit", []) }
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let type = attributes[.type] as? FileAttributeType
                let mode = UInt16((attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644) & 0o777
                if type == .typeDirectory {
                    entries.append(ManifestEntry(root: root, path: path, kind: .directory, mode: mode))
                    let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
                    for child in children { try visit(child, root: root, path: path.isEmpty ? child.lastPathComponent : path + "/" + child.lastPathComponent, depth: depth + 1) }
                } else if type == .typeRegular {
                    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                    sources[entries.count] = url
                    entries.append(ManifestEntry(root: root, path: path, kind: .file, size: size, mode: mode))
                } else if type == .typeSymbolicLink {
                    let target = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                    entries.append(ManifestEntry(root: root, path: path, kind: .symlink, mode: mode, link: target))
                } else { throw PeerError.localized("filestore.unsupported_file_type", [String(describing: url.lastPathComponent)]) }
            }
            for (index, url) in urls.enumerated() { try visit(url, root: index, path: "", depth: 0) }
            manifest = TransferManifest(roots: urls.map(\.lastPathComponent), entries: entries)
            try manifest.validate()
            self.sources = sources; self.accesses = accesses; self.cleanup = cleanup
        } catch { for url in accesses { url.stopAccessingSecurityScopedResource() }; throw error }
    }
    deinit { for url in accesses { url.stopAccessingSecurityScopedResource() }; cleanup?() }
    func openFile(index: Int) throws -> FileHandle {
        guard let url = sources[index] else { throw PeerError.localized("filestore.the_source_file_no_longer_exists", []) }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw PeerError.localized("filestore.could_not_read_file", [String(describing: url.lastPathComponent)]) }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}

// Injectable, transaction-local I/O checkpoints for isolated disk-full checks.
// Live transfers use real filesystem capacity and no injected failures.
struct ReceiveStorageIO {
    enum Stage { case createDirectory, createFile, write, synchronize, commit }
    var availableBytes: (URL) throws -> Int64? = { url in
        (try FileManager.default.attributesOfFileSystem(forPath: url.path)[.systemFreeSize] as? NSNumber)?.int64Value
    }
    var before: (Stage) throws -> Void = { _ in }
}

enum ReceiveStorageError {
    static let fullKey = "filestore.the_receiving_device_has_insufficient_disk_space"
    static let partialKey = "filestore.disk_full_partial"
    static func isFull(_ error: Error, depth: Int = 0) -> Bool {
        if let error = error as? PeerError, case .localized(let key, _) = error {
            return key == fullKey || key == partialKey
        }
        let value = error as NSError
        if value.domain == NSPOSIXErrorDomain && value.code == Int(ENOSPC) { return true }
        if value.domain == NSCocoaErrorDomain && value.code == NSFileWriteOutOfSpaceError { return true }
        if depth < 8, let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error {
            return isFull(underlying, depth: depth + 1)
        }
        return false
    }
    static func normalize(_ error: Error, saved: Int = 0) -> Error {
        guard isFull(error) else { return error }
        return PeerError.localized(saved > 0 ? partialKey : fullKey, saved > 0 ? [String(saved)] : [])
    }
}

public final class ReceiveTransaction {
    public let manifest: TransferManifest
    public let destination: URL
    public let staging: URL
    public private(set) var received: Int64 = 0
    public private(set) var committed: [URL] = []
    private var file: FileHandle?
    private var currentIndex: Int?
    private var fileBytes: Int64 = 0
    private var hash = SHA256()
    private var nextFile = 0
    private let fileIndices: [Int]
    private var complete = false
    private let io: ReceiveStorageIO

    public convenience init(manifest: TransferManifest, destination: URL) throws {
        try self.init(manifest: manifest, destination: destination, io: ReceiveStorageIO())
    }
    init(manifest: TransferManifest, destination: URL, io: ReceiveStorageIO) throws {
        self.io = io
        try manifest.validate()
        self.manifest = manifest
        self.destination = destination.resolvingSymlinksInPath().standardizedFileURL
        staging = self.destination.appendingPathComponent(".PeerJetty-Partial-\(UUID())", isDirectory: true)
        fileIndices = manifest.entries.indices.filter { manifest.entries[$0].kind == .file }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: self.destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PeerError.localized("filestore.the_receive_folder_does_not_exist_choose_it", [])
        }
        guard FileManager.default.isWritableFile(atPath: self.destination.path) else { throw PeerError.localized("filestore.the_receive_folder_is_not_writable", []) }
        if let free = try io.availableBytes(self.destination), manifest.byteCount > free - 16 * 1024 * 1024 {
            throw PeerError.localized("filestore.the_receiving_device_has_insufficient_disk_space", [])
        }
        do {
            try io.before(.createDirectory)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            for entry in manifest.entries where entry.kind == .directory {
                try FileManager.default.createDirectory(at: location(entry), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
        } catch { try? FileManager.default.removeItem(at: staging); throw ReceiveStorageError.normalize(error) }
    }

    private func location(_ entry: ManifestEntry) -> URL {
        let root = staging.appendingPathComponent(String(entry.root))
        return entry.path.isEmpty ? root : root.appendingPathComponent(entry.path)
    }
    public func beginFile(index: Int) throws {
        guard file == nil, nextFile < fileIndices.count, fileIndices[nextFile] == index else { throw PeerError.localized("filestore.invalid_file_order", []) }
        let path = location(manifest.entries[index]).path
        try storage { try io.before(.createFile) }
        let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            let code = errno
            if code == ENOSPC { throw ReceiveStorageError.normalize(NSError(domain: NSPOSIXErrorDomain, code: Int(code))) }
            throw PeerError.localized("filestore.could_not_create_the_received_file", [String(code)])
        }
        file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        currentIndex = index; fileBytes = 0; hash = SHA256()
    }
    public func append(_ data: Data) throws {
        guard let file, let currentIndex, !data.isEmpty,
              Int64(data.count) <= manifest.entries[currentIndex].size - fileBytes else { throw PeerError.localized("filestore.file_data_length_does_not_match", []) }
        try storage { try io.before(.write); try file.write(contentsOf: data) }; hash.update(data: data)
        fileBytes += Int64(data.count); received += Int64(data.count)
    }
    public func endFile(index: Int, expectedHash: String) throws {
        guard let file, currentIndex == index, fileBytes == manifest.entries[index].size else { throw PeerError.localized("filestore.the_file_was_not_received_completely", []) }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expectedHash else { throw PeerError.localized("filestore.file_integrity_check_failed", []) }
        try storage {
            try io.before(.synchronize); try file.synchronize(); try file.close()
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: manifest.entries[index].mode)], ofItemAtPath: location(manifest.entries[index]).path)
        }
        self.file = nil; currentIndex = nil; nextFile += 1
    }
    public func finish() throws -> [URL] {
        guard !complete, file == nil, nextFile == fileIndices.count, received == manifest.byteCount else { throw PeerError.localized("filestore.the_transfer_is_not_complete", []) }
        return try storage {
            for entry in manifest.entries where entry.kind == .symlink {
                try FileManager.default.createSymbolicLink(atPath: location(entry).path, withDestinationPath: entry.link!)
            }
            for entry in manifest.entries.reversed() where entry.kind == .directory {
                try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: entry.mode | 0o700)], ofItemAtPath: location(entry).path)
            }
            for root in manifest.roots.indices {
                let source = staging.appendingPathComponent(String(root))
                let isDirectory = manifest.entries.first { $0.root == root && $0.path.isEmpty }?.kind == .directory
                var number = 0
                while true {
                    let candidate = destination.appendingPathComponent(FileRules.collisionName(manifest.roots[root], directory: isDirectory, number: number))
                    try io.before(.commit)
                    // Same-volume atomic rename with exclusive destination, including dangling symlinks.
                    if renamex_np(source.path, candidate.path, UInt32(RENAME_EXCL)) == 0 { committed.append(candidate); break }
                    let code = errno
                    if code == ENOSPC { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
                    guard code == EEXIST, number < 100_000 else { throw PeerError.localized("filestore.could_not_commit_received_files_saved_count", [String(code), String(committed.count)]) }
                    number += 1
                }
            }
            complete = true; try? FileManager.default.removeItem(at: staging)
            return committed
        }
    }
    private func storage<T>(_ operation: () throws -> T) throws -> T {
        do { return try operation() }
        catch { throw ReceiveStorageError.normalize(error, saved: committed.count) }
    }
    public func cancel() { try? file?.close(); file = nil; try? FileManager.default.removeItem(at: staging) }
    deinit { if !complete { cancel() } }
}
