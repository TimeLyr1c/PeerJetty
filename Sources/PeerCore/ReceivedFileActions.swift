import Foundation

/// Called only with roots returned by a successful receiver commit.
/// Keeping the open operation injectable prevents tests from launching real apps.
public enum ReceivedFileActions {
    public static func openCommitted(_ urls: [URL], enabled: Bool, open: (URL) -> Bool) -> [URL] {
        guard enabled else { return [] }
        return urls.filter { !open($0) }
    }
}
