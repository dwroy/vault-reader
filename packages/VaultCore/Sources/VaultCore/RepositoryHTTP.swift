import Foundation

/// Cancellation-aware gate. All API requests, including image loads, share four permits.
actor RequestGate {
    private var available = 4
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []
    func acquire() async throws {
        try Task.checkCancellation()
        if available > 0 { available -= 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in waiting.append((id, continuation)) }
        } onCancel: { Task { await self.cancel(id) } }
    }
    private func cancel(_ id: UUID) {
        if let i = waiting.firstIndex(where: { $0.0 == id }) { waiting.remove(at: i).1.resume(throwing: CancellationError()) }
    }
    func release() {
        if waiting.isEmpty { available += 1 } else { waiting.removeFirst().1.resume() }
    }
}


/// Only GET requests. Every provider shares four permits; credentials never follow redirects.
actor RepositoryHTTP {
    private static let gate = RequestGate()
    private let session: URLSession
    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30; config.httpMaximumConnectionsPerHost = 4
        self.session = session ?? URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
    }
    static func encode(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed; allowed.remove(charactersIn: "/?#%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)!
    }
    func get(_ url: URL, headers: [String: String], etag: String? = nil, raw: Bool = false, progress: (@Sendable (Double) -> Void)? = nil) async throws -> (Data, HTTPURLResponse) {
        try await Self.gate.acquire()
        do {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            let data: Data, response: URLResponse
            if raw {
                let delegate = DownloadProgress(report: progress ?? { _ in })
                let temporary: URL, result: URLResponse
                do { (temporary, result) = try await session.download(for: request, delegate: delegate) }
                catch { if delegate.exceeded { throw VaultError.tooLarge }; throw error }
                defer { try? FileManager.default.removeItem(at: temporary) }
                response = result
                let bytes = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard bytes <= BlobStore.maximumFileBytes else { throw VaultError.tooLarge }
                data = try Data(contentsOf: temporary)
            } else { (data, response) = try await session.data(for: request) }
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw VaultError.http(0) }
            switch response.statusCode {
            case 200, 304: break
            case 401: throw VaultError.unauthorized
            case 403, 429:
                if response.statusCode == 429 || response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" || response.value(forHTTPHeaderField: "ratelimit-remaining") == "0" || response.value(forHTTPHeaderField: "retry-after") != nil {
                    let reset = (response.value(forHTTPHeaderField: "x-ratelimit-reset") ?? response.value(forHTTPHeaderField: "ratelimit-reset")).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
                    throw VaultError.rateLimited(reset)
                }
                throw VaultError.forbidden
            case 404: throw VaultError.missing
            default: throw VaultError.http(response.statusCode)
            }
            await Self.gate.release(); return (data, response)
        } catch {
            await Self.gate.release()
            if Task.isCancelled { throw CancellationError() }
            if let network = error as? URLError { throw VaultError.network(network.code.rawValue) }
            throw error
        }
    }
}
private final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let report: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var exceededLimit = false
    var exceeded: Bool { lock.withLock { exceededLimit } }
    init(report: @escaping @Sendable (Double) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > BlobStore.maximumFileBytes || totalBytesExpectedToWrite > BlobStore.maximumFileBytes {
            lock.withLock { exceededLimit = true }; downloadTask.cancel(); return
        }
        if totalBytesExpectedToWrite > 0 { report(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) }
    }
}
