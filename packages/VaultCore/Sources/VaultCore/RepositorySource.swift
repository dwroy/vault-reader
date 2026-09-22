import Foundation

/// Native data boundary. UI and WebKit do not depend on HTTP request construction.
public protocol RepositorySource: Sendable {
    func branch(etag: String?) async throws -> BranchSnapshot?
    func tree(sha: String) async throws -> GitTree
    func blob(_ entry: TreeEntry) async throws -> Data
}
