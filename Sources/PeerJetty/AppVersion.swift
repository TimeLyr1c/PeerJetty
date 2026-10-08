import Foundation
import PeerCore

enum AppVersion {
    static var summary: String {
        summary(info:Bundle.main.infoDictionary ?? [:])
    }
    static func summary(info:[String:Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? L10n.text("appversion.unknown")
        return L10n.text("appversion.version", String(describing: version))
    }

    static var diagnosticSummary: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return L10n.text("appversion.version_build", info["CFBundleShortVersionString"] as? String ?? L10n.text("appversion.unknown"), info["CFBundleVersion"] as? String ?? L10n.text("appversion.unknown"))
    }
    static var details: String {
        guard let url = Bundle.main.url(forResource: "build-info", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return diagnosticSummary
        }
        let commit = info["git_commit"] as? String ?? L10n.text("appversion.unknown")
        let configuration = info["configuration"] as? String ?? L10n.text("appversion.unknown")
        let changed = info["dirty"] as? Bool == true ? L10n.text("appversion.uncommitted_changes") : ""
        return L10n.text("version.source", diagnosticSummary, String(commit.prefix(7)), configuration, changed.isEmpty ? "" : L10n.text("version.changed_suffix", changed))
    }
}
