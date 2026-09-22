import VaultCore
import SwiftUI

struct DirView: View {
    let state: AppState
    let path: String
    var body: some View {
        List {
            if path.isEmpty {
                Section { Text("\(state.config.owner) / \(state.config.repo)").font(.subheadline).foregroundStyle(.secondary) } footer: { Text("\(state.index.entries.count) 个文件 · \(state.config.branch)") }
            }
            ForEach(state.index.children(of: path)) { item in
                if item.isDirectory { NavigationLink(value: ReaderRoute.directory(item.path)) { row(item) } }
                else if item.entry?.isMarkdown == true { NavigationLink(value: ReaderRoute.note(NoteRoute(path: item.path))) { row(item) } }
                else {
                    NavigationLink(value: ReaderRoute.file(item.path)) { row(item) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { StatusBanner(state: state) }
        .navigationTitle(path.isEmpty ? "目录" : (path as NSString).lastPathComponent)
        .refreshable { await state.refresh() }

    }
    private func row(_ item: DirectoryItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.isDirectory ? "folder" : item.entry?.isMarkdown == true ? "doc.text" : "doc").foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.body)
                if let bytes = item.entry?.size { Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
            }.padding(.vertical, 4)
        }
    }
}
