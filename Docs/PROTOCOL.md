# Protocol v1

## Identity and discovery

Each installation generates an RSA-2048 self-signed X.509 certificate (10-year validity). The device ID is the SHA-256 fingerprint of its DER certificate. The private PKCS#12 identity and its random passphrase are stored together in an app-specific, device-only, non-synchronizing Keychain generic-password item. PKCS#12 import is memory-only on supported macOS 15+. Certificate generation invokes the system openssl executable with a random temporary directory (0700) and private files (0600); files are removed on completion. No user SSH identity is used.

Bonjour advertises `_openonmini._tcp` with TXT `id`, `name`, and `pairing`. It is discovery information, never proof of identity. The name is `Mac` outside the two-minute pairing window. Public certificate fingerprints are observable on the local network. Listener ports are assigned dynamically; manual host/port connection uses the same authentication rules.

## TLS and pairing

Network.framework uses mutual TLS 1.3, ALPN `openonmini-v1`, and app-specific certificate verification. Peers must present certificates; self-connections are refused. A stored fingerprint must match the actual leaf certificate. Discovery-based outgoing connections also pin the advertised target ID. Unknown certificates are provisionally accepted only while the local pairing gate is open; such a connection has no file-transfer authority.

The application exchanges `hello(version:1, id, name, commitment)`, then `reveal(nonce)`. Each fresh 32-byte nonce is committed using SHA-256 with domain `OpenOnMini-SAS-v1`, local certificate fingerprint and nonce. A reveal must match the commitment. A six-digit code is derived from SHA-256 over a separate pairing-code domain, the TLS exporter (label `EXPORTER-OpenOnMini-Pairing-v1`, 32 bytes), and the canonically ordered fingerprints/nonces. Both users must compare both screens and send confirmation. Authorization requires both confirmations, valid commitment/reveal, and an open local gate for new trust. Known pinned peers automatically confirm reconnects.

Commit-before-reveal and exporter binding prevent simply choosing a nonce after seeing the other nonce, or replaying an old code on a new TLS connection. The short code has limited entropy; the implementation allows one unknown pairing session at a time, five provisional handshakes in 120 seconds, and eight total sessions. It does not constitute an independently audited pairing standard. SHA-256/TLS primitives are system implementations, but the surrounding protocol and its limits need review before broad public distribution. Automated tests cover code symmetry, changed exporter/nonces, incorrect commitments, TLS reconnect/revocation, and rejection of an unknown third identity; they are not a full adversarial audit.

Unpairing deletes local trust first and stops file/text work immediately. With the optional `unpair-v1` capability it also requests persisted revocation on the peer, as described below. A one-sided revoke is sufficient for that side to deny reconnects outside pairing mode. Reopening pairing is an explicit opportunity to create fresh trust. Reset generates a new identity on next launch; the other device must remove its old trust and pair again.

## Framing and transfer

A frame begins with a 4-byte big-endian length, followed by one type byte: 0 for Codable JSON messages, 1 for binary chunks. Length includes the type byte. JSON frames are at most 8 MiB; binary chunks at most 64 KiB. Reads handle partial delivery; chunk sends wait for Network completion to bound memory. Protocol errors close the connection.

Only authorized sessions may offer transfers. `offer` carries a UUID, root names and ordered entries. Receiver validates the entire manifest before creating anything: root count <=1,000, entries <=100,000, bounded sizes with overflow checks, ordinary permission bits only, unique relative paths, parents already present as directories. Source enumeration caps depth at 128. Top-level symlinks, absolute/escaping/cyclic symlinks and special files are rejected. Internal relative links are resolved virtually to detect composed escapes before any links are created.

Receiver returns `accept` or `reject`. Regular files use `file(index)`, binary frames and `endFile(index, sha256)`; zero-byte files follow the same sequence. All files must match length and hash. `finish` triggers final commit; only then does `receipt` acknowledge saved roots. The sender cannot report success before this receipt. Both directions can transfer concurrently; one active outgoing and incoming transaction per connection, up to 20 queued tasks per connection and four active incoming transactions overall.

Staging directories `.PeerJetty-Partial-UUID` are private and inside the selected receive directory, so final rename remains on the same filesystem. Files use exclusive creation with O_NOFOLLOW. Content is synchronized before completion. Internal links are created last. Final roots use renamex_np(RENAME_EXCL); collisions add a bounded UTF-8-safe suffix rather than overwrite, including existing dangling symlinks. A multi-root transfer commits roots individually: a late failure may leave earlier, fully verified roots saved; the error reports their count. Already committed roots are never deleted to roll back.

From build23, cancellation sends the existing task-scoped `cancel` UUID and removes only that task’s uncommitted staging. Other-direction and queued work remain on the same connection. A locally cancelled incoming task drains already-in-flight frames until the next ordered offer; cancelled UUIDs are cached (up to 256) to ignore late acknowledgements/control frames. This retains existing framing and message compatibility. Older implementations may still close the whole connection when cancelling; ordinary disconnect cleanup then applies. A stalled transfer expires after 60 seconds; an uncompleted pairing expires after 120 seconds. There is no resume protocol. Force-killing the app or losing power may leave hidden partial directories; ordinary cancellation/disconnect cleans them. The app does not silently delete unknown leftovers on launch.

## Current boundaries

LAN only; no relay, NAT traversal, remote wake or continuous synchronization. File content, names, folders and ordinary modes are transferred, not ownership, ACLs, extended attributes, Finder tags or resource forks. Directories retain owner access for safe cleanup. Source files should be closed/saved before sending; transfers are not filesystem snapshots. Growth/shrink during streaming is rejected; a same-size in-place edit may produce a mixed snapshot even though the received bytes match the sent hash. Use an archived copy for mutable datasets or metadata-sensitive packages.

The app runs without App Sandbox in this development build and relies on macOS privacy controls plus user-selected directories. TLS encryption alone does not protect against a malicious already-trusted device: it has permission to send files automatically into the chosen directory. Files remain unopened by default. A local receiver-only opt-in may request system default applications to open fully committed roots after successful receipt; it is not a wire-protocol option and cannot be enabled by the sender. Failed, cancelled or partial transactions do not trigger it. Notification bodies contain only device name and item count. No file-transfer history or file-content telemetry is persisted. From 0.4.0, successful plain-text sends and receipts are recorded locally as described below.

Product rename: PeerJetty 0.2.2 retains protocol v1 service, ALPN, SAS domain and exporter label unchanged, allowing communication with OpenOnMini 0.2.x. Product branding and certificate common names are not authentication criteria; trust uses the certificate fingerprint.

## Optional localized rejection diagnostics (0.3.0)

A `reject` may include `errorKey` and `errorArguments` in addition to `text`. These optional display fields do not change hello version 1, framing, authentication, receipt semantics or transfer authority. New senders render known diagnostics locally using a fixed allowlist of plain-string keys, exact string argument counts and a 4,096 UTF-8 byte limit per argument. Unknown keys, mismatched arguments or legacy messages fall back to literal `text`; remote input is never accepted as a format template. Existing JSON frame limits still apply before decoding.

For owned structured errors, new receivers include English legacy text. Older peers ignore the extra JSON fields and display that text. OS/provider errors may retain their provider's language. Different display languages leave identity, device names, filenames and persisted configuration unchanged. Tests exercise both JSON decoder directions and bilingual diagnostic rendering; real mixed-language/old-version device acceptance is recorded separately.


## Optional plain text (`text-v1`, 0.4.0)

`hello` optionally carries `capabilities: ["text-v1"]`. The protocol version, Bonjour service, ALPN, identity and pairing domains remain unchanged. An absent capability field means files only. Never send a text message to a peer that has not advertised `text-v1` on an authorized TLS connection. This is independent of file offers, chunks and file receipts.

A JSON `text` contains `transfer` (a UUID message ID) and `text` (the original Unicode string); a JSON `textReceipt` contains the same UUID. Empty strings and bodies exceeding 262,144 UTF-8 bytes are rejected. Whitespace-only messages are allowed. JSON escaping does not affect the byte limit; normal framing bounds still apply. No `.txt` file is created, no receive folder is used, and receiver auto-open does not apply.

Each connection permits one text awaiting receipt plus 20 queued texts. The sender reports success only for the matching receipt, then advances the queue. At 30 seconds without receipt it reports **unconfirmed**, does not retry, and advances the queue. Receipt can be lost after the receiver has saved a message: timeout does not prove non-delivery. Late/duplicate receipts for the most recent 256 retired outgoing IDs are ignored; an unrelated receipt is a protocol error. Disconnect fails the active and queued sends.

Receiver callbacks make text viewable before acknowledging it. Normally this means saving to SQLite; if saving fails, the app retains text in a bounded in-memory fallback for the current run, warns that history was not saved, and allows explicit copying before acknowledgement. The receiver caches the last 256 message UUIDs and UTF-8 SHA-256 digests within the connection. Identical pending duplicates do not get premature receipts; completed duplicates receive a receipt without another delivery/history entry. Same ID with different bytes closes the connection. SQLite also deduplicates matching message/direction/peer tuples across reconnects; this is not an automatic retry protocol.

Successful sends (after receipt) and receives are always recorded on each device independently. Local visibility and retention are never sent over the connection. See [Text and local history](TEXT.md) for storage, permissions, deletion and privacy. Notifications contain only sender device names and record IDs; message contents and URLs are neither opened nor executed, and the clipboard changes only when the user chooses Copy.


## Optional bilateral unpairing (`unpair-v1`, 0.4.0/build23)

New `hello` messages advertise `text-v1` and `unpair-v1`; neither capability changes protocol version, TLS, framing, identity or SAS. An absent capability remains compatible with file transfer. A JSON `unpair` carries `id` (the sender's certificate fingerprint) and `transfer` (request UUID). The receiver accepts it only on an already-authorized connection that advertised `unpair-v1`, and only when `id` matches that connection's authenticated peer. It cannot name a third device to revoke.

The initiator persists its local trust deletion before requesting remote deletion. It immediately ends that peer's file/text work and closes other connections, retaining only the control connection to wait for a receipt. The receiver persists trust deletion before sending `unpairReceipt` with its own fingerprint and the matching request UUID; it ends affected tasks, refreshes devices/default target, and closes after sending. A save failure returns `errorKey: "unpair.save_failed"` without deleting receiver trust. Only a matching receipt without error confirms remote persistence. A five-second timeout, disconnect, rejection, unsupported old peer or offline device means **local unpaired, remote unconfirmed**. This is not an eventual synchronization service; there is no background retry or automatic pairing approval.

Discovery, stored trust and active authorized TLS connections are separate states. Ordinary disconnection, sleep or app exit updates connection state only; it never deletes stored trust. Re-pairing requires both devices to explicitly open Add Device and confirm a new SAS. Notifications contain only a generic unpairing cue; the device page retains the readable result and a re-pair action.

新版通过已认证连接、可选 `unpair-v1` 能力及匹配请求 ID 同步解除配对；收到端保存成功后才确认。本机先保存撤销，再等待最多五秒。旧版、离线、超时或远端保存失败仅说明本机已解除、对方未确认，不宣称双方同步。普通断线不删除信任；重新配对仍需两端主动开启并核对验证码。


## Connection lifecycle and file request failures (build26)

Discovery and trust do not imply an active transport. A peer is connected only while at least one session is transport-ready, authorized and not unpairing. Established TLS waiting, failure, cancellation or receive EOF removes that session, ends its active/pending work and publishes a fresh peer snapshot. Complete final data is dispatched before terminal receive failure. Normal exit/disconnection retains trust and the default target; it is not an unpair event. No heartbeat was added: a silent network black hole need not be detected immediately.

All file entry points share an ephemeral UUID request; the same UUID becomes the transfer ID when started. Preparation, connecting, queued, started and failed events include peer identity/name; failures include the original error. An authorized ready session sends immediately. Otherwise an existing connection or discovered endpoint may be tried for five seconds from entering connecting. Deadline/connection failure removes unstarted requests and their temporary preparations; there is no durable offline queue, automatic later replay or retry. The deadline applies to connection/authorization, not file hashing or a transfer already started. Multiple pending requests on a failed session each receive one terminal failure.

发现和信任不代表连接可用。已认证 TLS 会话进入不可用等待、失败或结束后，清理该连接任务并刷新设备；最后一段完整数据先交付再处理结束。普通退出不解除信任或默认目标。文件请求带 UUID，进入连接阶段后最多等待五秒；失败任务不离线保存或自动重发。没有新增心跳，静默断网不承诺立即识别。


## Local startup reconnection

`autoConnectLastPeer` (missing = true) and `lastConnectedPeer` (missing = nil) are local configuration only. A successful authorized TLS handshake atomically records the peer ID alongside existing trust maintenance; it does not override a nonempty preferred destination. Startup recovery uses the existing discovery and expected-certificate validation; it never opens the pairing gate or adds protocol messages/capabilities. Only a currently trusted remembered identity is eligible. The startup budget is two discovery-triggered attempts, each bounded to five seconds; unchanged discovery cannot poll/retry. Successful authorization or explicit file/manual connection takes precedence and ends startup recovery. Revocation/reset clears the record. No queued content is sent by recovery.

新增两个本机配置字段，成功认证后保存上次连接身份，与默认目标分离。只向仍信任的发现设备使用原有 TLS 身份校验，不新增协议、配对批准或心跳；不发送旧请求。每次启动最多两次发现触发的五秒尝试，普通退出保留记录，解除与重置清除。
