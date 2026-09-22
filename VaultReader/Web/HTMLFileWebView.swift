import SwiftUI
import WebKit
import VaultCore

/// Stable across content updates, distinct across repositories, branches and file paths.
struct HTMLLocation {
    let host: String
    let url: URL
    init(config: RepositoryConfig, path: String) {
        host = "html-" + MetaStore.key(config.identity + "\0" + config.branch + "\0" + path)
        url = URL(string: "vault://" + host + "/")!.appendingPathComponent(path)
    }
    func path(for url: URL) -> String? {
        guard url.scheme == "vault", url.host == host else { return nil }
        let path = String(url.path.dropFirst())
        return !path.isEmpty && VaultIndex.normalized(path) == path ? path : nil
    }
}

@MainActor final class HTMLSchemeHandler: NSObject, WKURLSchemeHandler {
    let location: HTMLLocation
    let read: @MainActor (String) async throws -> Data
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    init(location: HTMLLocation, read: @escaping @MainActor (String) async throws -> Data) { self.location = location; self.read = read }
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        tasks[id] = Task {
            defer { tasks.removeValue(forKey: id) }
            do {
                guard let url = task.request.url, let path = location.path(for: url) else { throw VaultError.missing }
                let data = try await read(path)
                try Task.checkCancellation()
                let mime = SchemeHandler.mime(path)
                task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime.hasPrefix("text/") || mime.contains("javascript") ? "utf-8" : nil))
                task.didReceive(data); task.didFinish()
            } catch { if !Task.isCancelled { task.didFailWithError(error) } }
        }
    }
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) { tasks.removeValue(forKey: ObjectIdentifier(task))?.cancel() }
}

struct HTMLFileWebView: UIViewRepresentable {
    let state: AppState
    let session: ReaderSession
    let path: String
    let onExternal: (URL) -> Void
    let onFile: (String) -> Void
    let onError: (String) -> Void
    // Dedicated persistent store; Markdown always uses an ephemeral store.
    static let storeID = UUID(uuidString: "909762B0-8740-4B06-A86A-119DFAD84737")!
    @MainActor static func configuration(location: HTMLLocation, read: @escaping @MainActor (String) async throws -> Data) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        config.setURLSchemeHandler(HTMLSchemeHandler(location: location, read: read), forURLScheme: "vault")
        // No user scripts, message handlers, VaultHost or credentials.
        return config
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WebViewContainer {
        let container = WebViewContainer(), coordinator = context.coordinator
        session.container = container
        container.create = { [weak coordinator] in
            guard let coordinator else { return nil }
            let location = HTMLLocation(config: state.config, path: path)
            let web = WKWebView(frame: .zero, configuration: Self.configuration(location: location, read: { try await state.file($0) }))
            web.navigationDelegate = coordinator; web.uiDelegate = coordinator
            #if DEBUG
            ReaderWebViewRegistry.views.add(web)
            #endif
            web.load(URLRequest(url: location.url)); return web
        }
        container.mount(); return container
    }
    func updateUIView(_ container: WebViewContainer, context: Context) { context.coordinator.parent = self }
    static func dismantleUIView(_ container: WebViewContainer, coordinator: Coordinator) { container.releaseWebView(); container.create = nil }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: HTMLFileWebView
        init(_ parent: HTMLFileWebView) { self.parent = parent }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            let location = HTMLLocation(config: parent.state.config, path: parent.path)
            if let path = location.path(for: url), path == parent.path, action.targetFrame?.isMainFrame != false {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                // Only explicit user links can open another native screen/browser.
                if action.navigationType == .linkActivated {
                    if let path = location.path(for: url), parent.state.index.files[path] != nil { parent.onFile(path) }
                    else if ["https", "http"].contains(url.scheme ?? "") { parent.onExternal(url) }
                }
            }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { parent.onError(error.localizedDescription) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { parent.onError(error.localizedDescription) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
    }
}
struct HTMLReaderView: View {
    let state: AppState
    let path: String
    let navigate: (String) -> Void
    @State private var readerSession = ReaderSession()
    @State private var external: PreviewItem?
    @State private var error: String?
    @State private var attempt = 0
    var body: some View {
        Group {
            if let error {
                ContentUnavailableView { Label("无法打开阅读器", systemImage: "doc") } description: { Text(error) } actions: { Button("重试") { self.error = nil; attempt += 1 } }
            } else {
                HTMLFileWebView(state: state, session: readerSession, path: path, onExternal: { external = PreviewItem(url: $0) }, onFile: navigate, onError: { error = $0 }).id(attempt)
            }
        }
        .navigationTitle((path as NSString).lastPathComponent).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $external) { SafariView(url: $0.url) }
        .onAppear { readerSession.resume() }.onDisappear { readerSession.suspend() }
    }
}
