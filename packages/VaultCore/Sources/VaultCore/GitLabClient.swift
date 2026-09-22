import Foundation

public actor GitLabClient: RepositorySource {
    private let config: RepositoryConfig
    private let token: String
    private let http: RepositoryHTTP
    public init(config: RepositoryConfig, token: String, session: URLSession? = nil) {
        self.config = config; self.token = token; http = RepositoryHTTP(session: session)
    }
    private func request(_ path: [String], query: [URLQueryItem] = [], etag: String? = nil, raw: Bool = false, progress: (@Sendable (Double) -> Void)? = nil) async throws -> (Data, HTTPURLResponse) {
        guard config.isValid, let base = config.serverURL, var url = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw VaultError.invalidConfiguration }
        url.percentEncodedPath += "/api/v4/projects/" + RepositoryHTTP.encode(config.owner + "/" + config.repo) + "/repository/" + path.map(RepositoryHTTP.encode).joined(separator: "/")
        if !query.isEmpty { url.queryItems = query }
        var headers = ["Accept": raw ? "application/octet-stream" : "application/json"]
        if !token.isEmpty { headers["PRIVATE-TOKEN"] = token }
        return try await http.get(url.url!, headers: headers, etag: etag, raw: raw, progress: progress)
    }
    private struct Branch: Decodable { struct Commit: Decodable { let id: String }; let commit: Commit }
    public func branch(etag: String?) async throws -> BranchSnapshot? {
        let (data, response) = try await request(["branches", config.branch], etag: etag)
        if response.statusCode == 304 { return nil }
        let head = try JSONDecoder().decode(Branch.self, from: data).commit.id
        // GitLab's branch endpoint exposes a commit SHA; use it as the immutable tree ref.
        return BranchSnapshot(head: head, tree: head, etag: response.value(forHTTPHeaderField: "ETag"), checkedAt: Date())
    }
    private struct Entry: Decodable { let id: String; let path: String; let type: String }
    private func hasNext(_ response: HTTPURLResponse, count: Int) -> Bool {
        if let page = response.value(forHTTPHeaderField: "x-next-page") { return !page.isEmpty }
        if let link = response.value(forHTTPHeaderField: "Link") { return link.contains("rel=\"next\"") }
        return count == 100
    }
    public func tree(sha: String) async throws -> GitTree {
        var entries: [TreeEntry] = []
        for page in 1...1000 {
            let (data, response) = try await request(["tree"], query: [.init(name: "ref", value: sha), .init(name: "recursive", value: "true"), .init(name: "per_page", value: "100"), .init(name: "page", value: String(page))])
            let next = try JSONDecoder().decode([Entry].self, from: data)
            entries += next.map { TreeEntry(path: $0.path, sha: $0.id, size: nil, type: $0.type) }
            if !hasNext(response, count: next.count) { return GitTree(sha: sha, tree: entries) }
        }
        throw VaultError.invalidTree // Never replace a complete cache with a capped tree.
    }
    public func blob(_ entry: TreeEntry, progress: (@Sendable (Double) -> Void)? = nil) async throws -> Data {
        guard (entry.size ?? 0) <= BlobStore.maximumFileBytes else { throw VaultError.tooLarge }
        return try await request(["blobs", entry.sha, "raw"], raw: true, progress: progress).0
    }
    private struct Commit: Decodable {
        let id: String; let message: String; let author_name: String?; let committed_date: String?
        var summary: CommitSummary { CommitSummary(sha: id, commit: .init(message: message, author: .init(name: author_name, date: committed_date), committer: nil)) }
    }
    public func recent(etag: String?) async throws -> RecentSnapshot? {
        let (data, response) = try await request(["commits"], query: [.init(name: "ref_name", value: config.branch), .init(name: "per_page", value: "30")], etag: etag)
        if response.statusCode == 304 { return nil }
        return RecentSnapshot(commits: try JSONDecoder().decode([Commit].self, from: data).map(\.summary), etag: response.value(forHTTPHeaderField: "ETag"))
    }
    private struct Diff: Decodable {
        let old_path: String; let new_path: String
        let new_file: Bool; let renamed_file: Bool; let deleted_file: Bool
        let too_large: Bool?; let collapsed: Bool?
        var file: ChangedFile { ChangedFile(filename: deleted_file ? old_path : new_path, status: deleted_file ? "removed" : renamed_file ? "renamed" : new_file ? "added" : "modified", previous_filename: renamed_file ? old_path : nil) }
    }
    public func commitFiles(sha: String) async throws -> CommitFiles {
        var files: [ChangedFile] = [], truncated = false
        for page in 1...30 {
            let (data, response) = try await request(["commits", sha, "diff"], query: [.init(name: "per_page", value: "100"), .init(name: "page", value: String(page))])
            let next = try JSONDecoder().decode([Diff].self, from: data)
            files += next.map(\.file); truncated = truncated || next.contains { $0.too_large == true || $0.collapsed == true }
            if !hasNext(response, count: next.count) { return CommitFiles(files: files, truncated: truncated, limitsMayApply: true) }
        }
        return CommitFiles(files: files, truncated: true, limitsMayApply: true)
    }
}
