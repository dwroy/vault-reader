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
            if let record = state.reading.history.recent.first(where: { state.index.files[$0.path] != nil }) {
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
    @State private var query = ""
    @State private var indexError: String?
    private var catalog: BookCatalog { BookCatalog(index: state.index, linkedPDFs: linkedPDFs) }
    private var recent: [ReadingRecord] { state.reading.history.recent.filter { state.index.files[$0.path] != nil && matches($0.title) } }
    var body: some View {
        List {
            Section {
                Text("\(state.config.owner)/\(state.config.repo)").font(.subheadline).foregroundStyle(.secondary)
            }
            if let record = recent.first {
                Section("继续阅读") {
                    NavigationLink(value: readingRoute(record.path, index: state.index)) {
                        ReadingRow(title: record.title, format: record.kind.rawValue.uppercased(), record: record)
                    }.accessibilityIdentifier("continueBook")
                }
            }
            if recent.count > 1 {
                Section("最近阅读") {
                    ForEach(recent.dropFirst().prefix(12)) { record in
                        NavigationLink(value: readingRoute(record.path, index: state.index)) {
                            ReadingRow(title: record.title, format: record.kind.rawValue.uppercased(), record: record)
                        }
                    }
                }
            }
            if let error = indexError {
                Section { Text("部分书单附件暂未载入：\(error)").font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(catalog.books.filter { matches($0.title) || $0.editions.contains(where: { matches($0.name) }) }) { book in
                Section(book.title) {
                    ForEach(book.editions) { entry in
                        NavigationLink(value: readingRoute(entry.path, index: state.index)) {
                            ReadingRow(title: (entry.name as NSString).deletingPathExtension, format: entry.ext.uppercased(), record: state.reading.history.records[entry.path])
                        }.accessibilityIdentifier("reading-file:" + entry.path)
                    }
                }
            }
            if !catalog.indexes.isEmpty {
                Section("文章与书单") {
                    ForEach(catalog.indexes.filter { matches($0.name) }) { entry in
                        NavigationLink(value: readingRoute(entry.path, index: state.index)) {
                            ReadingRow(title: (entry.name as NSString).deletingPathExtension, format: "Markdown", record: state.reading.history.records[entry.path])
                        }.accessibilityIdentifier("reading-file:" + entry.path)
                    }
                }
            }
            if catalog.books.isEmpty && catalog.indexes.isEmpty && recent.isEmpty {
                ContentUnavailableView("还没有阅读内容", systemImage: "books.vertical", description: Text("可以从目录打开书籍、PDF，或在文章的操作菜单中选择“用阅读器打开”。"))
            }
        }
        .navigationTitle("书籍与文章").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "查找书籍、论文、文章")
        .task(id: state.config.storageKey + state.treeSHA) { await discoverAttachments() }
    }
    private func matches(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }
    private func discoverAttachments() async {
        linkedPDFs = []; indexError = nil
        let key = state.config.storageKey, index = state.index
        for entry in BookCatalog(index: index).indexes where (entry.size ?? 0) < 256 * 1024 {
            do {
                let data = try await state.file(entry.path)
                try Task.checkCancellation()
                guard key == state.config.storageKey else { return }
                linkedPDFs.formUnion(BookCatalog.linkedPDFs(in: String(decoding: data, as: UTF8.self), at: entry.path, index: index))
            } catch is CancellationError { return }
            catch { indexError = error.localizedDescription }
        }
    }
}

private struct ReadingRow: View {
    let title: String
    let format: String
    let record: ReadingRecord?
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record?.kind == .pdf || format == "PDF" ? "doc.richtext" : "book.closed").foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).foregroundStyle(.primary).lineLimit(2)
                HStack {
                    Text(format)
                    if let record {
                        if let page = record.location.page { Text("第 \(page + 1) 页") }
                        else if record.kind == .html { Text("接着上次阅读") }
                        else { Text("已读 \(Int((record.location.fraction * 100).rounded()))%") }
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
    }
}
