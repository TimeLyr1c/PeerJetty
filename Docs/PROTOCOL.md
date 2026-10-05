# Protocol v1

## Identity and discovery

Each installation generates an RSA-2048 self-signed X.509 certificate (10-year validity). The device ID is the SHA-256 fingerprint of its DER certificate. The private PKCS#12 identity and its random passphrase are stored together in an app-specific, device-only, non-synchronizing Keychain generic-password item. PKCS#12 import is memory-only on supported macOS 15+. Certificate generation invokes the system openssl executable with a random temporary directory (0700) and private files (0600); files are removed on completion. No user SSH identity is used.

Bonjour advertises `_openonmini._tcp` with TXT `id`, `name`, and `pairing`. It is discovery information, never proof of identity. The name is `Mac` outside the two-minute pairing window. Public certificate fingerprints are observable on the local network. Listener ports are assigned dynamically; manual host/port connection uses the same authentication rules.

## TLS and pairing

Network.framework uses mutual TLS 1.3, ALPN `openonmini-v1`, and app-specific certificate verification. Peers must present certificates; self-connections are refused. A stored fingerprint must match the actual leaf certificate. Discovery-based outgoing connections also pin the advertised target ID. Unknown certificates are provisionally accepted only while the local pairing gate is open; such a connection has no file-transfer authority.

The application exchanges `hello(version:1, id, name, commitment)`, then `reveal(nonce)`. Each fresh 32-byte nonce is committed using SHA-256 with domain `OpenOnMini-SAS-v1`, local certificate fingerprint and nonce. A reveal must match the commitment. A six-digit code is derived from SHA-256 over a separate pairing-code domain, the TLS exporter (label `EXPORTER-OpenOnMini-Pairing-v1`, 32 bytes), and the canonically ordered fingerprints/nonces. Both users must compare both screens and send confirmation. Authorization requires both confirmations, valid commitment/reveal, and an open local gate for new trust. Known pinned peers automatically confirm reconnects.

Commit-before-reveal and exporter binding prevent simply choosing a nonce after seeing the other nonce, or replaying an old code on a new TLS connection. The short code has limited entropy; the implementation allows one unknown pairing session at a time, five provisional handshakes in 120 seconds, and eight total sessions. It does not constitute an independently audited pairing standard. SHA-256/TLS primitives are system implementations, but the surrounding protocol and its limits need review before broad public distribution. Automated tests cover code symmetry, changed exporter/nonces, incorrect commitments, TLS reconnect/revocation, and rejection of an unknown third identity; they are not a full adversarial audit.

Forgetting a peer deletes local trust and closes its sessions. A one-sided revoke is sufficient for that side to deny reconnects outside pairing mode. Reopening pairing is an explicit opportunity to create fresh trust. Reset generates a new identity on next launch; the other device must remove its old trust and pair again.

## Framing and transfer

A frame begins with a 4-byte big-endian length, followed by one type byte: 0 for Codable JSON messages, 1 for binary chunks. Length includes the type byte. JSON frames are at most 8 MiB; binary chunks at most 64 KiB. Reads handle partial delivery; chunk sends wait for Network completion to bound memory. Protocol errors close the connection.

Only authorized sessions may offer transfers. `offer` carries a UUID, root names and ordered entries. Receiver validates the entire manifest before creating anything: root count <=1,000, entries <=100,000, bounded sizes with overflow checks, ordinary permission bits only, unique relative paths, parents already present as directories. Source enumeration caps depth at 128. Top-level symlinks, absolute/escaping/cyclic symlinks and special files are rejected. Internal relative links are resolved virtually to detect composed escapes before any links are created.

Receiver returns `accept` or `reject`. Regular files use `file(index)`, binary frames and `endFile(index, sha256)`; zero-byte files follow the same sequence. All files must match length and hash. `finish` triggers final commit; only then does `receipt` acknowledge saved roots. The sender cannot report success before this receipt. Both directions can transfer concurrently; one active outgoing and incoming transaction per connection, up to 20 queued tasks per connection and four active incoming transactions overall.

Staging directories `.OpenOnMini-Partial-UUID` are private and inside the selected receive directory, so final rename remains on the same filesystem. Files use exclusive creation with O_NOFOLLOW. Content is synchronized before completion. Internal links are created last. Final roots use renamex_np(RENAME_EXCL); collisions add a bounded UTF-8-safe suffix rather than overwrite, including existing dangling symlinks. A multi-root transfer commits roots individually: a late failure may leave earlier, fully verified roots saved; the error reports their count. Already committed roots are never deleted to roll back.

Cancellation closes the connection, clears pending tasks and removes uncommitted staging. Reconnect trusts the same certificate. A stalled transfer expires after 60 seconds; an uncompleted pairing expires after 120 seconds. There is no resume protocol. Force-killing the app or losing power may leave hidden partial directories; ordinary cancellation/disconnect cleans them. The app does not silently delete unknown leftovers on launch.

## Current boundaries

LAN only; no relay, NAT traversal, remote wake or continuous synchronization. File content, names, folders and ordinary modes are transferred, not ownership, ACLs, extended attributes, Finder tags or resource forks. Directories retain owner access for safe cleanup. Source files should be closed/saved before sending; transfers are not filesystem snapshots. Growth/shrink during streaming is rejected; a same-size in-place edit may produce a mixed snapshot even though the received bytes match the sent hash. Use an archived copy for mutable datasets or metadata-sensitive packages.

The app runs without App Sandbox in this development build and relies on macOS privacy controls plus user-selected directories. TLS encryption alone does not protect against a malicious already-trusted device: it has permission to send files automatically into the chosen directory. Files are never auto-opened or executed. Notification bodies contain only device name and item count. No transfer history or file-content telemetry is persisted.
