import SwiftUI
import VaultCore

func readingRoute(_ path: String, index: VaultIndex) -> ReaderRoute {
    index.files[path]?.isMarkdown == true ? .note(NoteRoute(path: path, reading: true)) : .file(path)
}

struct ReadingProjectsView: View {
    let state: AppState
    let openProject: (RepositoryConfig, String?) -> Void
    var body: some View {
        List {
            if let record = state.reading.history.recentMarkdown(limit: 1, where: { state.index.files[$0.path] != nil && state.fileDisplay.includes($0.path) }).first {
                Section("继续阅读") {
                    Button { openProject(state.config, record.path) } label: {
                        ReadingRow(title: record.title, format: "\(state.config.owner)/\(state.config.repo)", record: record)
                    }.accessibilityIdentifier("continueReading")
                }
            }
            Section("项目") {
                ForEach(state.library.repositories, id: \.storageKey) { config in
                    Button { openProject(config, nil) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "books.vertical").font(.title2).foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(config.owner)/\(config.repo)").foregroundStyle(.primary)
                                Text("\(config.provider.title) · \(config.branch)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }.padding(.vertical, 6)
                    }.disabled(state.switchingRepository).accessibilityIdentifier("reading-project-" + config.owner + "/" + config.repo + "-" + config.branch)
                }
            }
        }
        .navigationTitle("阅读").navigationBarTitleDisplayMode(.inline)
    }
}

struct ReadingLibraryView: View {
    let state: AppState
    @State private var linkedPDFs = Set<String>()
    /// Books declared by reading-list Markdown; nil until the lists have been read once.
    @State private var listed: [ListedBook]?
    @State private var query = ""
    @State private var indexError: String?
    private var catalog: BookCatalog { BookCatalog(index: VaultIndex(state.visibleEntries), linkedPDFs: linkedPDFs) }
    private var recent: [ReadingRecord] {
        state.reading.history.recentMarkdown(limit: 3) { state.index.files[$0.path] != nil && state.fileDisplay.includes($0.path) && matches($0.title) }
    }
    var body: some View {
        let catalog = catalog, recent = recent, books = (listed ?? []).filter(matches)
        List {
            Section {
                Text("\(state.config.owner)/\(state.config.repo)").font(.subheadline).foregroundStyle(.secondary)
            }
            if !recent.isEmpty {
                Section("最近阅读") {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { offset, record in
                        NavigationLink(value: readingRoute(record.path, index: state.index)) {
                            ReadingRow(title: record.title, format: "Markdown", record: record)
                        }.accessibilityIdentifier(offset == 0 ? "continueBook" : "recentBook")
                    }
                }
            }
            if let error = indexError {
                Section { Text("部分书单暂未载入：\(error)").font(.caption).foregroundStyle(.secondary) }
            }
            if listed == nil && !catalog.indexes.isEmpty {
                Section { HStack(spacing: 10) { ProgressView(); Text("正在读取书单…").foregroundStyle(.secondary) } }
            } else if let listed, !listed.isEmpty {
                ForEach(BookList.groups(books)) { group in
                    Section(group.title ?? "书籍") {
                        ForEach(group.books) { book in
                            NavigationLink(value: ReaderRoute.book(book)) { BookRow(book: book, latest: latest(book)) }
                                .accessibilityIdentifier("reading-book:" + book.title)
                        }
                    }
                }
                let listedPaths = Set(listed.flatMap(\.paths))
                let unlisted = catalog.books.flatMap(\.editions).filter { !listedPaths.contains($0.path) && matches($0.name) }
                if !unlisted.isEmpty {
                    Section {
                        ForEach(unlisted) { entry in fileLink(entry) }
                    } header: { Text("未列入书单") } footer: { Text("在书单里给它们加上书名和角色后，会归到对应的书下。") }
                }
            } else {
                ForEach(catalog.books.filter { matches($0.title) || $0.editions.contains(where: { matches($0.name) }) }) { book in
                    Section(book.title) {
                        ForEach(book.editions) { entry in fileLink(entry) }
                    }
                }
            }
            if !catalog.indexes.isEmpty {
                Section("文章与书单") {
                    ForEach(catalog.indexes.filter { matches($0.name) }) { entry in fileLink(entry) }
                }
            }
            if catalog.books.isEmpty && catalog.indexes.isEmpty && recent.isEmpty && (listed ?? []).isEmpty {
                ContentUnavailableView("还没有阅读内容", systemImage: "books.vertical", description: Text("可以从目录打开书籍、PDF，或在文章的操作菜单中选择“用阅读器打开”。"))
            }
        }
        .navigationTitle("书籍与文章").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "查找书籍、论文、文章")
        .task(id: state.config.storageKey + state.treeSHA + String(state.fileDisplay.hideDotFiles)) { await discoverLists() }
    }
    private func fileLink(_ entry: TreeEntry) -> some View {
        NavigationLink(value: readingRoute(entry.path, index: state.index)) {
            ReadingRow(title: (entry.name as NSString).deletingPathExtension, format: entry.isMarkdown ? "Markdown" : entry.ext.uppercased(), record: state.reading.history.records[entry.path])
        }.accessibilityIdentifier("reading-file:" + entry.path)
    }
    private func latest(_ book: ListedBook) -> ReadingRecord? {
        book.paths.compactMap { state.reading.history.records[$0] }.filter { state.fileDisplay.includes($0.path) }.max { $0.updatedAt < $1.updatedAt }
    }
    private func matches(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }
    private func matches(_ book: ListedBook) -> Bool {
        query.isEmpty || matches(book.title) || matches(book.author ?? "") || book.links.contains { matches($0.label) || matches($0.path ?? "") }
    }
    /// Reads every top-level Markdown in a reading folder: explicit books first, linked PDFs for the folder fallback.
    private func discoverLists() async {
        indexError = nil
        let key = state.config.storageKey, visible = VaultIndex(state.visibleEntries)
        var books: [ListedBook] = [], pdfs = Set<String>()
        for entry in BookCatalog(index: visible).indexes where (entry.size ?? 0) < 256 * 1024 {
            do {
                let data = try await state.file(entry.path)
                try Task.checkCancellation()
                guard key == state.config.storageKey else { return }
                let markdown = String(decoding: data, as: UTF8.self)
                books += BookList(markdown: markdown, at: entry.path, index: state.index).books
                pdfs.formUnion(BookCatalog.linkedPDFs(in: markdown, at: entry.path, index: visible))
            } catch is CancellationError { return }
            catch { indexError = error.localizedDescription }
        }
        linkedPDFs = pdfs; listed = books
    }
}

private struct BookRow: View {
    let book: ListedBook
    let latest: ReadingRecord?
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed").foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(book.title).foregroundStyle(.primary).lineLimit(2)
                let info = [book.author, book.status, book.rating].compactMap { $0 }
                if !info.isEmpty { Text(info.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if let latest { Text("上次：\(latest.title) · \(progressText(latest))").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }.padding(.vertical, 5)
    }
}

struct BookDetailView: View {
    let state: AppState
    let book: ListedBook
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title).font(.title3.weight(.semibold))
                    if let author = book.author { Text(author).foregroundStyle(.secondary) }
                    let info = [book.status, book.rating].compactMap { $0 }
                    if !info.isEmpty { Text(info.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 4)
                ForEach(Array(book.remarks.enumerated()), id: \.offset) { _, remark in Text(remark).font(.callout) }
            }
            ForEach(BookRole.allCases, id: \.self) { role in
                let links = book.links(role).filter { $0.path.map(state.fileDisplay.includes) ?? true }
                if !links.isEmpty || (role == .review && !book.comments.isEmpty) {
                    Section(role.title) {
                        if role == .review { ForEach(Array(book.comments.enumerated()), id: \.offset) { _, comment in Text(comment) } }
                        ForEach(links) { link in row(link) }
                    }
                }
            }
            if book.links.isEmpty && book.comments.isEmpty {
                Section { Text("书单里还没有这本书的文件。整理好原书、全文、精简版或笔记后，在书单里这本书下面加一行即可。").font(.callout).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func row(_ link: BookLink) -> some View {
        if let path = link.path, let entry = state.index.files[path] {
            NavigationLink(value: readingRoute(path, index: state.index)) {
                ReadingRow(title: link.label, format: entry.isMarkdown ? "Markdown" : entry.ext.uppercased(), record: state.reading.history.records[path], detail: link.detail)
            }.accessibilityIdentifier("reading-file:" + path)
        } else if let url = link.url {
            Link(destination: url) {
                HStack(spacing: 12) {
                    Image(systemName: "safari").foregroundStyle(.tint).frame(width: 24)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(link.label).foregroundStyle(.primary).lineLimit(2)
                        Text(url.host ?? url.absoluteString).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 5)
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.folder").foregroundStyle(.secondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(link.label).foregroundStyle(.secondary).lineLimit(2)
                    Text("未找到：\(link.target)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }.padding(.vertical, 5).accessibilityIdentifier("reading-missing:" + link.target)
        }
    }
}

extension BookRole {
    var title: String {
        switch self {
        case .condensed: "精简版"
        case .fulltext: "全文"
        case .reader: "阅读器"
        case .original: "原书"
        case .notes: "读书笔记"
        case .review: "评论"
        case .other: "其他"
        }
    }
}

private func progressText(_ record: ReadingRecord) -> String {
    if let page = record.location.page { return "第 \(page + 1) 页" }
    if record.kind == .html { return "接着上次阅读" }
    return "已读 \(Int((record.location.fraction * 100).rounded()))%"
}

private struct ReadingRow: View {
    let title: String
    let format: String
    let record: ReadingRecord?
    var detail: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record?.kind == .pdf || format == "PDF" ? "doc.richtext" : "book.closed").foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).foregroundStyle(.primary).lineLimit(2)
                HStack {
                    Text(format)
                    if let record { Text(progressText(record)) }
                }.font(.caption).foregroundStyle(.secondary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
        }.padding(.vertical, 5)
    }
}
