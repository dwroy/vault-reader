import Foundation

/// Native data boundary. UI and WebKit do not depend on HTTP request construction.
public protocol RepositorySource: Sendable {
    func branch(etag: String?) async throws -> BranchSnapshot?
    func tree(sha: String) async throws -> GitTree
    func blob(_ entry: TreeEntry, progress: (@Sendable (Double) -> Void)?) async throws -> Data
    func blob(_ entry: TreeEntry, maximumBytes: Int, progress: (@Sendable (Double) -> Void)?) async throws -> Data
    func recent(etag: String?) async throws -> RecentSnapshot?
    func commitFiles(sha: String) async throws -> CommitFiles
}

public extension RepositorySource {
    /// Adapters override this to bound downloads before buffering; the fallback supports synthetic sources.
    func blob(_ entry: TreeEntry, maximumBytes: Int, progress: (@Sendable (Double) -> Void)? = nil) async throws -> Data {
        guard (entry.size ?? 0) <= maximumBytes else { throw VaultError.tooLarge }
        let data = try await blob(entry, progress: progress)
        guard data.count <= maximumBytes else { throw VaultError.tooLarge }
        return data
    }
    func blob(_ entry: TreeEntry) async throws -> Data { try await blob(entry, progress: nil) }
}
