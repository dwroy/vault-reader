import VaultCore
import Foundation
import Observation
import OSLog

@MainActor @Observable
final class AppState {
    let launchedAt = ProcessInfo.processInfo.systemUptime
    var firstHomeRenderSeconds: Double?
    var config: RepositoryConfig
    var library: RepositoryLibrary
    var reading: ReadingStore
    var addingRepository = false
    var switchingRepository = false
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
    var recent: [CommitSummary] = []
    var recentError: String?
    var loadingRecent = false
    var prefetchCompleted = 0
    var prefetchTotal = 0
    var isPrefetching = false
    var prefetchError: String?
    @ObservationIgnored private(set) var searchIndex = SearchIndex()
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var storedLibrary = RepositoryLibrary()
    @ObservationIgnored private var recentSnapshot: RecentSnapshot?
    @ObservationIgnored private var recentRequest = UUID()
    var error: String?
    var tokenEnteredAt: Date? { UserDefaults.standard.object(forKey: "entered.\(config.identity)") as? Date }
    var lastValidatedAt: Date? { UserDefaults.standard.object(forKey: "validated.\(config.identity)") as? Date }
    @ObservationIgnored private(set) var blobs: BlobStore?
    @ObservationIgnored private var meta: MetaStore?
    @ObservationIgnored private var client: (any RepositorySource)?
    @ObservationIgnored private var snapshot: BranchSnapshot?
    @ObservationIgnored private var epoch = UUID()

    init() {
        let saved = UserDefaults.standard.data(forKey: "repository").flatMap { try? JSONDecoder().decode(RepositoryConfig.self, from: $0) }
        config = saved ?? RepositoryConfig()
        reading = ReadingStore(config: saved ?? RepositoryConfig())
        library = UserDefaults.standard.data(forKey: "repositoryLibrary").flatMap { try? JSONDecoder().decode(RepositoryLibrary.self, from: $0) } ?? RepositoryLibrary()
        if let saved { library.remember(saved) }
        storedLibrary = library
    }
    func start() async {
        guard !ready else { return }
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--demo") { config = RepositoryConfig(); config.owner = "example"; config.repo = "synthetic-vault"; config.branch = "main"; config.home = "README.md" }
            #endif
            try await prepare()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--demo") {
                if ProcessInfo.processInfo.arguments.contains("--reset-reading") { reading.clearDemoProgress() }
                try await loadDemo(); ready = true; return
            }
            if ProcessInfo.processInfo.arguments.contains("--cached-vault") {
                library.remember(config)
                needsSetup = false; demo = true; notice = "本机缓存验收 · 未连接服务器"; ready = true; return
            }
            if let token = ProcessInfo.processInfo.environment["VR_TOKEN"], !token.isEmpty, try Keychain.read(config.identity) == nil {
                try Keychain.save(token, account: config.identity)
                UserDefaults.standard.set(Date(), forKey: "entered.\(config.identity)")
            }
            #endif
            if let token = try Keychain.read(config.identity) {
                client = source(config, token: token); needsSetup = false
            }
            ready = true
            if !needsSetup { await refresh() }
        } catch { self.error = error.localizedDescription; ready = true }
    }
    private func prepare() async throws {
        reading.flush()
        if reading.key != config.storageKey { reading = ReadingStore(config: config) }
        stopPrefetch()
        epoch = UUID(); isRefreshing = false
        index = VaultIndex(); treeSHA = ""; blobs = nil; meta = nil; snapshot = nil
        searchIndex = SearchIndex(); prefetchCompleted = 0; prefetchTotal = 0
        recentRequest = UUID(); loadingRecent = false; recentError = nil; recent = []
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VaultReader").appendingPathComponent(MetaStore.key(config.identity))
        blobs = try BlobStore(root: root.appendingPathComponent("blobs"))
        meta = try MetaStore(root: root.appendingPathComponent("meta").appendingPathComponent(MetaStore.key(config.branch)))
        snapshot = try await meta?.read("branch", as: BranchSnapshot.self)
        if let tree = try await meta?.read("tree", as: GitTree.self), !tree.truncated {
            index = VaultIndex(tree.tree); treeSHA = tree.sha
        } else { index = VaultIndex(); treeSHA = ""; snapshot = nil }
        recentSnapshot = try await meta?.read("recent", as: RecentSnapshot.self)
        recent = recentSnapshot?.commits ?? []
        await updateUsage()
    }
    private func source(_ config: RepositoryConfig, token: String) -> any RepositorySource {
        switch config.provider {
        case .github: GitHubClient(config: config, token: token)
        case .gitlab: GitLabClient(config: config, token: token)
        }
    }
    func connect(_ candidate: RepositoryConfig, token: String) async throws {
        guard candidate.isValid else { throw VaultError.invalidConfiguration }
        let input = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential = input.isEmpty ? try Keychain.read(candidate.identity) : input
        guard let credential, !credential.isEmpty else { throw VaultError.noToken }
        let newClient = source(candidate, token: credential)
        // Validate both repo access and complete tree before changing the active repository.
        guard let branch = try await newClient.branch(etag: nil) else { throw VaultError.missing }
        let tree = try await newClient.tree(sha: branch.tree)
        try Keychain.save(credential, account: candidate.identity)
        if !token.isEmpty { UserDefaults.standard.set(Date(), forKey: "entered.\(candidate.identity)") }
        UserDefaults.standard.set(Date(), forKey: "validated.\(candidate.identity)")
        UserDefaults.standard.set(try JSONEncoder().encode(candidate), forKey: "repository")
        if demo { library = storedLibrary }
        library.remember(candidate)
        storedLibrary = library
        UserDefaults.standard.set(try JSONEncoder().encode(library), forKey: "repositoryLibrary")
        addingRepository = false
        config = candidate; client = newClient; demo = false
        try await prepare()
        try await meta?.write(tree, name: "tree"); try await meta?.write(branch, name: "branch")
        snapshot = branch; index = VaultIndex(tree.tree); treeSHA = tree.sha
        needsSetup = false; isOffline = false; notice = "已连接 · \(index.entries.count) 个文件"; error = nil
        startPrefetch()
    }
    func selectRepository(_ selected: RepositoryConfig) async {
        guard !switchingRepository, library.repositories.contains(where: { $0.storageKey == selected.storageKey }), selected.storageKey != config.storageKey else { return }
        switchingRepository = true
        defer { switchingRepository = false }
        stopPrefetch(); ready = false; client = nil
        config = selected; needsSetup = true; error = nil; notice = nil
        do {
            if !demo { UserDefaults.standard.set(try JSONEncoder().encode(selected), forKey: "repository") }
            try await prepare()
            if demo {
                needsSetup = false; isOffline = false; notice = "演示资料 · 可在设置中连接仓库"
            } else if let token = try Keychain.read(selected.identity) {
                client = source(selected, token: token); needsSetup = false
                isOffline = true; notice = "已打开本机缓存，正在检查更新…"
            } else { isOffline = true; notice = "此知识库未保存 Token，可阅读已有缓存。" }
            ready = true; startPrefetch()
            if client != nil { Task { await refresh() } }
        } catch { ready = true; self.error = error.localizedDescription; notice = error.localizedDescription }
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
                    stopPrefetch()
                    index = newIndex; treeSHA = tree.sha
                    notice = "已更新 \(count) 个文件"
                } else { notice = "已是最新" }
                try await meta.write(branch, name: "branch")
                guard generation == epoch else { return }
                snapshot = branch
            }
            guard generation == epoch else { return }
            isOffline = false; error = nil
            if !isPrefetching { startPrefetch() }
            UserDefaults.standard.set(Date(), forKey: "validated.\(config.identity)")
            await updateUsage()
        } catch is CancellationError {} catch {
            guard generation == epoch else { return }
            handle(error)
        }
    }
    func file(_ path: String, progress: (@Sendable (Double) -> Void)? = nil) async throws -> Data {
        guard let entry = index.files[path], let blobs else { throw VaultError.missing }
        let generation = epoch, requestClient = client
        if let data = try await blobs.data(for: entry.sha) { return data }
        guard let client = requestClient else { throw VaultError.noToken }
        do {
            let data = try await client.blob(entry, progress: progress)
            try Task.checkCancellation()
            try await blobs.put(data, entry: entry)
            if generation == epoch { await updateUsage(keeping: [entry.sha]) }
            return data
        } catch {
            if generation == epoch && !Task.isCancelled && !(error is CancellationError) { handle(error) }
            throw error
        }
    }
    func preview(_ path: String, progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        guard let entry = index.files[path], let blobs else { throw VaultError.missing }
        _ = try await file(path, progress: progress)
        try Task.checkCancellation()
        return try await blobs.previewURL(sha: entry.sha, filename: entry.name)
    }
    func clearAttachments() async {
        do { try await blobs?.evict(to: 0); await updateUsage() } catch { self.error = error.localizedDescription }
    }
    func updateUsage(keeping: Set<String> = []) async {
        do {
            cacheBytes = try await blobs?.usage() ?? 0
            if cacheBytes > config.cacheLimitMB * 1024 * 1024 {
                try await blobs?.evict(to: config.cacheLimitMB * 1024 * 1024, keeping: keeping, clearPreviews: false)
                cacheBytes = try await blobs?.usage() ?? 0
            }
        } catch { self.error = error.localizedDescription }
    }
    func recordHomeRendered(_ path: String) {
        guard path == config.home, firstHomeRenderSeconds == nil else { return }
        let seconds = ProcessInfo.processInfo.systemUptime - launchedAt
        firstHomeRenderSeconds = seconds
        Logger(subsystem: "com.dwroy.vaultreader", category: "performance").info("Home rendered in \(seconds, privacy: .public) seconds")
        startPrefetch()
    }
    func stopPrefetch() {
        prefetchTask?.cancel(); prefetchTask = nil; isPrefetching = false
    }
    func startPrefetch() {
        guard !isPrefetching else { return }
        let generation = epoch, entries = index.entries, engine = searchIndex
        let markdown = entries.filter(\.isMarkdown).sorted { a, b in
            if (a.path == config.home) != (b.path == config.home) { return a.path == config.home }
            return a.path < b.path
        }
        prefetchTotal = markdown.count; prefetchError = nil; isPrefetching = true
        prefetchTask = Task {
            defer { if generation == epoch && !Task.isCancelled { isPrefetching = false; prefetchTask = nil } }
            await engine.update(entries)
            guard generation == epoch, !Task.isCancelled else { return }
            var missing: [TreeEntry] = []
            // Hydrate every available document before a failed network request can interrupt completion.
            for entry in markdown {
                guard generation == epoch, !Task.isCancelled else { return }
                if let data = try? await blobs?.data(for: entry.sha), let text = String(data: data, encoding: .utf8) {
                    await engine.insert(text, for: entry)
                } else { missing.append(entry) }
            }
            guard generation == epoch, !Task.isCancelled else { return }
            prefetchCompleted = await engine.count
            for entry in missing {
                do {
                    try Task.checkCancellation()
                    let data = try await file(entry.path)
                    try Task.checkCancellation()
                    guard generation == epoch else { return }
                    guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
                    await engine.insert(text, for: entry)
                    prefetchCompleted = await engine.count
                } catch is CancellationError { return }
                catch { if generation == epoch && !Task.isCancelled { prefetchError = error.localizedDescription }; return }
            }
        }
    }
    func loadRecent() async {
        guard !loadingRecent, let client, let meta, !demo else { return }
        let generation = epoch, request = UUID()
        recentRequest = request; loadingRecent = true; recentError = nil
        defer { if request == recentRequest { loadingRecent = false } }
        do {
            if let result = try await client.recent(etag: recentSnapshot?.etag) {
                try Task.checkCancellation()
                guard generation == epoch else { return }
                try await meta.write(result, name: "recent")
                guard generation == epoch else { return }
                recentSnapshot = result; recent = result.commits
            }
        } catch is CancellationError {} catch {
            guard generation == epoch else { return }
            recentError = error.localizedDescription; handle(error)
        }
    }
    func changedFiles(_ sha: String) async throws -> CommitFiles {
        guard let meta else { throw VaultError.missing }
        let key = "commit-" + MetaStore.key(sha), generation = epoch, requestClient = client
        if let cached = try await meta.read(key, as: CommitFiles.self) {
            guard generation == epoch else { throw CancellationError() }; return cached
        }
        guard let client = requestClient else { throw VaultError.noToken }
        do {
            let files = try await client.commitFiles(sha: sha)
            try Task.checkCancellation()
            guard generation == epoch else { throw CancellationError() }
            try await meta.write(files, name: key)
            return files
        } catch {
            if generation == epoch && !Task.isCancelled && !(error is CancellationError) { handle(error) }
            throw error
        }
    }
    private func handle(_ error: Error) {
        if (error as? VaultError) == .unauthorized {
            do { try Keychain.delete(config.identity) } catch { self.error = error.localizedDescription; return }
            client = nil; needsSetup = true; showSettings = true
        }
        isOffline = true; notice = error.localizedDescription
    }
    #if DEBUG
    func startDemoForTesting() async throws {
        config = RepositoryConfig(); config.owner = "example"; config.repo = "synthetic-vault"; config.branch = "main"; config.home = "README.md"
        try await prepare(); try await loadDemo(); ready = true; startPrefetch()
    }
    private func loadDemo() async throws {
        // Only synthetic examples are included in the binary; no private vault content.
        var samples: [(String, String)] = [
            ("README.md", "---\ntags: [阅读, 本地优先]\n---\n# 我的知识库\n把写过的日子，重新读一遍。\n\n## 从这里开始\n- [[生活/孩子索引|孩子的成长记录]]\n- [[阅读/阅读清单|书与思考]]\n- [[使用说明]]\n\n## 今日一页\n留一点时间，回到自己的文字。\n\n> 这是演示资料。连接你的 GitHub 仓库后，首页会显示你的 README。\n"),
            ("生活/孩子索引.md", "# 孩子的成长记录\n\n那些平常又值得记住的小事。\n\n- [[生活/公园的一天|公园的一天]]\n- [[日记|同目录的日记]]\n\n[[README|回到首页]]"),
            ("生活/公园的一天.md", "---\ntags:\n  - 生活/孩子\n---\n# 公园的一天\n\n今天一起去公园，发现了一片形状像小船的叶子。\n\n![[files/leaf.svg|300]]\n\n==把普通的一天，好好记下来。==\n\n## 回家的路\n- [x] 看树叶\n- [ ] 下次带上画笔\n\n[[孩子索引|继续阅读]] · [[#回家的路|回到这一段]]"),
            ("生活/日记.md", "# 生活里的日记\n同名链接优先落到当前目录。"),
            ("阅读/日记.md", "# 阅读日记\n另一篇同名笔记。"),
            ("阅读/阅读清单.md", "# 书与思考\n| 书目 | 状态 |\n| --- | --- |\n| 阅读中的一本书 | 慢慢读 |\n\n一句话，一点新的理解。[^1]\n\n[^1]: 阅读从来不着急。"),
            ("使用说明.md", "# 使用说明\n这是只读阅读器。\n\n支持 **Markdown**、[[README|双链]]、图片、表格与脚注。\n\n[[不存在的笔记]] 会显示为灰色死链。\n\n```swift\nlet reading = true\n```"),
            ("files/leaf.svg", "<svg xmlns='http://www.w3.org/2000/svg' width='600' height='420' viewBox='0 0 600 420'><rect width='600' height='420' rx='24' fill='#e8eee1'/><path d='M150 315Q140 105 460 80Q460 330 150 315Z' fill='#629367'/><path d='M128 345L410 128' stroke='#e8eee1' stroke-width='8'/><text x='38' y='385' font-family='sans-serif' font-size='20' fill='#41684c'>A little moment, kept.</text></svg>")
        ]
        samples += [
            ("阅读器.html", Self.demoHTML), ("独立阅读器.html", Self.demoHTML),
            ("长文.md", "# 长文\n\n" + (1...80).map { "## 第 \($0) 段\n\n正文检索词：银杏。慢慢读，记得回来的位置。\n\n[[长文|继续长文]]\n\n" }.joined())
        ]
        samples += BookDemoFixtures.markdown
        for n in 1...12 {
            samples.append(("深读/第 \(n) 页.md", "# 第 \(n) 页\n\n" + String(repeating: "保留每次阅读的位置。\n\n", count: 100)))
        }
        var entries: [TreeEntry] = []
        for (path, value) in samples {
            let data = Data(value.utf8), entry = TreeEntry(path: path, sha: BlobStore.hash(Data(value.utf8)), size: Data(value.utf8).count, type: "blob")
            try await blobs?.put(data, entry: entry); entries.append(entry)
        }
        let pdf = BookDemoFixtures.pdf
        let pdfEntry = TreeEntry(path: "files/夜航手记.pdf", sha: BlobStore.hash(pdf), size: pdf.count)
        try await blobs?.put(pdf, entry: pdfEntry); entries.append(pdfEntry)
        index = VaultIndex(entries); treeSHA = "demo"; needsSetup = false; demo = true
        try await meta?.write(GitTree(sha: treeSHA, tree: entries), name: "tree")
        var second = config; second.repo = "synthetic-other"
        library = RepositoryLibrary([config, second])
        let secondRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VaultReader").appendingPathComponent(MetaStore.key(second.identity))
        let secondBlobs = try BlobStore(root: secondRoot.appendingPathComponent("blobs"))
        let secondMeta = try MetaStore(root: secondRoot.appendingPathComponent("meta").appendingPathComponent(MetaStore.key(second.branch)))
        let secondText = Data("# 第二个知识库\n\n这是另一份独立缓存，不包含第一库的银杏笔记。".utf8)
        let secondEntry = TreeEntry(path: "README.md", sha: BlobStore.hash(secondText), size: secondText.count)
        try await secondBlobs.put(secondText, entry: secondEntry)
        try await secondMeta.write(GitTree(sha: "second-demo", tree: [secondEntry]), name: "tree")
        notice = "演示资料 · 可在设置中连接仓库"
        let demoCommits = (1...30).map { n in
            ["sha": String(format: "%040x", n), "commit": ["message": "记录第 \(n) 天\n\n补上公园散步的片段。", "committer": ["name": "Demo", "date": "2026-09-22T00:00:00Z"]]] as [String: Any]
        }
        recent = try JSONDecoder().decode([CommitSummary].self, from: JSONSerialization.data(withJSONObject: demoCommits))
        try await meta?.write(RecentSnapshot(commits: recent, etag: nil), name: "recent")
        let detail = try JSONDecoder().decode(CommitFiles.self, from: Data(#"{"files":[{"filename":"生活/公园的一天.md","status":"modified"},{"filename":"旧日记.md","status":"removed"}],"truncated":false}"#.utf8))
        for commit in recent { try await meta?.write(detail, name: "commit-" + MetaStore.key(commit.sha)) }
    }
    static let demoHTML = """
    <!doctype html><html><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font:22px -apple-system;padding:24px;color-scheme:light dark}button{font:inherit;padding:15px;margin:10px}</style><h1>独立阅读器</h1><p id="page"></p><button onclick="n++;save()">Next page</button><button onclick="n=1;save()">Reset</button><script>let n=Number(localStorage.getItem('page')||1);function save(){localStorage.setItem('page',n);document.getElementById('page').textContent='Page '+n}save()</script></html>
    """
    #endif
}
