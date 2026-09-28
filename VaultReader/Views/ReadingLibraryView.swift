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
            let recent = state.reading.history.recentMarkdown(limit: 3) { state.index.files[$0.path] != nil && state.fileDisplay.includes($0.path) }
            if !recent.isEmpty {
                Section(L10n.text("Continue reading")) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { offset, record in
                        Button { openProject(state.config, record.path) } label: {
                            ReadingRow(title: record.title, format: "\(state.config.owner)/\(state.config.repo)", record: record)
                        }.accessibilityIdentifier(offset == 0 ? "continueReading" : "continueReading-\(offset)")
                    }
                }
            }
            Section(L10n.text("Projects")) {
                ForEach(state.library.repositories, id: \.storageKey) { config in
                    Button { openProject(config, nil) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "books.vertical").font(.title2).foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(config.owner)/\(config.repo)").foregroundStyle(.primary)
                                Text("\(config.provider.title) · \(config.branch)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }.padding(.vertical, 6)
                    }.disabled(state.switchingRepository).accessibilityIdentifier("reading-project-" + config.owner + "/" + config.repo + "-" + config.branch)
                }
            }
        }
        .navigationTitle(L10n.text("Reading")).navigationBarTitleDisplayMode(.inline)
    }
}

struct ReadingLibraryView: View {
    let state: AppState
    @State private var linkedPDFs = Set<String>()
    /// Books declared by reading-list Markdown; nil until the lists have been read once.
    @State private var listed: [ListedBook]?
    /// Reading-list files that were read, shown with articles so the list itself can be opened.
    @State private var listFiles: [String] = []
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
                Section(L10n.text("Recently read")) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { offset, record in
                        NavigationLink(value: readingRoute(record.path, index: state.index)) {
                            ReadingRow(title: record.title, format: "Markdown", record: record)
                        }.accessibilityIdentifier(offset == 0 ? "continueBook" : "recentBook")
                    }
                }
            }
            if let error = indexError {
                Section { Text(L10n.format("Some book lists could not be loaded: %1$@", error)).font(.caption).foregroundStyle(.secondary) }
            }
            if listed == nil {
                Section { HStack(spacing: 10) { ProgressView(); Text(L10n.text("Loading book lists…")).foregroundStyle(.secondary) } }
            } else if let listed, !listed.isEmpty {
                ForEach(BookList.groups(books)) { group in
                    Section(group.title ?? L10n.text("Books")) {
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
                    } header: { Text(L10n.text("Not in a book list")) } footer: { Text(L10n.text("Add a title and role in your book list to group these files under a book.")) }
                }
            } else {
                ForEach(catalog.books.filter { matches($0.title) || $0.editions.contains(where: { matches($0.name) }) }) { book in
                    Section(book.title) {
                        ForEach(book.editions) { entry in fileLink(entry) }
                    }
                }
            }
            let articles = listFiles.compactMap { state.index.files[$0] }.filter { state.fileDisplay.includes($0.path) } + catalog.indexes.filter { !listFiles.contains($0.path) }
            if !articles.isEmpty {
                Section(L10n.text("Articles & book lists")) {
                    ForEach(articles.filter { matches($0.name) }) { entry in fileLink(entry) }
                }
            }
            if listed != nil && catalog.books.isEmpty && articles.isEmpty && recent.isEmpty && (listed ?? []).isEmpty {
                ContentUnavailableView(L10n.text("No reading content yet"), systemImage: "books.vertical", description: Text(L10n.text("Add “booklist: path/to/booklist.md” to README frontmatter, or create booklist.md. You can also open any article from Files and choose Open in reader.")))
            }
        }
        .navigationTitle(L10n.text("Books & articles")).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: L10n.text("Find books, papers and articles"))
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
    /// The root README's `书单:` frontmatter names the lists for any vault layout. Without it,
    /// conventional `书单.md`/`booklist.md` files and top-level reading-folder Markdown are read.
    private func discoverLists() async {
        indexError = nil
        let key = state.config.storageKey, visible = VaultIndex(state.visibleEntries)
        var sources: [String] = []
        if let readme = BookList.readme(in: state.index), (state.index.files[readme]?.size ?? 0) < 256 * 1024 {
            do {
                let data = try await state.file(readme)
                try Task.checkCancellation()
                guard key == state.config.storageKey else { return }
                sources = BookList.declared(inReadme: String(decoding: data, as: UTF8.self), at: readme, index: state.index)
            } catch is CancellationError { return }
            catch { indexError = error.localizedDescription }
        }
        if sources.isEmpty { sources = BookList.conventional(in: visible) }
        var books: [ListedBook] = [], files: [String] = [], pdfs = Set<String>()
        for path in sources.prefix(32) where (state.index.files[path]?.size ?? 0) < 256 * 1024 {
            do {
                let data = try await state.file(path)
                try Task.checkCancellation()
                guard key == state.config.storageKey else { return }
                let markdown = String(decoding: data, as: UTF8.self)
                let found = BookList(markdown: markdown, at: path, index: state.index).books
                books += found
                if !found.isEmpty { files.append(path) }
                pdfs.formUnion(BookCatalog.linkedPDFs(in: markdown, at: path, index: visible))
            } catch is CancellationError { return }
            catch { indexError = error.localizedDescription }
        }
        linkedPDFs = pdfs; listFiles = files; listed = books
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
                if let latest { Text(L10n.format("Last read: %1$@ · %2$@", latest.title, progressText(latest))).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
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
                Section { Text(L10n.text("No files are listed for this book yet. Add links to the original, full text, summary or notes under the book in your book list.")).font(.callout).foregroundStyle(.secondary) }
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
                    Text(L10n.format("Not found: %1$@", link.target)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }.padding(.vertical, 5).accessibilityIdentifier("reading-missing:" + link.target)
        }
    }
}

extension BookRole {
    var title: String {
        switch self {
        case .condensed: L10n.text("Summary")
        case .fulltext: L10n.text("Full text")
        case .reader: L10n.text("Reader")
        case .original: L10n.text("Original")
        case .notes: L10n.text("Reading notes")
        case .review: L10n.text("Reviews")
        case .other: L10n.text("Other")
        }
    }
}

private func progressText(_ record: ReadingRecord) -> String {
    if let page = record.location.page { return L10n.format("Page %1$ld", page + 1) }
    if record.kind == .html { return L10n.text("Resume reading") }
    return L10n.format("Read: %1$ld%%", Int((record.location.fraction * 100).rounded()))
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
