import SwiftUI
import WebKit
import VaultCore

struct RendererWebView: UIViewRepresentable {
    let state: AppState
    let session: ReaderSession
    let markdown: String
    let path: String
    let anchor: String
    let onOpen: (URL) -> Void
    let onPreview: (String) -> Void
    let onError: (String) -> Void
    var readingOptions: ReadingRecord? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WebViewContainer {
        let container = WebViewContainer(), coordinator = context.coordinator
        session.container = container
        container.create = { [weak coordinator] in
            guard let coordinator else { return nil }
            coordinator.loaded = false; coordinator.lastTree = ""; coordinator.lastRenderKey = ""; coordinator.renderedOnce = false

            let config = WKWebViewConfiguration()
            config.setURLSchemeHandler(SchemeHandler { try await state.file($0) }, forURLScheme: "vault")
            config.websiteDataStore = .nonPersistent()
            let adapter = """
            window.VaultHost = Object.freeze({
              resourceBaseURL: 'vault://file/',
              postMessage: (name, body) => {
                if (['open','preview','height'].includes(name)) window.webkit.messageHandlers[name].postMessage(body);
              }
            });
            """
            config.userContentController.addUserScript(WKUserScript(source: adapter, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            for name in ["open", "preview", "height"] { config.userContentController.add(coordinator, name: name) }
            let web = WKWebView(frame: .zero, configuration: config)
            web.isOpaque = false; web.backgroundColor = .clear
            web.navigationDelegate = coordinator
            web.scrollView.delegate = coordinator
            let refresh = UIRefreshControl()
            refresh.addTarget(coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
            web.scrollView.refreshControl = refresh
            web.load(URLRequest(url: URL(string: "vault://app/index.html")!))
            coordinator.web = web
            #if DEBUG
            ReaderWebViewRegistry.views.add(web)
            #endif
            return web
        }
        container.beforeRelease = { [weak coordinator] web in
            guard let coordinator else { return }
            if coordinator.renderedOnce { coordinator.parent.session.scrollY = web.scrollView.contentOffset.y }
            coordinator.captureTask?.cancel(); coordinator.captureTask = nil
            if coordinator.parent.readingOptions != nil, coordinator.renderedOnce {
                let position = coordinator.parent.session.onPosition, save = coordinator.parent.session.onSave
                Task {
                    if let raw = try? await web.evaluateJavaScript("VaultReader.capturePosition()"),
                       let data = try? JSONSerialization.data(withJSONObject: raw),
                       let value = try? JSONDecoder().decode(ReadingLocation.self, from: data) { position?(value) }
                    save?()
                }
            } else { coordinator.parent.session.onSave?() }
            coordinator.renderTask?.cancel(); coordinator.renderTask = nil
            coordinator.generation = UUID(); coordinator.updating = false
            coordinator.loaded = false; coordinator.web = nil
        }
        container.mount(); return container
    }
    func updateUIView(_ container: WebViewContainer, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update()
    }
    static func dismantleUIView(_ container: WebViewContainer, coordinator: Coordinator) {
        container.releaseWebView(); container.create = nil; container.beforeRelease = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIScrollViewDelegate {
        var parent: RendererWebView
        weak var web: WKWebView?
        var loaded = false
        var lastRenderKey = ""
        var lastTree = ""
        var renderedOnce = false
        var updating = false
        var generation = UUID()
        var renderTask: Task<Void, Never>?
        var captureTask: Task<Void, Never>?
        init(_ parent: RendererWebView) { self.parent = parent }
        func update() {
            guard loaded, let web, !updating else { return }
            let scale = UIFontMetrics.default.scaledValue(for: 17) / 17 * (parent.readingOptions?.fontScale ?? 1)
            let theme = parent.readingOptions?.theme == .system || parent.readingOptions == nil ? (parent.colorScheme == .dark ? "dark" : "light") : parent.readingOptions!.theme.rawValue
            let key = "\(parent.path)|\(parent.markdown)|\(parent.state.treeSHA)|\(scale)|\(theme)|\(parent.anchor)|\(parent.readingOptions != nil)"
            guard key != lastRenderKey else { return }
            updating = true
            let currentGeneration = generation, tree = parent.state.treeSHA, entriesToRender = parent.state.index.entries
            renderTask = Task {
                defer { if generation == currentGeneration { updating = false; if lastRenderKey == key { update() } } }
                do {
                    if lastTree != tree {
                        let data = try JSONEncoder().encode(entriesToRender)
                        let entries = try JSONSerialization.jsonObject(with: data)
                        _ = try await web.callAsyncJavaScript("if (VaultReader.version !== 2) throw new Error('Unsupported reader contract'); VaultReader.setTree(entries)", arguments: ["entries": entries], in: nil, contentWorld: .page)
                        try Task.checkCancellation()
                        lastTree = tree
                    }
                    let preserved = renderedOnce && parent.readingOptions != nil ? (try? await web.evaluateJavaScript("VaultReader.capturePosition()")) : nil
                    _ = try await web.callAsyncJavaScript("VaultReader.setReadingMode(book); return VaultReader.render(markdown, path, scale, theme)", arguments: ["markdown": parent.markdown, "path": parent.path, "scale": scale, "theme": theme, "book": parent.readingOptions != nil], in: nil, contentWorld: .page)
                    if !renderedOnce {
                        // A programmatic multi-level navigation can load WebKit before it is visible.
                        // Restore only after its real viewport exists, without relying on offscreen rAF.
                        for _ in 0..<100 {
                            try Task.checkCancellation()
                            if web.window != nil && web.bounds.width > 0 && web.bounds.height > 0 { break }
                            try await Task.sleep(for: .milliseconds(30))
                        }
                        guard web.window != nil, web.bounds.width > 0 else { throw CancellationError() }
                        // Offscreen requestAnimationFrame promises can never settle and retain WebKit.
                        // Poll font readiness with cancellable native waits instead.
                        for _ in 0..<100 {
                            try Task.checkCancellation()
                            if (try await web.evaluateJavaScript("document.fonts.status")) as? String == "loaded" { break }
                            try await Task.sleep(for: .milliseconds(50))
                        }
                        try await Task.sleep(for: .milliseconds(35))
                        try Task.checkCancellation()
                        if let position = parent.session.position, parent.readingOptions != nil, parent.anchor.isEmpty {
                            let data = try JSONEncoder().encode(position)
                            let object = try JSONSerialization.jsonObject(with: data)
                            _ = try await web.callAsyncJavaScript("VaultReader.restorePosition(position)", arguments: ["position": object], in: nil, contentWorld: .page)
                            try await Task.sleep(for: .milliseconds(50))
                        } else if let y = parent.session.scrollY {
                            _ = try await web.callAsyncJavaScript("window.scrollTo(0, y)", arguments: ["y": y], in: nil, contentWorld: .page)
                            try await Task.sleep(for: .milliseconds(35))
                        } else if !parent.anchor.isEmpty {
                            _ = try await web.callAsyncJavaScript("VaultReader.scrollToAnchor(anchor)", arguments: ["anchor": parent.anchor], in: nil, contentWorld: .page)
                        }
                        renderedOnce = true
                        web.accessibilityIdentifier = "reader-ready"
                        parent.state.recordHomeRendered(parent.path)
                    }
                    if let preserved {
                        _ = try await web.callAsyncJavaScript("VaultReader.restorePosition(position)", arguments: ["position": preserved], in: nil, contentWorld: .page)
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    if parent.readingOptions != nil {
                        if let raw = try await web.evaluateJavaScript("VaultReader.outline()") as? [[String: Any]] {
                            let data = try JSONSerialization.data(withJSONObject: raw)
                            parent.session.onOutline?(try JSONDecoder().decode([ReadingOutline].self, from: data))
                        }
                        if let section = parent.session.sectionRequest {
                            parent.session.sectionRequest = nil
                            _ = try await web.callAsyncJavaScript("VaultReader.scrollToSection(id)", arguments: ["id": section], in: nil, contentWorld: .page)
                        }
                    }
                    try Task.checkCancellation()
                    if parent.readingOptions != nil, let raw = try await web.evaluateJavaScript("VaultReader.capturePosition()") {
                        try Task.checkCancellation()
                        let data = try JSONSerialization.data(withJSONObject: raw)
                        let position = try JSONDecoder().decode(ReadingLocation.self, from: data)
                        parent.session.position = position; parent.session.onPosition?(position)
                    }
                    lastRenderKey = key
                } catch is CancellationError {} catch { if !Task.isCancelled { parent.onError("排版加载失败：\(error.localizedDescription)") } }
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true; update() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { parent.onError(error.localizedDescription) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loaded = false; lastTree = ""; lastRenderKey = ""; renderedOnce = false; webView.reload() }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.host == "app", let body = message.body as? [String: Any] else { return }
            if message.name == "open", let href = body["href"] as? String, let url = URL(string: href) {
                if url.scheme == "vault", url.host == "f", String(url.path.dropFirst()) == parent.path {
                    Task { _ = try? await web?.callAsyncJavaScript("VaultReader.scrollToAnchor(anchor)", arguments: ["anchor": url.fragment?.removingPercentEncoding ?? ""], in: nil, contentWorld: .page) }
                } else { parent.onOpen(url) }
            }
            if message.name == "preview", let path = body["path"] as? String { parent.onPreview(path) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .other, action.request.url?.absoluteString == "vault://app/index.html", !loaded { decisionHandler(.allow) }
            else { decisionHandler(.cancel); if action.navigationType == .linkActivated, let url = action.request.url { parent.onOpen(url) } }
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard renderedOnce, !updating, scrollView.window != nil else { return }
            parent.session.scrollY = scrollView.contentOffset.y
            guard parent.readingOptions != nil else { return }
            captureTask?.cancel()
            captureTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(120)); try Task.checkCancellation()
                    guard let self, let web = self.web, self.renderedOnce else { return }
                    let raw = try await web.evaluateJavaScript("VaultReader.capturePosition()")
                    try Task.checkCancellation()
                    guard let raw else { return }
                    let data = try JSONSerialization.data(withJSONObject: raw)
                    let position = try JSONDecoder().decode(ReadingLocation.self, from: data)
                    self.parent.session.position = position
                    self.parent.session.onPosition?(position)
                } catch {}
            }
        }
        @objc func refresh(_ sender: UIRefreshControl) {
            Task { await parent.state.refresh(); sender.endRefreshing() }
        }
    }
}

#if DEBUG
@MainActor enum ReaderWebViewRegistry {
    static let views = NSHashTable<WKWebView>.weakObjects()
}
#endif
