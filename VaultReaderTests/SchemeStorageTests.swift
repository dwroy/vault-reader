import XCTest
import WebKit
@testable import VaultReader

@MainActor
private final class ProbeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let data = Data("<!doctype html><html><body>Storage probe</body></html>".utf8)
        task.didReceive(URLResponse(url: task.request.url!, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
@MainActor
private final class LoadedPage: NSObject, WKNavigationDelegate {
    let view: WKWebView
    var continuation: CheckedContinuation<Void, Error>?
    override init() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(ProbeHandler(), forURLScheme: "vault")
        config.websiteDataStore = .default()
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 402, height: 874), configuration: config)
        super.init()
        view.navigationDelegate = self
    }
    func load(_ host: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            view.load(URLRequest(url: URL(string: "vault://\(host)/index.html")!))
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { continuation?.resume(); continuation = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { continuation?.resume(throwing: error); continuation = nil }
}
final class SchemeStorageTests: XCTestCase {
    @MainActor func testCustomSchemeStoragePersistsAndSeparatesHosts() async throws {
        let a = LoadedPage(), b = LoadedPage(), reopened = LoadedPage()
        try await a.load("html-probe-a")
        let marker = UUID().uuidString
        _ = try await a.view.evaluateJavaScript("localStorage.setItem('probe', '\(marker)')")
        try await b.load("html-probe-b")
        let other = try await b.view.evaluateJavaScript("localStorage.getItem('probe') || 'empty'") as? String
        XCTAssertEqual(other, "empty")
        try await reopened.load("html-probe-a")
        let restored = try await reopened.view.evaluateJavaScript("localStorage.getItem('probe')") as? String
        XCTAssertEqual(restored, marker)
        _ = try await a.view.evaluateJavaScript("localStorage.removeItem('probe')")
    }
}
