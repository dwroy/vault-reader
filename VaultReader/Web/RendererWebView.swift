import SwiftUI
import WebKit

struct RendererWebView: UIViewRepresentable {
    let state: AppState
    let markdown: String
    let path: String
    let anchor: String
    let onOpen: (URL) -> Void
    let onPreview: (String) -> Void
    let onError: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
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
        for name in ["open", "preview", "height"] { config.userContentController.add(context.coordinator, name: name) }
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false; web.backgroundColor = .clear
        web.navigationDelegate = context.coordinator
        web.scrollView.delegate = context.coordinator
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresh
        web.load(URLRequest(url: URL(string: "vault://app/index.html")!))
        context.coordinator.web = web
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update()
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.parent.state.scrollPositions[coordinator.parent.path] = web.scrollView.contentOffset.y
        web.stopLoading()
        web.configuration.userContentController.removeAllScriptMessageHandlers()
        web.navigationDelegate = nil; web.scrollView.delegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIScrollViewDelegate {
        var parent: RendererWebView
        weak var web: WKWebView?
        var loaded = false
        var lastRenderKey = ""
        var lastTree = ""
        var renderedOnce = false
        var updating = false
        init(_ parent: RendererWebView) { self.parent = parent }
        func update() {
            guard loaded, let web, !updating else { return }
            let scale = UIFontMetrics.default.scaledValue(for: 17) / 17
            let theme = parent.colorScheme == .dark ? "dark" : "light"
            let key = "\(parent.path)|\(parent.markdown)|\(parent.state.treeSHA)|\(scale)|\(theme)|\(parent.anchor)"
            guard key != lastRenderKey else { return }
            updating = true
            Task {
                defer { updating = false; if lastRenderKey == key { update() } }
                do {
                    if lastTree != parent.state.treeSHA {
                        let data = try JSONEncoder().encode(parent.state.index.entries)
                        let entries = try JSONSerialization.jsonObject(with: data)
                        _ = try await web.callAsyncJavaScript("if (VaultReader.version !== 1) throw new Error('Unsupported reader contract'); VaultReader.setTree(entries)", arguments: ["entries": entries], in: nil, contentWorld: .page)
                        lastTree = parent.state.treeSHA
                    }
                    _ = try await web.callAsyncJavaScript("return VaultReader.render(markdown, path, scale, theme)", arguments: ["markdown": parent.markdown, "path": parent.path, "scale": scale, "theme": theme], in: nil, contentWorld: .page)
                    if !renderedOnce {
                        if !parent.anchor.isEmpty {
                            _ = try await web.callAsyncJavaScript("VaultReader.scrollToAnchor(anchor)", arguments: ["anchor": parent.anchor], in: nil, contentWorld: .page)
                        } else if let y = parent.state.scrollPositions[parent.path] {
                            web.scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
                        }
                        renderedOnce = true
                    }
                    lastRenderKey = key
                } catch { parent.onError("排版加载失败：\(error.localizedDescription)") }
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
        func scrollViewDidScroll(_ scrollView: UIScrollView) { if renderedOnce { parent.state.scrollPositions[parent.path] = scrollView.contentOffset.y } }
        @objc func refresh(_ sender: UIRefreshControl) {
            Task { await parent.state.refresh(); sender.endRefreshing() }
        }
    }
}
