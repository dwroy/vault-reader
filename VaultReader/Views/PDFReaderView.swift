import SwiftUI
import PDFKit
import VaultCore

@MainActor @Observable final class PDFReadingSession {
    let document: PDFDocument
    let book: BookSession
    var page: Int
    var requestedPage: Int
    var requestID = UUID()
    init(document: PDFDocument, book: BookSession) {
        self.document = document; self.book = book
        let startPage = min(max(0, book.record.location.page ?? 0), max(0, document.pageCount - 1))
        page = startPage; requestedPage = startPage
    }
    func go(_ page: Int) { requestedPage = min(max(0, page), max(0, document.pageCount - 1)); requestID = UUID() }
    func changed(_ page: Int) {
        self.page = page
        book.save(ReadingLocation(fraction: document.pageCount > 1 ? Double(page) / Double(document.pageCount - 1) : 1, page: page))
    }
    var outline: [(String, Int)] {
        var rows: [(String, Int)] = []
        func walk(_ item: PDFOutline, depth: Int) {
            guard depth < 12, rows.count < 2000 else { return }
            if let title = item.label, let page = item.destination?.page {
                rows.append((String(repeating: "　", count: max(0, depth - 1)) + title, document.index(for: page)))
            }
            for i in 0..<item.numberOfChildren { if let child = item.child(at: i) { walk(child, depth: depth + 1) } }
        }
        if let root = document.outlineRoot { walk(root, depth: 0) }
        return rows
    }
}

private final class RestoringPDFView: PDFView {
    var initialPage: Int?
    var ready = false
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, let index = initialPage, let page = document?.page(at: index) else { return }
        initialPage = nil
        autoScales = true; go(to: page); ready = true
    }
}
private struct PDFCanvas: UIViewRepresentable {
    let session: PDFReadingSession
    func makeCoordinator() -> Coordinator { Coordinator(session) }
    func makeUIView(context: Context) -> RestoringPDFView {
        let view = RestoringPDFView()
        view.displayMode = .singlePageContinuous; view.displayDirection = .vertical
        view.displaysPageBreaks = true; view.backgroundColor = .secondarySystemBackground
        view.document = session.document; view.initialPage = session.page
        view.accessibilityIdentifier = "bookPDF"
        context.coordinator.view = view
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak coordinator = context.coordinator] _ in
            Task { @MainActor in coordinator?.capture() }
        }
        context.coordinator.lastRequest = session.requestID
        return view
    }
    func updateUIView(_ view: RestoringPDFView, context: Context) {
        guard context.coordinator.lastRequest != session.requestID else { return }
        context.coordinator.lastRequest = session.requestID
        if view.ready, let page = session.document.page(at: session.requestedPage) { view.go(to: page) }
        else { view.initialPage = session.requestedPage; view.setNeedsLayout() }
    }
    static func dismantleUIView(_ view: RestoringPDFView, coordinator: Coordinator) {
        coordinator.capture(); coordinator.session.book.store.flush()
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
        view.document = nil
    }
    @MainActor final class Coordinator: NSObject {
        let session: PDFReadingSession
        weak var view: RestoringPDFView?
        var observer: NSObjectProtocol?
        var lastRequest: UUID?
        init(_ session: PDFReadingSession) { self.session = session }
        func capture() {
            guard let view, view.ready, let page = view.currentPage else { return }
            let index = session.document.index(for: page)
            if index != NSNotFound { session.changed(index) }
        }
    }
}

struct PDFReaderView: View {
    let state: AppState
    let path: String
    @State private var session: PDFReadingSession?
    @State private var preview: URL?
    @State private var previewStore: BlobStore?
    @State private var progress: Double?
    @State private var error: String?
    @State private var attempt = 0
    @State private var cancelled = false
    @State private var showingContents = false
    @State private var pageInput = ""
    @State private var showingPage = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let session {
                PDFCanvas(session: session)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(spacing: 0) {
                            if let warning = session.book.store.saveError { Text(warning).font(.caption).foregroundStyle(.orange) }
                            HStack {
                                Button("上一页", systemImage: "chevron.left") { session.go(session.page - 1) }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).disabled(session.page == 0)
                                Spacer()
                                Button("第 \(session.page + 1) / \(session.document.pageCount) 页") { pageInput = String(session.page + 1); showingPage = true }.frame(minHeight: 44).accessibilityIdentifier("pdfPage")
                                Spacer()
                                Button("下一页", systemImage: "chevron.right") { session.go(session.page + 1) }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).disabled(session.page >= session.document.pageCount - 1)
                            }.padding(.horizontal, 24).padding(.vertical, 6)
                        }.background(.bar)
                    }
            } else if let error {
                ContentUnavailableView { Label(cancelled ? "下载已取消" : "无法打开 PDF", systemImage: "doc") } description: { Text(error) } actions: {
                    Button("重试") { cancelled = false; attempt += 1 }
                    Link("在仓库中打开", destination: state.config.fileURL(path: path))
                }
            } else {
                VStack(spacing: 18) {
                    if let progress { ProgressView(value: progress).frame(maxWidth: 240) } else { ProgressView("正在打开 PDF…") }
                    Button("取消") { cancelled = true; error = "可以稍后重新下载。" }
                }
            }
        }
        .navigationTitle((path as NSString).lastPathComponent).navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("目录", systemImage: "list.bullet") { showingContents = true }.disabled(session == nil) } }
        .sheet(isPresented: $showingContents) {
            NavigationStack {
                if let session {
                    let outline = session.outline
                    List {
                        if outline.isEmpty { Text("这份 PDF 没有章节目录，可以按页码跳转。").foregroundStyle(.secondary) }
                        ForEach(Array(outline.enumerated()), id: \.offset) { row in
                            Button(row.element.0) { session.go(row.element.1); showingContents = false }
                        }
                        Button("跳到指定页") { pageInput = String(session.page + 1); showingContents = false; showingPage = true }
                    }
                    .navigationTitle("PDF 目录").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingContents = false } } }
                }
            }
        }
        .alert("跳转页码", isPresented: $showingPage) {
            TextField("页码", text: $pageInput).keyboardType(.numberPad)
            Button("跳转") { if let page = Int(pageInput), let session { session.go(page - 1) } }
            Button("取消", role: .cancel) {}
        }
        .task(id: "\(attempt)|\(cancelled)") { await load() }
        .onDisappear {
            session?.book.store.flush()
            if let preview, let previewStore { Task { try? await previewStore.releasePreview(preview) } }
            preview = nil; previewStore = nil; session = nil
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { session?.book.store.flush() } }
    }
    private func load() async {
        guard !cancelled, session == nil else { return }
        error = nil; progress = nil
        let store = state.blobs, book = BookSession(path: path, kind: .pdf, store: state.reading)
        do {
            let file = try await state.preview(path, progress: { value in Task { @MainActor in progress = value } })
            if Task.isCancelled { try? await store?.releasePreview(file); return }
            guard let document = PDFDocument(url: file), !document.isLocked, document.pageCount > 0 else {
                try? await store?.releasePreview(file)
                throw CocoaError(.fileReadCorruptFile)
            }
            preview = file; previewStore = store
            session = PDFReadingSession(document: document, book: book); book.opened()
        } catch is CancellationError {} catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
