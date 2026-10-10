# Release workflow / 发布流程

Repository: https://github.com/TimeLyr1c/PeerJetty. License: MIT; attribution and artwork terms are in LICENSE-NOTES.md. Private vulnerability reporting is enabled. Current release preparation: 1.0.0/build29, Apple Silicon, macOS 15+, ad hoc signed and not notarized.

1. Review source, resources, reachable Git history and public documentation for credentials and personal data. Preserve compatibility identifiers and source attribution.
2. Run relevant isolated regression checks and record real-device coverage honestly in VALIDATION.md. Source and user-reported physical tests are distinct evidence.
3. Set version/build with `python3 Scripts/release.py set VERSION --build NUMBER`; commit verified changes.
4. Package a clean commit with `python3 Scripts/release.py package`. Never overwrite an existing archive. Verify signature, disk image, contents and embedded source metadata.
5. Tag the exact clean source commit embedded in the App. Push only the intended branch and release tag, never all private refs/backups.
6. Publish bilingual release notes with **only the DMG** as an uploaded asset. ZIP, checksums and build/signature records remain in ignored local archives. GitHub supplies source archives automatically.
7. Verify the remote tag, stable Latest release, asset list and downloaded DMG checksum. Updates remain manual; no automatic installation.

发布前完成隐私、回归和安装包核查；记录用户实机结果，不冒充开发者直接实测。版本标签必须指向 App 内记录的干净源码提交，后续文档提交不改变已发布标签或二进制。公开附件只放 DMG；已有归档及 Release 不覆盖。发布不代表自动安装到任何设备。

Historical provenance: [HISTORY.md](HISTORY.md), [CHANGELOG](../CHANGELOG.md), [validation](VALIDATION.md). Future CI, additional platforms, signing/notarization and artwork changes remain separately scoped work.
