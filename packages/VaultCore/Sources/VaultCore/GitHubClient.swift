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

public actor GitHubClient: RepositorySource {
    private let config: RepositoryConfig
    private let token: String
    private let session: URLSession
    private let gate = RequestGate()
    public init(config: RepositoryConfig, token: String, session: URLSession? = nil) {
        self.config = config; self.token = token
        let settings = URLSessionConfiguration.ephemeral
        settings.urlCache = nil
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.timeoutIntervalForRequest = 30
        settings.httpMaximumConnectionsPerHost = 4
        self.session = session ?? URLSession(configuration: settings)
    }
    func request(_ components: [String], query: [URLQueryItem] = [], etag: String? = nil, raw: Bool = false) async throws -> (Data, HTTPURLResponse) {
        try await gate.acquire()
        do {
            try Task.checkCancellation()
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/?#%")
            var url = URLComponents(string: "https://api.github.com")!
            url.percentEncodedPath = "/" + (["repos", config.owner, config.repo] + components).map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "/")
            if !query.isEmpty { url.queryItems = query }
            var request = URLRequest(url: url.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(raw ? "application/vnd.github.raw+json" : "application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw VaultError.http(0) }
            switch response.statusCode {
            case 200, 304: break
            case 401: throw VaultError.unauthorized
            case 403, 429:
                if response.statusCode == 429 || response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" || response.value(forHTTPHeaderField: "retry-after") != nil {
                    let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
                    throw VaultError.rateLimited(reset)
                }
                throw VaultError.forbidden
            case 404: throw VaultError.missing
            default: throw VaultError.http(response.statusCode)
            }
            await gate.release()
            return (data, response)
        } catch { await gate.release(); throw error }
    }
    public func branch(etag: String?) async throws -> BranchSnapshot? {
        let (data, response) = try await request(["branches", config.branch], etag: etag)
        if response.statusCode == 304 { return nil }
        let result = try JSONDecoder().decode(BranchResponse.self, from: data)
        return BranchSnapshot(head: result.commit.sha, tree: result.commit.commit.tree.sha,
                              etag: response.value(forHTTPHeaderField: "ETag"), checkedAt: Date())
    }
    public func tree(sha: String) async throws -> GitTree {
        let (data, _) = try await request(["git", "trees", sha], query: [.init(name: "recursive", value: "1")])
        let tree = try JSONDecoder().decode(GitTree.self, from: data)
        guard !tree.truncated else { throw VaultError.invalidTree }
        return tree
    }
    public func blob(_ entry: TreeEntry) async throws -> Data {
        guard (entry.size ?? 0) <= BlobStore.maximumFileBytes else { throw VaultError.tooLarge }
        let (data, _) = try await request(["git", "blobs", entry.sha], raw: true)
        guard data.count <= BlobStore.maximumFileBytes else { throw VaultError.tooLarge }
        return data
    }
}
