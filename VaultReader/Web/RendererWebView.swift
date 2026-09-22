import SwiftUI
import WebKit

struct RendererWebView: UIViewRepresentable {
    let state: AppState
    let session: ReaderSession
    let markdown: String
    let path: String
    let anchor: String
    let onOpen: (URL) -> Void
    let onPreview: (String) -> Void
    let onError: (String) -> Void
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
        init(_ parent: RendererWebView) { self.parent = parent }
        func update() {
            guard loaded, let web, !updating else { return }
            let scale = UIFontMetrics.default.scaledValue(for: 17) / 17
            let theme = parent.colorScheme == .dark ? "dark" : "light"
            let key = "\(parent.path)|\(parent.markdown)|\(parent.state.treeSHA)|\(scale)|\(theme)|\(parent.anchor)"
            guard key != lastRenderKey else { return }
            updating = true
            let currentGeneration = generation, tree = parent.state.treeSHA, entriesToRender = parent.state.index.entries
            renderTask = Task {
                defer { if generation == currentGeneration { updating = false; if lastRenderKey == key { update() } } }
                do {
                    if lastTree != tree {
                        let data = try JSONEncoder().encode(entriesToRender)
                        let entries = try JSONSerialization.jsonObject(with: data)
                        _ = try await web.callAsyncJavaScript("if (VaultReader.version !== 1) throw new Error('Unsupported reader contract'); VaultReader.setTree(entries)", arguments: ["entries": entries], in: nil, contentWorld: .page)
                        try Task.checkCancellation()
                        lastTree = tree
                    }
                    _ = try await web.callAsyncJavaScript("return VaultReader.render(markdown, path, scale, theme)", arguments: ["markdown": parent.markdown, "path": parent.path, "scale": scale, "theme": theme], in: nil, contentWorld: .page)
                    if !renderedOnce {
                        // Offscreen requestAnimationFrame promises can never settle and retain WebKit.
                        // Poll font readiness with cancellable native waits instead.
                        for _ in 0..<100 {
                            try Task.checkCancellation()
                            if (try await web.evaluateJavaScript("document.fonts.status")) as? String == "loaded" { break }
                            try await Task.sleep(for: .milliseconds(50))
                        }
                        try await Task.sleep(for: .milliseconds(35))
                        try Task.checkCancellation()
                        if let y = parent.session.scrollY {
                            _ = try await web.callAsyncJavaScript("window.scrollTo(0, y)", arguments: ["y": y], in: nil, contentWorld: .page)
                            try await Task.sleep(for: .milliseconds(35))
                        } else if !parent.anchor.isEmpty {
                            _ = try await web.callAsyncJavaScript("VaultReader.scrollToAnchor(anchor)", arguments: ["anchor": parent.anchor], in: nil, contentWorld: .page)
                        }
                        renderedOnce = true
                        web.accessibilityIdentifier = "reader-ready"
                        parent.state.recordHomeRendered(parent.path)
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
        func scrollViewDidScroll(_ scrollView: UIScrollView) { if renderedOnce && scrollView.window != nil { parent.session.scrollY = scrollView.contentOffset.y } }
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
