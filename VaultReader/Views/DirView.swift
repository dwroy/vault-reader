import VaultCore
import SwiftUI

struct DirView: View {
    let state: AppState
    let path: String
    var body: some View {
        List {
            if path.isEmpty {
                Section { Text("\(state.config.owner) / \(state.config.repo)").font(.subheadline).foregroundStyle(.secondary) } footer: { Text("\(state.visibleEntries.count) 个文件 · \(state.config.branch)") }
            }
            ForEach(state.index.children(of: path).filter { state.fileDisplay.includes($0.path) }) { item in
                if item.isDirectory { NavigationLink(value: ReaderRoute.directory(item.path)) { row(item) } }
                else if item.entry?.isMarkdown == true { NavigationLink(value: ReaderRoute.note(NoteRoute(path: item.path))) { row(item) } }
                else {
                    NavigationLink(value: ReaderRoute.file(item.path)) { row(item) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { StatusBanner(state: state) }
        .navigationTitle(path.isEmpty ? "目录" : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await state.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("刷新", systemImage: "arrow.clockwise") { Task { await state.refresh() } }
                        .disabled(state.isRefreshing || state.switchingRepository)
                    Button("设置", systemImage: "gearshape") { state.addingRepository = false; state.showSettings = true }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("目录操作")
            }
        }
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
