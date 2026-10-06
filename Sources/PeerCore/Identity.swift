import Foundation
import Security
import Network

public final class DeviceIdentity {
    private struct Stored: Codable { let archive: Data; let password: String }
    public let identity: SecIdentity
    public let certificate: SecCertificate
    public let fingerprint: String
    // Preserve the established Keychain identity across product renaming.
    private static let service = "app.openonmini.identity.v1"

    private init(_ stored: Stored) throws {
        var options: [String: Any] = [kSecImportExportPassphrase as String: stored.password]
        if #available(macOS 15, *) { options[kSecImportToMemoryOnly as String] = true }
        var items: CFArray?
        let status = SecPKCS12Import(stored.archive as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess, let entries = items as? [[String: Any]], let first = entries.first,
              let item = first[kSecImportItemIdentity as String] else { throw PeerError.localized("identity.could_not_load_the_local_identity", [String(describing: status)]) }
        identity = item as! SecIdentity
        var cert: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert else { throw PeerError.localized("identity.the_local_certificate_is_invalid", []) }
        certificate = cert
        fingerprint = Digest.hex(SecCertificateCopyData(cert) as Data)
    }

    public static func load() throws -> DeviceIdentity {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: "identity",
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return try DeviceIdentity(JSONDecoder().decode(Stored.self, from: data))
        }
        guard status == errSecItemNotFound else { throw PeerError.localized("identity.could_not_read_the_keychain_identity", [String(describing: status)]) }
        let stored = try generate()
        let identity = try DeviceIdentity(stored)
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service, kSecAttrAccount as String: "identity",
                                  kSecAttrLabel as String: L10n.text("identity.peerjetty_device_identity"),
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                  kSecAttrSynchronizable as String: false,
                                  kSecValueData as String: try JSONEncoder().encode(stored)]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw PeerError.localized("identity.could_not_save_the_keychain_identity", [String(describing: addStatus)]) }
        return identity
    }

    // Isolated integration tests never read or modify the user's Keychain.
    public static func ephemeral() throws -> DeviceIdentity { try DeviceIdentity(generate()) }

    public static func reset() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: "identity"]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PeerError.localized("identity.could_not_reset_the_local_identity", [String(describing: status)]) }
    }

    public static func random(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw PeerError.localized("identity.could_not_generate_secure_random_data", []) }
        return Data(bytes)
    }

    private static func generate() throws -> Stored {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PeerJetty-Identity-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = folder.appendingPathComponent("key.pem").path
        let cert = folder.appendingPathComponent("cert.pem").path
        let archive = folder.appendingPathComponent("identity.p12")
        // A new private directory contains the temporary unencrypted key; it never enters source or logs.
        try runOpenSSL(["req", "-x509", "-newkey", "rsa:2048", "-sha256", "-nodes", "-days", "3650",
                        "-subj", "/CN=PeerJetty-\(UUID())", "-keyout", key, "-out", cert,
                        "-addext", "basicConstraints=critical,CA:FALSE", "-addext", "extendedKeyUsage=serverAuth,clientAuth"])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key)
        let password = try random(32).base64EncodedString()
        try runOpenSSL(["pkcs12", "-export", "-inkey", key, "-in", cert, "-out", archive.path, "-passout", "stdin"],
                       input: Data((password + "\n").utf8))
        return Stored(archive: try Data(contentsOf: archive), password: password)
    }

    private static func runOpenSSL(_ args: [String], input: Data? = nil) throws {
        let process = Process(); let errors = Pipe(); let stdin = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl"); process.arguments = args
        process.standardOutput = FileHandle.nullDevice; process.standardError = errors
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        try process.run()
        if let input { try stdin.fileHandleForWriting.write(contentsOf: input); try stdin.fileHandleForWriting.close() }
        _ = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw PeerError.localized("identity.local_identity_generation_failed", [String(describing: process.terminationStatus)]) }
    }
}

final class PairingGate {
    private let lock = NSLock()
    private var deadline = Date.distantPast
    func open() { lock.lock(); deadline = Date().addingTimeInterval(120); lock.unlock() }
    func close() { lock.lock(); deadline = .distantPast; lock.unlock() }
    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return Date() < deadline }
}

enum TLS {
    static func parameters(identity: DeviceIdentity, store: ConfigurationStore, gate: PairingGate,
                           expected: String? = nil, queue: DispatchQueue, onDenied: ((String) -> Void)? = nil) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, sec_identity_create(identity.identity)!)
        sec_protocol_options_set_peer_authentication_required(tls.securityProtocolOptions, true)
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "openonmini-v1")
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, securityTrust, complete in
            let trust = sec_trust_copy_ref(securityTrust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let cert = chain.first else { complete(false); return }
            let id = Digest.hex(SecCertificateCopyData(cert) as Data)
            guard id != identity.fingerprint, expected == nil || expected == id,
                  store.snapshot.peers.contains(where: { $0.id == id }) || gate.isOpen else { onDenied?(id); complete(false); return }
            // A pinned leaf is the trust anchor; unknown leaves are provisionally allowed ONLY in the pairing window.
            // Application messages remain gated until both users have authenticated the SAS and confirmed.
            SecTrustSetAnchorCertificates(trust, [cert] as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)
            SecTrustSetPolicies(trust, SecPolicyCreateBasicX509())
            complete(SecTrustEvaluateWithError(trust, nil))
        }, queue)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = false
        return parameters
    }
    static func peerFingerprint(_ connection: NWConnection) throws -> String {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { throw PeerError.localized("identity.tls_identity_is_missing", []) }
        var certificate: SecCertificate?
        sec_protocol_metadata_access_peer_certificate_chain(metadata.securityProtocolMetadata) { entry in
            if certificate == nil { certificate = sec_certificate_copy_ref(entry).takeRetainedValue() }
        }
        guard let certificate else { throw PeerError.localized("identity.the_other_device_did_not_provide_an_identity", []) }
        return Digest.hex(SecCertificateCopyData(certificate) as Data)
    }
    static func exporter(_ connection: NWConnection) throws -> Data {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { throw PeerError.localized("identity.tls_connection_information_is_missing", []) }
        let label = "EXPORTER-OpenOnMini-Pairing-v1"
        let secret = label.withCString { sec_protocol_metadata_create_secret(metadata.securityProtocolMetadata, label.utf8.count, $0, 32) }
        guard let secret else { throw PeerError.localized("identity.could_not_verify_the_pairing_code", []) }
        return Data(secret as DispatchData)
    }
}
