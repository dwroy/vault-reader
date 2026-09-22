import SwiftUI
import SafariServices

struct PreviewItem: Identifiable { let url: URL; var id: URL { url } }
struct NoteView: View {
    let state: AppState
    let route: NoteRoute
    let navigate: (NoteRoute) -> Void
    @State private var markdown: String?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var preview: PreviewItem?
    @State private var external: PreviewItem?
    @State private var downloading = false
    @State private var downloadTask: Task<Void, Never>?
    var body: some View {
        Group {
            if let markdown {
                RendererWebView(state: state, markdown: markdown, path: route.path, anchor: route.anchor, onOpen: open, onPreview: showPreview, onError: { actionError = $0 })
            } else if let loadError {
                ContentUnavailableView {
                    Label("暂时无法打开", systemImage: "doc.text.magnifyingglass")
                } description: { Text(loadError) } actions: {
                    Button("重试") { Task { await load() } }.buttonStyle(.bordered)
                    Button("设置") { state.showSettings = true }
                }
            } else { ProgressView("正在读取…") }
        }
        .safeAreaInset(edge: .top, spacing: 0) { StatusBanner(state: state) }
        .navigationTitle((route.path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: state.config.identity + state.config.branch + (state.index.files[route.path]?.sha ?? "missing")) { await load() }
        .sheet(item: $preview) { PreviewSheet(url: $0.url) }
        .sheet(item: $external) { SafariView(url: $0.url) }
        .alert("提示", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) { Button("好", role: .cancel) {} } message: { Text(actionError ?? "") }
        .overlay(alignment: .bottom) {
            if downloading { HStack { ProgressView(); Text("正在准备预览…"); Button("取消") { downloadTask?.cancel(); downloading = false } }.font(.callout).padding().background(.regularMaterial, in: Capsule()).padding() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("复制路径", systemImage: "doc.on.doc") { UIPasteboard.general.string = route.path }
                    Button("在 GitHub 打开", systemImage: "safari") { external = PreviewItem(url: state.config.githubURL(path: route.path)) }
                    Button("刷新", systemImage: "arrow.clockwise") { Task { await state.refresh(); await load() } }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("笔记操作")
            }
        }
        .onDisappear { downloadTask?.cancel() }
    }
    private func load() async {
        loadError = nil
        do {
            let data = try await state.file(route.path)
            try Task.checkCancellation()
            guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            markdown = text
        } catch is CancellationError {} catch { loadError = error.localizedDescription }
    }
    private func open(_ url: URL) {
        if url.scheme == "vault", url.host == "f" {
            let path = String(url.path.dropFirst())
            guard let entry = state.index.files[path] else { actionError = "未找到这篇笔记。"; return }
            if entry.isMarkdown { navigate(NoteRoute(path: path, anchor: url.fragment?.removingPercentEncoding ?? "")) }
            else { showPreview(path) }
        } else if ["https", "http"].contains(url.scheme ?? "") { external = PreviewItem(url: url) }
        else if url.scheme == "obsidian" { actionError = "这是另一个 vault 的链接。多仓库支持将在后续版本加入。" }
        else if url.scheme == "mailto" { UIApplication.shared.open(url) }
    }
    private func showPreview(_ path: String) {
        downloadTask?.cancel(); downloading = true
        downloadTask = Task {
            defer { downloading = false }
            do { let url = try await state.preview(path); try Task.checkCancellation(); preview = PreviewItem(url: url) }
            catch is CancellationError {} catch { actionError = error.localizedDescription }
        }
    }
}
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
