import Foundation

public struct RepositoryConfig: Codable, Equatable, Sendable {
    public init() {}
    public var owner = "dwroy"
    public var repo = "notes"
    public var branch = "main"
    public var home = "README.md"
    public var cacheLimitMB = 500
    public var identity: String { "\(owner.lowercased())/\(repo.lowercased())" }
    public var isValid: Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return [owner, repo].allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }
            && !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && VaultIndex.normalized(home) == home && !home.isEmpty
    }
    public func githubURL(path: String) -> URL {
        URL(string: "https://github.com")!.appendingPathComponent(owner).appendingPathComponent(repo)
            .appendingPathComponent("blob").appendingPathComponent(branch).appendingPathComponent(path)
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
    public var isMarkdown: Bool { ext == "md" }
    public var isPinned: Bool { isMarkdown || ext == "svg" }
}
public struct GitTree: Codable, Sendable {
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
    case rateLimited(Date?), http(Int)
    public var errorDescription: String? {
        switch self {
        case .unauthorized: "Token 无效或已过期，请在设置中重新录入。"
        case .forbidden: "GitHub 拒绝访问，请检查仓库授权及 Contents 只读权限。"
        case .missing: "未找到文件、仓库或分支。请检查路径及 Token 的仓库授权。"
        case .tooLarge: "文件超过 100 MB，请在 GitHub 打开。"
        case .invalidTree: "仓库目录未完整返回，已保留上次完整缓存。"
        case .corruptBlob: "文件校验失败，未写入缓存。请重试。"
        case .invalidConfiguration: "请填写有效的 owner、repo、branch 和仓库内首页路径。"
        case .noToken: "请先在设置中录入只读 Token。"
        case .rateLimited(let date): date.map { "GitHub 请求额度已用完，\($0.formatted(date: .omitted, time: .shortened)) 后可重试。" } ?? "GitHub 暂时限制请求，请稍后重试。"
        case .http(let code): "GitHub 请求失败（\(code)），缓存仍可阅读。"
        }
    }
}
