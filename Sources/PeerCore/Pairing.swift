import Foundation
import CryptoKit

public enum PairingProof {
    // Protocol v1 domain is stable across product renaming.
    private static let domain = Data("OpenOnMini-SAS-v1\0".utf8)
    public static func commitment(id: String, nonce: Data) -> String {
        Digest.hex(domain + Data(id.utf8) + nonce)
    }
    public static func verify(id: String, nonce: Data, commitment: String) throws {
        guard id.count == 64, nonce.count == 32, self.commitment(id: id, nonce: nonce) == commitment else {
            throw PeerError.localized("pairing.pairing_proof_does_not_match_connection_rejected", [])
        }
    }
    public static func code(localID: String, localNonce: Data, remoteID: String, remoteNonce: Data, exporter: Data) -> String {
        let ordered = localID < remoteID ? [(localID, localNonce), (remoteID, remoteNonce)] : [(remoteID, remoteNonce), (localID, localNonce)]
        var data = domain + exporter
        for (id, nonce) in ordered { data.append(Data(id.utf8)); data.append(nonce) }
        let digest = Array(SHA256.hash(data: data))
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06u", value % 1_000_000)
    }
}
