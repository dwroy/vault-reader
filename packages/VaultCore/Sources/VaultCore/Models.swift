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
        case .unauthorized: "Token 无效或已过期，请在设置中重新录入。"
        case .forbidden: "仓库服务拒绝访问，请检查仓库授权及只读 Token 权限。"
        case .missing: "未找到文件、仓库或分支。请检查路径及 Token 的仓库授权。"
        case .tooLarge: "文件超过 100 MB，请在仓库网页打开。"
        case .invalidTree: "仓库目录未完整返回，已保留上次完整缓存。"
        case .corruptBlob: "文件校验失败，未写入缓存。请重试。"
        case .invalidConfiguration: "请填写有效的 owner、repo、branch 和仓库内首页路径。"
        case .noToken: "请先在设置中录入只读 Token。"
        case .rateLimited(let date): date.map { "仓库服务请求额度已用完，\($0.formatted(date: .omitted, time: .shortened)) 后可重试。" } ?? "仓库服务暂时限制请求，请稍后重试。"
        case .network(let code):
            switch URLError.Code(rawValue: code) {
            case .notConnectedToInternet: "系统报告设备离线。请检查 Wi-Fi、蜂窝数据及本 App 的联网权限。已缓存内容仍可阅读。"
            case .timedOut: "连接仓库服务超时，请检查网络后重试。已缓存内容仍可阅读。"
            case .cannotFindHost, .dnsLookupFailed: "无法解析仓库服务地址，请检查域名与网络。已缓存内容仍可阅读。"
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot: "无法验证仓库服务的安全连接，请检查服务证书、设备日期和网络。已缓存内容仍可阅读。"
            case .networkConnectionLost: "与仓库服务的网络连接中断，请重试。已缓存内容仍可阅读。"
            default: "无法连接仓库服务（网络错误 \(code)）。请检查网络后重试。已缓存内容仍可阅读。"
            }
        case .http(let code): "仓库服务请求失败（\(code)），缓存仍可阅读。"
        }
    }
}
