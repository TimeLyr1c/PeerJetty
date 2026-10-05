import Foundation

enum AppVersion {
    static var summary: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "未知"
        let build = info["CFBundleVersion"] as? String ?? "未知"
        return "版本 \(version) · 构建 \(build)"
    }

    static var details: String {
        guard let url = Bundle.main.url(forResource: "build-info", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return summary
        }
        let commit = info["git_commit"] as? String ?? "未知"
        let configuration = info["configuration"] as? String ?? "未知"
        let changed = info["dirty"] as? Bool == true ? " · 含未提交修改" : ""
        return "\(summary)\n源码 \(commit.prefix(7)) · \(configuration)\(changed)"
    }
}
