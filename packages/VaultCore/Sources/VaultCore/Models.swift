import Foundation

public enum RepositoryProvider: String, Codable, CaseIterable, Sendable {
    case github, gitlab
    public var title: String { self == .github ? "GitHub" : "GitLab" }
}
public struct RepositoryConfig: Codable, Equatable, Sendable {
    public init() {}
    public var owner = "dwroy"
    public var repo = "notes"
    public var branch = "main"
    public var home = "README.md"
    public var cacheLimitMB = 500
    public var provider: RepositoryProvider = .github
    public var server = "https://gitlab.com"
    enum CodingKeys: String, CodingKey { case owner, repo, branch, home, cacheLimitMB, provider, server }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        owner = try c.decodeIfPresent(String.self, forKey: .owner) ?? "dwroy"
        repo = try c.decodeIfPresent(String.self, forKey: .repo) ?? "notes"
        branch = try c.decodeIfPresent(String.self, forKey: .branch) ?? "main"
        home = try c.decodeIfPresent(String.self, forKey: .home) ?? "README.md"
        cacheLimitMB = try c.decodeIfPresent(Int.self, forKey: .cacheLimitMB) ?? 500
        provider = try c.decodeIfPresent(RepositoryProvider.self, forKey: .provider) ?? .github
        server = try c.decodeIfPresent(String.self, forKey: .server) ?? "https://gitlab.com"
    }
    public var serverURL: URL? {
        guard var c = URLComponents(string: server), c.scheme?.lowercased() == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil else { return nil }
        c.scheme = "https"; c.host = host.lowercased()
        if c.port == 443 { c.port = nil }
        while c.path.hasSuffix("/") { c.path.removeLast() }
        return c.url
    }
    public var identity: String {
        let project = "\(owner.lowercased())/\(repo.lowercased())"
        // Preserve legacy GitHub Keychain/cache identities on migration.
        return provider == .github ? project : "gitlab:" + (serverURL?.absoluteString ?? server) + "/" + project
    }
    public var isValid: Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let namespace = provider == .gitlab ? owner.components(separatedBy: "/") : [owner]
        return (namespace + [repo]).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains) }
            && (provider == .github || serverURL != nil)
            && !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && VaultIndex.normalized(home) == home && !home.isEmpty
            && cacheLimitMB > 0 && cacheLimitMB <= 10000
    }
    public var webURL: URL {
        (provider == .github ? URL(string: "https://github.com")! : serverURL ?? URL(string: "https://gitlab.com")!)
            .appendingPathComponent(owner).appendingPathComponent(repo)
    }
    public func fileURL(path: String) -> URL {
        let base = provider == .github ? webURL : webURL.appendingPathComponent("-")
        return base.appendingPathComponent("blob").appendingPathComponent(branch).appendingPathComponent(path)
    }
    public func commitURL(sha: String) -> URL {
        (provider == .github ? webURL : webURL.appendingPathComponent("-")).appendingPathComponent("commit").appendingPathComponent(sha)
    }
}

public struct TreeEntry: Codable, Hashable, Sendable, Identifiable {
    public init(path: String, sha: String, size: Int?, type: String = "blob") {
        self.path = path; self.sha = sha; self.size = size; self.type = type
    }
    public let path: String
    public let sha: String
    public let size: Int?
    public let type: String
    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var ext: String { (path as NSString).pathExtension.lowercased() }
    public var isHTML: Bool { ["html", "htm"].contains(ext) }
    public var isMarkdown: Bool { ext == "md" }
    public var isPinned: Bool { isMarkdown || ext == "svg" }
}
public struct GitTree: Codable, Sendable {
    public init(sha: String, tree: [TreeEntry], truncated: Bool = false) { self.sha = sha; self.tree = tree; self.truncated = truncated }
    public let sha: String
    public let tree: [TreeEntry]
    public let truncated: Bool
}
struct BranchResponse: Codable, Sendable {
    struct Commit: Codable, Sendable {
        struct Detail: Codable, Sendable {
            struct Tree: Codable, Sendable { let sha: String }
            let tree: Tree
        }
        let sha: String
        let commit: Detail
    }
    let commit: Commit
}
public struct BranchSnapshot: Codable, Sendable {
    public let head: String
    public let tree: String
    public let etag: String?
    public let checkedAt: Date
}
public enum VaultError: LocalizedError, Equatable {
    case unauthorized, forbidden, missing, tooLarge, invalidTree, corruptBlob, invalidConfiguration, noToken
    case rateLimited(Date?), http(Int), network(Int)
    public var errorDescription: String? {
        switch self {
        case .unauthorized: CoreL10n.text("The token is invalid or expired. Enter it again in Settings.")
        case .forbidden: CoreL10n.text("Access denied. Check repository authorization and read-only token permissions.")
        case .missing: CoreL10n.text("File, repository or branch not found. Check the path and the token's repository access.")
        case .tooLarge: CoreL10n.text("The file exceeds 100 MB. Open it on the repository website.")
        case .invalidTree: CoreL10n.text("The repository returned an incomplete file tree. Your last complete cache was kept.")
        case .corruptBlob: CoreL10n.text("File verification failed. It was not cached. Please try again.")
        case .invalidConfiguration: CoreL10n.text("Enter a valid server URL, owner, repository and branch.")
        case .noToken: CoreL10n.text("Enter a read-only token in Settings first.")
        case .rateLimited(let date): date.map { CoreL10n.format("The service's request limit was reached. Try again after %1$@.", $0.formatted(date: .omitted, time: .shortened)) } ?? CoreL10n.text("The service is temporarily limiting requests. Please try again later.")
        case .network(let code):
            switch URLError.Code(rawValue: code) {
            case .notConnectedToInternet: CoreL10n.text("Your device is offline. Check Wi-Fi, mobile data and this app's network permissions. Cached files remain available.")
            case .timedOut: CoreL10n.text("The repository connection timed out. Check your network and retry. Cached files remain available.")
            case .cannotFindHost, .dnsLookupFailed: CoreL10n.text("The repository address could not be resolved. Check the hostname and network. Cached files remain available.")
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot: CoreL10n.text("The secure connection could not be verified. Check the server certificate, device date and network. Cached files remain available.")
            case .networkConnectionLost: CoreL10n.text("The repository connection was lost. Please retry. Cached files remain available.")
            default: CoreL10n.format("Could not connect to the repository (network error %1$ld). Check your network and retry. Cached files remain available.", code)
            }
        case .http(let code): CoreL10n.format("Repository request failed (%1$ld). Cached files remain available.", code)
        }
    }
}
