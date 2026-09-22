import VaultCore
import SwiftUI

struct DirView: View {
    let state: AppState
    let path: String
    @State private var preview: PreviewItem?
    @State private var error: String?
    @State private var downloading: String?
    @State private var downloadTask: Task<Void, Never>?
    var body: some View {
        List {
            if path.isEmpty {
                Section { Text("\(state.config.owner) / \(state.config.repo)").font(.subheadline).foregroundStyle(.secondary) } footer: { Text("\(state.index.entries.count) 个文件 · \(state.config.branch)") }
            }
            ForEach(state.index.children(of: path)) { item in
                if item.isDirectory { NavigationLink(value: ReaderRoute.directory(item.path)) { row(item) } }
                else if item.entry?.isMarkdown == true { NavigationLink(value: ReaderRoute.note(NoteRoute(path: item.path))) { row(item) } }
                else {
                    Button { open(item.path) } label: { row(item) }.foregroundStyle(.primary)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { StatusBanner(state: state) }
        .navigationTitle(path.isEmpty ? "目录" : (path as NSString).lastPathComponent)
        .refreshable { await state.refresh() }
        .sheet(item: $preview) { PreviewSheet(url: $0.url) }
        .alert("无法预览", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好", role: .cancel) {} } message: { Text(error ?? "") }
        .safeAreaInset(edge: .bottom) {
            if downloading != nil { HStack { ProgressView(); Text("正在准备预览…"); Button("取消") { downloadTask?.cancel(); downloading = nil } }.padding().background(.bar) }
        }
        .onDisappear { downloadTask?.cancel() }
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
    private func open(_ path: String) {
        downloadTask?.cancel(); downloading = path
        downloadTask = Task {
            defer { downloading = nil }
            do { let url = try await state.preview(path); try Task.checkCancellation(); preview = PreviewItem(url: url) }
            catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}
