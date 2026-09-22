import VaultCore
import Foundation
import Observation

@MainActor @Observable
final class AppState {
    var config: RepositoryConfig
    var index = VaultIndex()
    var treeSHA = ""
    var notice: String?
    var isOffline = false
    var isRefreshing = false
    var needsSetup = true
    var showSettings = false
    var ready = false
    var demo = false
    var cacheBytes = 0
    var error: String?
    var tokenEnteredAt: Date? { UserDefaults.standard.object(forKey: "entered.\(config.identity)") as? Date }
    var lastValidatedAt: Date? { UserDefaults.standard.object(forKey: "validated.\(config.identity)") as? Date }
    @ObservationIgnored private(set) var blobs: BlobStore?
    @ObservationIgnored private var meta: MetaStore?
    @ObservationIgnored private var client: (any RepositorySource)?
    @ObservationIgnored private var snapshot: BranchSnapshot?
    @ObservationIgnored private var epoch = UUID()
    @ObservationIgnored var scrollPositions: [String: Double] = [:]

    init() {
        config = UserDefaults.standard.data(forKey: "repository").flatMap { try? JSONDecoder().decode(RepositoryConfig.self, from: $0) } ?? RepositoryConfig()
    }
    func start() async {
        guard !ready else { return }
        do {
            try await prepare()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--demo") {
                try await loadDemo(); ready = true; return
            }
            if ProcessInfo.processInfo.arguments.contains("--cached-vault") {
                needsSetup = false; demo = true; notice = "本机缓存验收 · 未连接 GitHub"; ready = true; return
            }
            if let token = ProcessInfo.processInfo.environment["VR_TOKEN"], !token.isEmpty, try Keychain.read(config.identity) == nil {
                try Keychain.save(token, account: config.identity)
                UserDefaults.standard.set(Date(), forKey: "entered.\(config.identity)")
            }
            #endif
            if let token = try Keychain.read(config.identity) {
                client = GitHubClient(config: config, token: token); needsSetup = false
            }
            ready = true
            if !needsSetup { await refresh() }
        } catch { self.error = error.localizedDescription; ready = true }
    }
    private func prepare() async throws {
        epoch = UUID(); isRefreshing = false
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VaultReader").appendingPathComponent(MetaStore.key(config.identity))
        blobs = try BlobStore(root: root.appendingPathComponent("blobs"))
        meta = try MetaStore(root: root.appendingPathComponent("meta").appendingPathComponent(MetaStore.key(config.branch)))
        snapshot = try await meta?.read("branch", as: BranchSnapshot.self)
        if let tree = try await meta?.read("tree", as: GitTree.self), !tree.truncated {
            index = VaultIndex(tree.tree); treeSHA = tree.sha
        } else { index = VaultIndex(); treeSHA = ""; snapshot = nil }
        await updateUsage()
    }
    func connect(_ candidate: RepositoryConfig, token: String) async throws {
        guard candidate.isValid else { throw VaultError.invalidConfiguration }
        let input = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential = input.isEmpty ? try Keychain.read(candidate.identity) : input
        guard let credential, !credential.isEmpty else { throw VaultError.noToken }
        let newClient = GitHubClient(config: candidate, token: credential)
        // Validate both repo access and complete tree before changing the active repository.
        guard let branch = try await newClient.branch(etag: nil) else { throw VaultError.missing }
        let tree = try await newClient.tree(sha: branch.tree)
        guard VaultIndex(tree.tree).files[candidate.home] != nil else { throw VaultError.missing }
        try Keychain.save(credential, account: candidate.identity)
        if !token.isEmpty { UserDefaults.standard.set(Date(), forKey: "entered.\(candidate.identity)") }
        UserDefaults.standard.set(Date(), forKey: "validated.\(candidate.identity)")
        UserDefaults.standard.set(try JSONEncoder().encode(candidate), forKey: "repository")
        config = candidate; client = newClient; demo = false
        try await prepare()
        try await meta?.write(tree, name: "tree"); try await meta?.write(branch, name: "branch")
        snapshot = branch; index = VaultIndex(tree.tree); treeSHA = tree.sha
        needsSetup = false; isOffline = false; notice = "已连接 · \(index.entries.count) 个文件"; error = nil
    }
    func refresh() async {
        guard let client, let meta, !isRefreshing, !demo else { return }
        let generation = epoch
        isRefreshing = true
        defer { if epoch == generation { isRefreshing = false } }
        do {
            if let branch = try await client.branch(etag: snapshot?.tree == treeSHA ? snapshot?.etag : nil) {
                if branch.tree != treeSHA {
                    let tree = try await client.tree(sha: branch.tree)
                    guard generation == epoch else { return }
                    let newIndex = VaultIndex(tree.tree), count = newIndex.changedCount(from: index)
                    try await meta.write(tree, name: "tree")
                    guard generation == epoch else { return }
                    index = newIndex; treeSHA = tree.sha
                    notice = "已更新 \(count) 个文件"
                } else { notice = "已是最新" }
                try await meta.write(branch, name: "branch")
                guard generation == epoch else { return }
                snapshot = branch
            }
            guard generation == epoch else { return }
            isOffline = false; error = nil
            UserDefaults.standard.set(Date(), forKey: "validated.\(config.identity)")
            await updateUsage()
        } catch is CancellationError {} catch {
            guard generation == epoch else { return }
            handle(error)
        }
    }
    func file(_ path: String) async throws -> Data {
        guard let entry = index.files[path], let blobs else { throw VaultError.missing }
        let generation = epoch
        if let data = try await blobs.data(for: entry.sha) { return data }
        guard let client else { throw VaultError.noToken }
        do {
            let data = try await client.blob(entry)
            try Task.checkCancellation()
            try await blobs.put(data, entry: entry)
            if generation == epoch { await updateUsage() }
            return data
        } catch {
            if generation == epoch && !(error is CancellationError) { handle(error) }
            throw error
        }
    }
    func preview(_ path: String) async throws -> URL {
        guard let entry = index.files[path], let blobs else { throw VaultError.missing }
        _ = try await file(path)
        return try await blobs.previewURL(sha: entry.sha, filename: entry.name)
    }
    func clearAttachments() async {
        do { try await blobs?.evict(to: 0); await updateUsage() } catch { self.error = error.localizedDescription }
    }
    func updateUsage() async {
        do {
            cacheBytes = try await blobs?.usage() ?? 0
            if cacheBytes > config.cacheLimitMB * 1024 * 1024 {
                try await blobs?.evict(to: config.cacheLimitMB * 1024 * 1024)
                cacheBytes = try await blobs?.usage() ?? 0
            }
        } catch { self.error = error.localizedDescription }
    }
    private func handle(_ error: Error) {
        if (error as? VaultError) == .unauthorized {
            do { try Keychain.delete(config.identity) } catch { self.error = error.localizedDescription; return }
            client = nil; needsSetup = true; showSettings = true
        }
        isOffline = true; notice = error.localizedDescription
    }
    #if DEBUG
    private func loadDemo() async throws {
        // Only synthetic examples are included in the binary; no private vault content.
        let samples: [(String, String)] = [
            ("README.md", "---\ntags: [阅读, 本地优先]\n---\n# 我的知识库\n把写过的日子，重新读一遍。\n\n## 从这里开始\n- [[生活/孩子索引|孩子的成长记录]]\n- [[阅读/阅读清单|书与思考]]\n- [[使用说明]]\n\n## 今日一页\n留一点时间，回到自己的文字。\n\n> 这是演示资料。连接你的 GitHub 仓库后，首页会显示你的 README。\n"),
            ("生活/孩子索引.md", "# 孩子的成长记录\n\n那些平常又值得记住的小事。\n\n- [[生活/公园的一天|公园的一天]]\n- [[日记|同目录的日记]]\n\n[[README|回到首页]]"),
            ("生活/公园的一天.md", "---\ntags:\n  - 生活/孩子\n---\n# 公园的一天\n\n今天一起去公园，发现了一片形状像小船的叶子。\n\n![[files/leaf.svg|300]]\n\n==把普通的一天，好好记下来。==\n\n## 回家的路\n- [x] 看树叶\n- [ ] 下次带上画笔\n\n[[孩子索引|继续阅读]] · [[#回家的路|回到这一段]]"),
            ("生活/日记.md", "# 生活里的日记\n同名链接优先落到当前目录。"),
            ("阅读/日记.md", "# 阅读日记\n另一篇同名笔记。"),
            ("阅读/阅读清单.md", "# 书与思考\n| 书目 | 状态 |\n| --- | --- |\n| 阅读中的一本书 | 慢慢读 |\n\n一句话，一点新的理解。[^1]\n\n[^1]: 阅读从来不着急。"),
            ("使用说明.md", "# 使用说明\n这是只读阅读器。\n\n支持 **Markdown**、[[README|双链]]、图片、表格与脚注。\n\n[[不存在的笔记]] 会显示为灰色死链。\n\n```swift\nlet reading = true\n```"),
            ("files/leaf.svg", "<svg xmlns='http://www.w3.org/2000/svg' width='600' height='420' viewBox='0 0 600 420'><rect width='600' height='420' rx='24' fill='#e8eee1'/><path d='M150 315Q140 105 460 80Q460 330 150 315Z' fill='#629367'/><path d='M128 345L410 128' stroke='#e8eee1' stroke-width='8'/><text x='38' y='385' font-family='sans-serif' font-size='20' fill='#41684c'>A little moment, kept.</text></svg>")
        ]
        var entries: [TreeEntry] = []
        for (path, value) in samples {
            let data = Data(value.utf8), entry = TreeEntry(path: path, sha: BlobStore.hash(Data(value.utf8)), size: Data(value.utf8).count, type: "blob")
            try await blobs?.put(data, entry: entry); entries.append(entry)
        }
        index = VaultIndex(entries); treeSHA = "demo"; needsSetup = false; demo = true
        notice = "演示资料 · 可在设置中连接仓库"
    }
    #endif
}
