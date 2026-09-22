import Foundation

/// Saved connection profiles contain no credentials. Branches share a repository's credential,
/// but keep their own tree metadata and reading origins.
public struct RepositoryLibrary: Codable, Sendable {
    public private(set) var repositories: [RepositoryConfig]
    public init(_ repositories: [RepositoryConfig] = []) {
        self.repositories = []
        for config in repositories where config.isValid { remember(config) }
    }
    public mutating func remember(_ config: RepositoryConfig) {
        guard config.isValid else { return }
        if let i = repositories.firstIndex(where: { $0.storageKey == config.storageKey }) { repositories[i] = config }
        else { repositories.append(config) }
    }
}
public extension RepositoryConfig {
    var storageKey: String { identity + "\0" + branch }
    var displayName: String { provider == .github ? "\(owner)/\(repo) · \(branch)" : "GitLab · \(serverURL?.host ?? server) / \(owner)/\(repo) · \(branch)" }
}
