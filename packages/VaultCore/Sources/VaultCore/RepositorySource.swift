import Foundation

/// Native data boundary. UI and WebKit do not depend on HTTP request construction.
public protocol RepositorySource: Sendable {
    func branch(etag: String?) async throws -> BranchSnapshot?
    func tree(sha: String) async throws -> GitTree
    func blob(_ entry: TreeEntry, progress: (@Sendable (Double) -> Void)?) async throws -> Data
    func recent(etag: String?) async throws -> RecentSnapshot?
    func commitFiles(sha: String) async throws -> CommitFiles
}

public extension RepositorySource {
    func blob(_ entry: TreeEntry) async throws -> Data { try await blob(entry, progress: nil) }
}
