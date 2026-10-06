import Foundation

// Counts files, not receivers. Callbacks can arrive before the accepting API returns.
public final class PromiseTracker {
    private let lock = NSLock()
    private var expected: [Int?]
    private var observed: [Int]
    private var urls: [URL] = []
    private var failure: Error?
    private var done = false
    private var cancelled = false
    private let completion: (Result<[URL], Error>) -> Void
    public init(receivers: Int, completion: @escaping (Result<[URL], Error>) -> Void) {
        expected = Array(repeating: nil, count: receivers); observed = Array(repeating: 0, count: receivers); self.completion = completion
    }
    public func expect(receiver: Int, count: Int) {
        lock.lock(); guard !done else { lock.unlock(); return }
        expected[receiver] = max(1, count); let result = finishIfReady(); lock.unlock()
        if let result { completion(result) }
    }
    public func record(receiver: Int, url: URL, error: Error?) {
        lock.lock(); guard !done else { lock.unlock(); return }
        observed[receiver] += 1
        if let error { if failure == nil { failure = error } }
        else { urls.append(url) }
        let result = finishIfReady(); lock.unlock()
        if let result { completion(result) }
    }
    public func cancel() {
        lock.lock(); guard !done else { lock.unlock(); return }; done = true; cancelled = true; lock.unlock()
        completion(.failure(PeerError.localized("promisetracker.reading_dropped_files_timed_out_or_was_cancelled", [])))
    }
    public var wasCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    private func finishIfReady() -> Result<[URL], Error>? {
        guard expected.indices.allSatisfy({ expected[$0] != nil && observed[$0] >= expected[$0]! }) else { return nil }
        done = true
        if let failure { return .failure(failure) }
        return urls.isEmpty ? .failure(PeerError.localized("promisetracker.the_source_app_did_not_provide_a_file", [])) : .success(urls)
    }
}
