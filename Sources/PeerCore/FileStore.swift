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
                guard depth < 128, entries.count < 100_000 else { throw PeerError.message("目录层级或文件数量超出限制") }
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
                } else { throw PeerError.message("不支持这种文件类型：\(url.lastPathComponent)") }
            }
            for (index, url) in urls.enumerated() { try visit(url, root: index, path: "", depth: 0) }
            manifest = TransferManifest(roots: urls.map(\.lastPathComponent), entries: entries)
            try manifest.validate()
            self.sources = sources; self.accesses = accesses; self.cleanup = cleanup
        } catch { for url in accesses { url.stopAccessingSecurityScopedResource() }; throw error }
    }
    deinit { for url in accesses { url.stopAccessingSecurityScopedResource() }; cleanup?() }
    func openFile(index: Int) throws -> FileHandle {
        guard let url = sources[index] else { throw PeerError.message("发送文件不存在") }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw PeerError.message("无法读取文件：\(url.lastPathComponent)") }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
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

    public init(manifest: TransferManifest, destination: URL) throws {
        try manifest.validate()
        self.manifest = manifest
        self.destination = destination.resolvingSymlinksInPath().standardizedFileURL
        staging = self.destination.appendingPathComponent(".OpenOnMini-Partial-\(UUID())", isDirectory: true)
        fileIndices = manifest.entries.indices.filter { manifest.entries[$0].kind == .file }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: self.destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PeerError.message("接收目录不存在，请在设置中重新选择")
        }
        guard FileManager.default.isWritableFile(atPath: self.destination.path) else { throw PeerError.message("接收目录无法写入") }
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: self.destination.path)
        if let free = attributes[.systemFreeSize] as? NSNumber, manifest.byteCount > free.int64Value - 16 * 1024 * 1024 {
            throw PeerError.message("接收设备磁盘空间不足")
        }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            for entry in manifest.entries where entry.kind == .directory {
                try FileManager.default.createDirectory(at: location(entry), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
        } catch { try? FileManager.default.removeItem(at: staging); throw error }
    }

    private func location(_ entry: ManifestEntry) -> URL {
        let root = staging.appendingPathComponent(String(entry.root))
        return entry.path.isEmpty ? root : root.appendingPathComponent(entry.path)
    }
    public func beginFile(index: Int) throws {
        guard file == nil, nextFile < fileIndices.count, fileIndices[nextFile] == index else { throw PeerError.message("文件顺序无效") }
        let path = location(manifest.entries[index]).path
        let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw PeerError.message("无法创建接收文件（\(errno)）") }
        file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        currentIndex = index; fileBytes = 0; hash = SHA256()
    }
    public func append(_ data: Data) throws {
        guard let file, let currentIndex, !data.isEmpty,
              Int64(data.count) <= manifest.entries[currentIndex].size - fileBytes else { throw PeerError.message("文件数据长度不匹配") }
        try file.write(contentsOf: data); hash.update(data: data)
        fileBytes += Int64(data.count); received += Int64(data.count)
    }
    public func endFile(index: Int, expectedHash: String) throws {
        guard let file, currentIndex == index, fileBytes == manifest.entries[index].size else { throw PeerError.message("文件未完整接收") }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expectedHash else { throw PeerError.message("文件完整性校验失败") }
        try file.synchronize(); try file.close(); self.file = nil; currentIndex = nil; nextFile += 1
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: manifest.entries[index].mode)], ofItemAtPath: location(manifest.entries[index]).path)
    }
    public func finish() throws -> [URL] {
        guard !complete, file == nil, nextFile == fileIndices.count, received == manifest.byteCount else { throw PeerError.message("传输尚未完成") }
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
                // Same-volume atomic rename with exclusive destination, including dangling symlinks.
                if renamex_np(source.path, candidate.path, UInt32(RENAME_EXCL)) == 0 { committed.append(candidate); break }
                guard errno == EEXIST, number < 100_000 else { throw PeerError.message("提交接收文件失败（\(errno)）；已保存 \(committed.count) 项") }
                number += 1
            }
        }
        complete = true; try? FileManager.default.removeItem(at: staging)
        return committed
    }
    public func cancel() { try? file?.close(); file = nil; try? FileManager.default.removeItem(at: staging) }
    deinit { if !complete { cancel() } }
}
