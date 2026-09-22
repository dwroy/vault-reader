import Foundation

public actor GitHubClient: RepositorySource {
    private let config: RepositoryConfig
    private let token: String
    private let http: RepositoryHTTP
    public init(config: RepositoryConfig, token: String, session: URLSession? = nil) {
        self.config = config; self.token = token; http = RepositoryHTTP(session: session)
    }
    func request(_ components: [String], query: [URLQueryItem] = [], etag: String? = nil, raw: Bool = false, progress: (@Sendable (Double) -> Void)? = nil) async throws -> (Data, HTTPURLResponse) {
        var url = URLComponents(string: "https://api.github.com")!
        url.percentEncodedPath = "/" + (["repos", config.owner, config.repo] + components).map(RepositoryHTTP.encode).joined(separator: "/")
        if !query.isEmpty { url.queryItems = query }
        return try await http.get(url.url!, headers: ["Authorization": "Bearer " + token, "Accept": raw ? "application/vnd.github.raw+json" : "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"], etag: etag, raw: raw, progress: progress)
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
    public func blob(_ entry: TreeEntry, progress: (@Sendable (Double) -> Void)? = nil) async throws -> Data {
        guard (entry.size ?? 0) <= BlobStore.maximumFileBytes else { throw VaultError.tooLarge }
        let (data, _) = try await request(["git", "blobs", entry.sha], raw: true, progress: progress)
        guard data.count <= BlobStore.maximumFileBytes else { throw VaultError.tooLarge }
        return data
    }
    public func recent(etag: String?) async throws -> RecentSnapshot? {
        let (data, response) = try await request(["commits"], query: [.init(name: "sha", value: config.branch), .init(name: "per_page", value: "30")], etag: etag)
        if response.statusCode == 304 { return nil }
        let commits = try JSONDecoder().decode([CommitSummary].self, from: data)
        return RecentSnapshot(commits: commits, etag: response.value(forHTTPHeaderField: "ETag"))
    }
    public func commitFiles(sha: String) async throws -> CommitFiles {
        struct Page: Decodable { let files: [ChangedFile]? }
        var files: [ChangedFile] = []
        // GitHub caps this endpoint at 3,000 files. Never present a capped list as complete.
        for page in 1...30 {
            let (data, response) = try await request(["commits", sha], query: [.init(name: "per_page", value: "100"), .init(name: "page", value: String(page))])
            files += try JSONDecoder().decode(Page.self, from: data).files ?? []
            let more = response.value(forHTTPHeaderField: "Link")?.contains("rel=\"next\"") == true
            if !more { return CommitFiles(files: files, truncated: files.count >= 3000) }
        }
        return CommitFiles(files: files, truncated: true)
    }

}
