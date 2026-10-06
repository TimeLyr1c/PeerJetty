import Foundation
import CryptoKit

public enum PeerError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public enum Digest {
    public static func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

public struct TrustedPeer: Codable, Equatable {
    public let id: String
    public var name: String
    public let pairedAt: Date
    public init(id: String, name: String) { self.id = id; self.name = name; pairedAt = Date() }
}

public struct Configuration: Codable {
    public var name: String
    public var receivePath: String
    public var receiveBookmark: Data?
    public var peers: [TrustedPeer]
    public var preferredPeer: String?
    public var onboardingComplete: Bool
    public var autoOpenReceivedFiles: Bool
    public init(name: String, receivePath: String) {
        self.name = name; self.receivePath = receivePath; peers = []; onboardingComplete = false; autoOpenReceivedFiles = false
    }
    private enum CodingKeys: String, CodingKey {
        case name, receivePath, receiveBookmark, peers, preferredPeer, onboardingComplete, autoOpenReceivedFiles
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        receivePath = try values.decode(String.self, forKey: .receivePath)
        receiveBookmark = try values.decodeIfPresent(Data.self, forKey: .receiveBookmark)
        peers = try values.decode([TrustedPeer].self, forKey: .peers)
        preferredPeer = try values.decodeIfPresent(String.self, forKey: .preferredPeer)
        onboardingComplete = try values.decode(Bool.self, forKey: .onboardingComplete)
        autoOpenReceivedFiles = try values.decodeIfPresent(Bool.self, forKey: .autoOpenReceivedFiles) ?? false
    }
}

public final class ConfigurationStore {
    private let lock = NSLock()
    public let url: URL?
    private var value: Configuration
    public init(url: URL?, fallback: Configuration) throws {
        self.url = url
        if let url, FileManager.default.fileExists(atPath: url.path) {
            value = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        } else { value = fallback }
    }
    /// Copy validated legacy settings once, preserving the original for recovery.
    /// An existing PeerJetty configuration always takes precedence, even if corrupt.
    public static func forApplication(applicationSupport: URL, fallback: Configuration) throws -> ConfigurationStore {
        let current = applicationSupport.appendingPathComponent("PeerJetty/configuration.json")
        let legacy = applicationSupport.appendingPathComponent("OpenOnMini/configuration.json")
        if !FileManager.default.fileExists(atPath: current.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            let previous = try ConfigurationStore(url: legacy, fallback: fallback)
            let migrated = try ConfigurationStore(url: current, fallback: previous.snapshot)
            try migrated.update { _ in }
            return migrated
        }
        return try ConfigurationStore(url: current, fallback: fallback)
    }
    public var snapshot: Configuration { lock.lock(); defer { lock.unlock() }; return value }
    public func update(_ change: (inout Configuration) -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        var next = value; change(&next)
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        value = next
    }
}

public struct ManifestEntry: Codable, Equatable {
    public enum Kind: String, Codable { case file, directory, symlink }
    public var root: Int
    public var path: String
    public var kind: Kind
    public var size: Int64
    public var mode: UInt16
    public var link: String?
    public init(root: Int, path: String, kind: Kind, size: Int64 = 0, mode: UInt16 = 0o644, link: String? = nil) {
        self.root = root; self.path = path; self.kind = kind; self.size = size; self.mode = mode; self.link = link
    }
}

public struct TransferManifest: Codable {
    public let roots: [String]
    public let entries: [ManifestEntry]
    public var byteCount: Int64 { entries.reduce(0) { $0 + $1.size } }
    public init(roots: [String], entries: [ManifestEntry]) { self.roots = roots; self.entries = entries }
    public func validate() throws {
        guard !roots.isEmpty, roots.count <= 1000, entries.count <= 100_000 else { throw PeerError.message("文件数量超出限制") }
        try roots.forEach { try FileRules.validateName($0) }
        var paths: [String: ManifestEntry.Kind] = [:]
        var sum: Int64 = 0
        for entry in entries {
            guard roots.indices.contains(entry.root), entry.size >= 0, entry.size <= 1 << 50,
                  entry.mode <= 0o777, entry.kind == .file || entry.size == 0 else { throw PeerError.message("无效文件清单") }
            let (next, overflow) = sum.addingReportingOverflow(entry.size)
            guard !overflow else { throw PeerError.message("文件大小超出限制") }; sum = next
            try FileRules.validateRelative(entry.path, allowEmpty: true)
            let key = "\(entry.root)/\(entry.path)"
            guard paths[key] == nil else { throw PeerError.message("文件清单包含重复路径") }
            if !entry.path.isEmpty {
                let parent = (entry.path as NSString).deletingLastPathComponent
                guard paths["\(entry.root)/\(parent)"] == .directory else { throw PeerError.message("文件父目录无效") }
            }
            if entry.kind == .symlink {
                guard let link = entry.link else { throw PeerError.message("符号链接缺少目标") }
                try FileRules.validateLink(link, from: entry.path)
            } else if entry.link != nil { throw PeerError.message("无效链接信息") }
            if entry.path.isEmpty, entry.kind == .symlink { throw PeerError.message("不能发送顶层符号链接，请选择实际文件") }
            paths[key] = entry.kind
        }
        for root in roots.indices { guard paths["\(root)/"] != nil else { throw PeerError.message("文件清单缺少根目录") } }
        // Resolve chains virtually before creating links: lexical checks alone miss `sub/link/..` escapes.
        let links = Dictionary(uniqueKeysWithValues: entries.filter { $0.kind == .symlink }.map { ("\($0.root)/\($0.path)", $0.link!) })
        for entry in entries where entry.kind == .symlink {
            var remaining = entry.path.split(separator: "/").map(String.init)
            var resolved: [String] = []; var steps = 0
            while !remaining.isEmpty {
                steps += 1; guard steps < 4096 else { throw PeerError.message("符号链接包含循环或过长链条") }
                let part = remaining.removeFirst()
                if part == "." { continue }
                if part == ".." {
                    guard !resolved.isEmpty else { throw PeerError.message("符号链接链条指向接收目录外") }
                    resolved.removeLast(); continue
                }
                resolved.append(part)
                if let target = links["\(entry.root)/\(resolved.joined(separator: "/"))"] {
                    resolved.removeLast(); remaining = target.split(separator: "/").map(String.init) + remaining
                }
            }
        }
    }
}

public enum FileRules {
    public static func validateName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0"),
              name.utf8.count <= 255 else { throw PeerError.message("无效文件名") }
    }
    public static func validateRelative(_ path: String, allowEmpty: Bool = false) throws {
        if path.isEmpty, allowEmpty { return }
        guard !path.hasPrefix("/"), !path.contains("\0"), path.utf8.count <= 4096 else { throw PeerError.message("无效文件路径") }
        for part in path.split(separator: "/", omittingEmptySubsequences: false) { try validateName(String(part)) }
    }
    public static func validateLink(_ link: String, from path: String) throws {
        guard !link.isEmpty, !link.hasPrefix("/"), !link.contains("\0"), !path.isEmpty else { throw PeerError.message("仅支持目录内部的相对符号链接") }
        var components = path.split(separator: "/").dropLast().map(String.init)
        for component in link.split(separator: "/", omittingEmptySubsequences: false) {
            if component == "." { continue }
            if component == ".." {
                guard !components.isEmpty else { throw PeerError.message("符号链接不能指向接收目录外") }
                components.removeLast()
            } else { try validateName(String(component)); components.append(String(component)) }
        }
    }
    public static func collisionName(_ name: String, directory: Bool, number: Int) -> String {
        if number == 0 { return name }
        let ext = (name as NSString).pathExtension
        let suffix = " (\(number))"
        let keepExtension = !directory && !name.hasPrefix(".") && !ext.isEmpty && ext.utf8.count < 100
        let ending = suffix + (keepExtension ? "." + ext : "")
        var stem = keepExtension ? (name as NSString).deletingPathExtension : name
        while stem.utf8.count + ending.utf8.count > 255 { stem.removeLast() }
        return stem + ending
    }
}

public struct DiscoveredPeer: Equatable {
    public let id: String
    public let name: String
    public let paired: Bool
    public let connected: Bool
}

public struct TransferUpdate {
    public let id: UUID
    public let peerName: String
    public let receiving: Bool
    public let completed: Int64
    public let total: Int64
    public let status: String
    public let finished: Bool
    public let succeeded: Bool
}
