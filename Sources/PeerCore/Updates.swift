import Foundation

/// Release tags and product versions use three nonnegative numeric components.
public struct ProductVersion: Comparable, Equatable {
    public let components: [Int]
    public init?(_ value: String) {
        let digits = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              parts.allSatisfy({ $0.count == 1 || $0.first != "0" }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }; components = numbers
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
    public var description: String { components.map(String.init).joined(separator: ".") }
}

public struct PublicRelease {
    public let version: ProductVersion
    public let notes: String
    public let page: URL
    public let hasInstaller: Bool
}

public enum UpdateResponse {
    public static let endpoint = URL(string: "https://api.github.com/repos/TimeLyr1c/PeerJetty/releases/latest")!
    public static let releasesPage = URL(string: "https://github.com/TimeLyr1c/PeerJetty/releases")!
    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let body: String?
        let html_url: String
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let state: String
        let browser_download_url: String
    }
    public static func parse(data: Data, status: Int) throws -> PublicRelease? {
        if status == 404 { return nil }
        if status == 403 || status == 429 { throw PeerError.localized("updates.rate_limit", []) }
        guard status == 200 else { throw PeerError.localized("updates.server_error", [String(status)]) }
        guard data.count <= 1_048_576, let release = try? JSONDecoder().decode(Release.self, from: data),
              !release.draft, !release.prerelease, let version = ProductVersion(release.tag_name),
              let page = URL(string: release.html_url), safeURL(page),
              page.path == "/TimeLyr1c/PeerJetty/releases/tag/" + release.tag_name else {
            throw PeerError.localized("updates.invalid_release", [])
        }
        let installer = release.assets.contains { asset in
            guard asset.state == "uploaded", asset.name.hasPrefix("PeerJetty-" + version.description + "-"),
                  asset.name.hasSuffix("-arm64.dmg"), let url = URL(string: asset.browser_download_url), safeURL(url) else { return false }
            return url.path == "/TimeLyr1c/PeerJetty/releases/download/" + release.tag_name + "/" + asset.name
        }
        return PublicRelease(version: version, notes: String((release.body ?? "").prefix(20_000)), page: page, hasInstaller: installer)
    }
    private static func safeURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil && url.port == nil && url.query == nil && url.fragment == nil
    }
}

/// Manual, unauthenticated check. No app credentials, transfer names or config
/// enter the request; URLSession's ephemeral store avoids persistent cookies.
public final class UpdateClient {
    private let session: URLSession
    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }
    deinit { session.invalidateAndCancel() }
    @discardableResult
    public func check(completion: @escaping (Result<PublicRelease?, Error>) -> Void) -> URLSessionDataTask {
        var request = URLRequest(url: UpdateResponse.endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("PeerJetty-Update-Check", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request) { data, response, error in
            let result: Result<PublicRelease?, Error>
            if let error { result = .failure(error) }
            else if let response = response as? HTTPURLResponse {
                result = Result { try UpdateResponse.parse(data: data ?? Data(), status: response.statusCode) }
            } else { result = .failure(PeerError.localized("updates.invalid_release", [])) }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume(); return task
    }
}
