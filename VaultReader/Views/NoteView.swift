import SwiftUI
import SafariServices
import VaultCore

struct PreviewItem: Identifiable { let url: URL; var id: URL { url } }
struct NoteView: View {
    let state: AppState
    let route: NoteRoute
    let navigate: (ReaderRoute) -> Void
    var readingBook = false
    @State private var book: BookSession?
    @Environment(\.scenePhase) private var scenePhase
    @State private var markdown: String?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var previewPath: String?
    @State private var video: PreviewItem?
    @State private var readerSession = ReaderSession()
    @State private var external: PreviewItem?
    @State private var shareContent: NoteShareContent?
    @State private var shareTask: Task<Void, Never>?
    var body: some View {
        Group {
            if let markdown {
                RendererWebView(state: state, session: book?.viewport ?? readerSession, markdown: markdown, path: route.path, anchor: route.anchor, onOpen: open, onPreview: showPreview, onError: { actionError = $0 }, readingOptions: book?.record, searchTerms: route.searchTerms)
            } else if let loadError {
                ContentUnavailableView {
                    Label(L10n.text("Could not open file"), systemImage: "doc.text.magnifyingglass")
                } description: { Text(loadError) } actions: {
                    Button(L10n.text("Retry")) { Task { await load() } }.buttonStyle(.bordered)
                    Button(L10n.text("Settings")) { state.showSettings = true }
                }
            } else { ProgressView(L10n.text("Loading…")) }
        }
        .safeAreaInset(edge: .top, spacing: 0) { if !readingBook { StatusBanner(state: state) } }
        .safeAreaInset(edge: .bottom, spacing: 0) { if let book { ReadingControls(book: book) } }
        .toolbar(readingBook ? .hidden : .automatic, for: .tabBar)
        .preferredColorScheme(book?.record.theme == .dark ? .dark : (book?.record.theme == .light || book?.record.theme == .sepia ? .light : nil))
        .navigationTitle((route.path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: state.config.identity + state.config.branch + (state.index.files[route.path]?.sha ?? "missing")) { await load() }
        .sheet(isPresented: Binding(get: { previewPath != nil }, set: { if !$0 { previewPath = nil } })) {
            if let path = previewPath { AttachmentSheet(state: state, path: path) }
        }
        .sheet(item: $video) { VideoSheet(url: $0.url) }
        .sheet(item: $external) { SafariView(url: $0.url) }
        .sheet(item: $shareContent) { NoteShareSheet(content: $0) }
        .alert(L10n.text("Notice"), isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) { Button(L10n.text("OK"), role: .cancel) {} } message: { Text(actionError ?? "") }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !readingBook { Button(L10n.text("Open in reader"), systemImage: "book") { navigate(.note(NoteRoute(path: route.path, anchor: route.anchor, reading: true, searchTerms: route.searchTerms))) } }
                    Button(L10n.text("Share"), systemImage: "square.and.arrow.up", action: share)
                        .disabled(markdown == nil || shareTask != nil)
                    Button(L10n.text("Copy path"), systemImage: "doc.on.doc") { UIPasteboard.general.string = route.path }
                    Button(L10n.format("Open in %1$@", state.config.provider.title), systemImage: "safari") { external = PreviewItem(url: state.config.fileURL(path: route.path)) }
                    Button(L10n.text("Refresh"), systemImage: "arrow.clockwise") { Task { await state.refresh(); await load() } }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel(L10n.text("Note actions")).accessibilityIdentifier("noteActions")
            }
        }
        .onAppear { (book?.viewport ?? readerSession).resume() }
        .onDisappear { shareTask?.cancel(); shareTask = nil; (book?.viewport ?? readerSession).suspend(); book?.store.flush() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { book?.store.flush() } }
    }
    private func share() {
        guard shareTask == nil else { return }
        guard let web = (book?.viewport ?? readerSession).container?.web else {
            actionError = L10n.text("Wait for the article to finish loading before sharing."); return
        }
        shareTask = Task { @MainActor in
            defer { shareTask = nil }
            do {
                let content = try await NoteShareContent.read(from: web)
                try Task.checkCancellation()
                shareContent = content
            } catch is CancellationError {} catch {
                if !Task.isCancelled { actionError = L10n.format("Could not share: %1$@", error.localizedDescription) }
            }
        }
    }
    private func load() async {
        loadError = nil
        if readingBook, book == nil { book = BookSession(path: route.path, kind: .markdown, store: state.reading) }
        do {
            let data = try await state.file(route.path)
            try Task.checkCancellation()
            guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            markdown = text
            book?.opened()
        } catch is CancellationError {} catch { loadError = error.localizedDescription }
    }
    private func open(_ url: URL) {
        if url.scheme == "vault", url.host == "f" {
            let path = String(url.path.dropFirst())
            guard let entry = state.index.files[path] else { actionError = L10n.text("This note could not be found."); return }
            if entry.isMarkdown { navigate(.note(NoteRoute(path: path, anchor: url.fragment?.removingPercentEncoding ?? "", reading: readingBook))) }
            else if entry.isHTML || entry.ext == "pdf" { navigate(.file(path)) }
            else { showPreview(path) }
        } else if ["https", "http"].contains(url.scheme ?? "") {
            if ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) { video = PreviewItem(url: url) }
            else { external = PreviewItem(url: url) }
        }
        else if url.scheme == "obsidian" { actionError = L10n.text("Links to another vault are not supported. Switch repositories to open that content.") }
        else if url.scheme == "mailto" { UIApplication.shared.open(url) }
    }
    private func showPreview(_ path: String) {
        guard state.index.files[path] != nil else { return }
        if state.index.files[path]?.isHTML == true || state.index.files[path]?.ext == "pdf" { navigate(.file(path)) }
        else { previewPath = path }
    }
}
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
