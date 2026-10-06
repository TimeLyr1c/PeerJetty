# Changes

## 0.2.4 / build 6 — optional receive auto-open, local candidate, 2026-10-05

Adds a persistent receiver-side “open after receiving” switch, disabled by default including legacy configuration upgrades. Only successful committed roots are handed to the system default application; opening failures preserve received files and are reported. Settings now scroll to accommodate smaller screens. Pairing and transfer protocol unchanged; physical two-Mac behavior remains to be checked.

## 0.2.3 / build 5 — new icon, local candidate, 2026-10-05

Uses the project owner’s replacement PeerJetty PNG and records the non-notch display improvement plan. The display behavior is unchanged in this build; screen-edge activation and geometry adjustments are planned separately. Pairing and transfer implementation unchanged. Not automatically installed or published.

## 0.2.2 / build 4 — PeerJetty rename, local candidate, 2026-10-05

Renames the app UI, SwiftPM target, executable, build output and new installer filenames to PeerJetty. Copies validated legacy settings once without overwriting current settings or deleting the old file; preserves the Bundle ID, Keychain identity and protocol v1 identifiers for compatibility. Adds MIT licensing records and bundles LICENSE with the app. Keeps Original and historical packages unchanged. Compilation and automated checks are recorded in VALIDATION.md; physical upgrade acceptance remains pending. Not automatically installed or publicly released.

## 0.2.1 / build 3 — local test candidate, 2026-10-05

Adds version/build display in Settings and About, build provenance including source revision and dirty state, explicit version management, and immutable installer archives with checksums. Records the i18n, naming, licensing, GitHub and update roadmap. No changes to the pairing identity or transfer protocol; not automatically installed or publicly released.

## 0.2.0 — 2026-10-04

Native bidirectional LAN app with Bonjour discovery, mutual TLS, two-screen pairing confirmation, device trust/revocation, Keychain identity, configurable destination, streamed files/folders, integrity checks, exclusive collision-safe commits, progress/cancellation, notifications, menu/settings and notch/non-notch drop zone. Received files are never opened automatically. No SSH or per-user connection credentials in source.

Preserves Original starter separately. macOS 15+ required for memory-only test identity import. First local build is arm64, ad hoc signed, not notarized. Two-device physical acceptance and original source/icon licensing remain pending before public release.
