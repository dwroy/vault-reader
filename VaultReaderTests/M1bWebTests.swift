import XCTest
import WebKit
import SwiftUI
import Observation
import VaultCore
@testable import VaultReader

@MainActor private final class HTMLTestPage: NSObject, WKNavigationDelegate {
    let web: WKWebView
    let location: HTMLLocation
    var continuation: CheckedContinuation<Void, Error>?
    init(config: RepositoryConfig, path: String) {
        location = HTMLLocation(config: config, path: path)
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 402, height: 874), configuration: HTMLFileWebView.configuration(location: location) { _ in Data(AppState.demoHTML.utf8) })
        super.init(); web.navigationDelegate = self
    }
    func load() async throws {
        try await withCheckedThrowingContinuation { continuation in self.continuation = continuation; web.load(URLRequest(url: location.url)) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { continuation?.resume(); continuation = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { continuation?.resume(throwing: error); continuation = nil }
}
@MainActor @Observable private final class NavigationProbe { var path: [ReaderRoute] = [] }
private struct ProbeStack: View {
    let state: AppState
    @Bindable var probe: NavigationProbe
    var body: some View {
        NavigationStack(path: $probe.path) {
            NoteView(state: state, route: NoteRoute(path: "长文.md"), navigate: { probe.path.append($0) })
                .navigationDestination(for: ReaderRoute.self) { route in
                    if case .note(let note) = route { NoteView(state: state, route: note, navigate: { probe.path.append($0) }) }
                }
        }
    }
}
final class M1bWebTests: XCTestCase {
    @MainActor func testHTMLProductionStoreHasNoBridgeAndSeparatesRepositoriesAndPaths() async throws {
        var config = RepositoryConfig(); config.owner = "test"; config.repo = UUID().uuidString
        let a = HTMLTestPage(config: config, path: "books/one.html"), b = HTMLTestPage(config: config, path: "books/two.html")
        var other = config; other.repo += "-other"
        let c = HTMLTestPage(config: other, path: "books/one.html")
        try await a.load(); try await b.load(); try await c.load()
        _ = try await a.web.evaluateJavaScript("localStorage.setItem('page','7')")
        let bValue = try await b.web.evaluateJavaScript("localStorage.getItem('page')") as? String
        let cValue = try await c.web.evaluateJavaScript("localStorage.getItem('page')") as? String
        XCTAssertEqual(bValue, "1"); XCTAssertEqual(cValue, "1")
        let reopened = HTMLTestPage(config: config, path: "books/one.html"); try await reopened.load()
        let saved = try await reopened.web.evaluateJavaScript("localStorage.getItem('page')") as? String
        XCTAssertEqual(saved, "7")
        let bridge = try await a.web.evaluateJavaScript("typeof VaultHost") as? String
        XCTAssertEqual(bridge, "undefined"); XCTAssertTrue(a.web.configuration.userContentController.userScripts.isEmpty)
        XCTAssertNil(a.location.path(for: URL(string: "vault://file/private.md")!))
        XCTAssertNil(a.location.path(for: URL(string: "vault://app/index.html")!))
        XCTAssertNil(a.location.path(for: URL(string: "vault://" + a.location.host + "/%2e%2e/private.md")!))
        let sibling = a.location.url.deletingLastPathComponent().appendingPathComponent("image.svg")
        XCTAssertEqual(a.location.path(for: sibling), "books/image.svg")
    }
    @MainActor func testCachedMarkdownPrefetchResumesAndDropsDeletedText() async throws {
        let state = AppState(); try await state.startDemoForTesting()
        state.stopPrefetch(); state.startPrefetch()
        for _ in 0..<100 where state.isPrefetching { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertEqual(state.prefetchCompleted, state.prefetchTotal)
        XCTAssertGreaterThan(state.prefetchCompleted, 10)
        let found = try await state.searchIndex.search("银杏", fullText: true)
        XCTAssertEqual(found.map(\.path), ["长文.md"])
        state.index = VaultIndex(state.index.entries.filter { $0.path != "长文.md" })
        state.startPrefetch()
        for _ in 0..<100 where state.isPrefetching { try await Task.sleep(for: .milliseconds(30)) }
        let deleted = try await state.searchIndex.search("银杏", fullText: true)
        XCTAssertTrue(deleted.isEmpty); XCTAssertNil(state.prefetchError)
    }
    @MainActor func testRepositorySwitchSeparatesIdenticalPathsAndSearch() async throws {
        let state = AppState(); try await state.startDemoForTesting()
        let first = state.config, second = try XCTUnwrap(state.library.repositories.last)
        await state.selectRepository(second)
        XCTAssertEqual(state.config.repo, "synthetic-other")
        XCTAssertEqual(state.index.entries.count, 1)
        let other = String(decoding: try await state.file("README.md"), as: UTF8.self)
        XCTAssertTrue(other.contains("第二个知识库"))
        XCTAssertTrue(state.recent.isEmpty)
        for _ in 0..<100 where state.isPrefetching { try await Task.sleep(for: .milliseconds(20)) }
        let hits = try await state.searchIndex.search("公园", fullText: true)
        XCTAssertTrue(hits.isEmpty)
        await state.selectRepository(first)
        let restored = String(decoding: try await state.file("README.md"), as: UTF8.self)
        XCTAssertTrue(restored.contains("我的知识库")); XCTAssertEqual(state.recent.count, 30)
        state.stopPrefetch()
    }
    @MainActor func testTwelveLevelNavigationReleasesWebViewsAndRestoresScroll() async throws {
        let state = AppState(); try await state.startDemoForTesting()
        let probe = NavigationProbe()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ProbeStack(state: state, probe: probe)); window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; state.stopPrefetch() }
        func visibleWeb() -> WKWebView? {
            let expected: String
            if case .note(let note) = probe.path.last { expected = note.path } else { expected = "长文.md" }
            return ReaderWebViewRegistry.views.allObjects.first {
                $0.window === window && ($0.navigationDelegate as? RendererWebView.Coordinator)?.parent.path == expected
            }
        }
        func settle() async throws {
            for _ in 0..<100 {
                if let web = visibleWeb(), web.accessibilityIdentifier == "reader-ready", web.scrollView.contentSize.height > 1500,
                   (try? await web.evaluateJavaScript("document.querySelector('h1') !== null")) as? Bool == true { return }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTFail("Reader failed to appear")
        }
        try await settle()
        let originalSession = try XCTUnwrap((visibleWeb()?.navigationDelegate as? RendererWebView.Coordinator)?.parent.session)
        try XCTUnwrap(visibleWeb()).scrollView.setContentOffset(CGPoint(x: 0, y: 700), animated: false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(try XCTUnwrap(visibleWeb()).scrollView.contentOffset.y, 700, accuracy: 8)
        // The test itself must not retain a WKWebView while checking lifetime.
        for n in 1...12 {
            probe.path.append(.note(NoteRoute(path: "深读/第 \(n) 页.md")))
            try await Task.sleep(for: .milliseconds(400)); try await settle()
            XCTAssertLessThanOrEqual(ReaderWebViewRegistry.views.allObjects.count, 3, "WebViews grew at depth \(n)")
        }
        probe.path.removeAll()
        try await Task.sleep(for: .milliseconds(500)); try await settle()
        let restored = try XCTUnwrap(visibleWeb())
        for _ in 0..<30 where restored.scrollView.contentOffset.y < 650 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue((restored.navigationDelegate as? RendererWebView.Coordinator)?.parent.session === originalSession)
        XCTAssertEqual(restored.scrollView.contentOffset.y, 700, accuracy: 8)
        XCTAssertLessThanOrEqual(ReaderWebViewRegistry.views.allObjects.count, 3)
    }
}
