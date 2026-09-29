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
    var root = NoteRoute(path: "长文.md")
    var body: some View {
        NavigationStack(path: $probe.path) {
            NoteView(state: state, route: root, navigate: { probe.path.append($0) }, readingBook: root.reading)
                .navigationDestination(for: ReaderRoute.self) { route in
                    if case .note(let note) = route { NoteView(state: state, route: note, navigate: { probe.path.append($0) }) }
                }
        }
    }
}
private struct BookProbe: View {
    let state: AppState
    var body: some View {
        NavigationStack { NoteView(state: state, route: NoteRoute(path: "长文.md", reading: true), navigate: { _ in }, readingBook: true) }
    }
}
final class M1bWebTests: XCTestCase {
    @MainActor func testFailedReflowReloadsAndRestoresReadingPosition() async throws {
        let state = AppState(); try await state.startDemoForTesting()
        state.reading.clearDemoProgress()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: BookProbe(state: state)); window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; state.stopPrefetch() }
        func reader() -> WKWebView? { ReaderWebViewRegistry.views.allObjects.first { $0.window === window } }
        func settle() async throws -> WKWebView {
            for _ in 0..<100 {
                if let web = reader(), web.accessibilityIdentifier == "reader-ready", web.scrollView.contentSize.height > 3000,
                   (try? await web.evaluateJavaScript("typeof VaultReader === 'object' && document.querySelector('h2') !== null")) as? Bool == true { return web }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw XCTSkip("Reader failed to appear")
        }
        func waitForReload(_ web: WKWebView) async throws {
            for _ in 0..<50 where web.accessibilityIdentifier == "reader-ready" { try await Task.sleep(for: .milliseconds(100)) }
            XCTAssertNotEqual(web.accessibilityIdentifier, "reader-ready", "the page was reloaded")
        }
        var web = try await settle()
        web.scrollView.setContentOffset(CGPoint(x: 0, y: 2400), animated: false)
        try await Task.sleep(for: .milliseconds(600))
        let saved = try XCTUnwrap(state.reading.history.records["长文.md"]?.location)
        XCTAssertGreaterThan(saved.fraction, 0.05)
        // A reflow that throws (as iOS 26.6 did) must not leave a broken page behind an alert.
        let coordinator = try XCTUnwrap(web.navigationDelegate as? RendererWebView.Coordinator)
        _ = try await web.evaluateJavaScript("delete window.VaultReader; true")
        coordinator.lastRenderKey = ""; coordinator.update()
        try await waitForReload(web)
        web = try await settle()
        for _ in 0..<30 where web.scrollView.contentOffset.y < 2000 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(web.scrollView.contentOffset.y, 2400, accuracy: 120, "reloaded at the saved reading position")
        XCTAssertEqual(state.reading.history.records["长文.md"]?.location.heading, saved.heading)
        XCTAssertEqual(coordinator.recoveries, 0, "a successful reload resets the retry budget")
        // WebKit may also discard the page process; that path restores the same way.
        let kill = NSSelectorFromString("_killWebContentProcess")
        guard web.responds(to: kill) else { return }
        web.perform(kill)
        try await waitForReload(web)
        web = try await settle()
        for _ in 0..<30 where web.scrollView.contentOffset.y < 2000 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(web.scrollView.contentOffset.y, 2400, accuracy: 120)
    }
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

private actor SearchPrefetchSource: RepositorySource {
    let data: [String: Data]
    private(set) var requested: [String] = []
    init(_ data: [String: Data]) { self.data = data }
    func branch(etag: String?) async throws -> BranchSnapshot? { nil }
    func tree(sha: String) async throws -> GitTree { throw VaultError.missing }
    func blob(_ entry: TreeEntry, progress: (@Sendable (Double) -> Void)?) async throws -> Data {
        requested.append(entry.path)
        guard let value = data[entry.path] else { throw VaultError.missing }
        return value
    }
    func recent(etag: String?) async throws -> RecentSnapshot? { nil }
    func commitFiles(sha: String) async throws -> CommitFiles { throw VaultError.missing }
}

extension M1bWebTests {
    @MainActor func testSearchPrefetchContinuesPastMissingAndInvalidText() async throws {
        let id = UUID().uuidString
        let missing = TreeEntry(path: "a-\(id).md", sha: BlobStore.hash(Data(id.utf8)), size: 1)
        let invalidData = Data([0xff, 0xfe, 0xfd]), validData = Data("# \(id)\n\n后续正文能搜到".utf8)
        let invalid = TreeEntry(path: "b-\(id).md", sha: BlobStore.hash(invalidData), size: invalidData.count)
        let valid = TreeEntry(path: "c-\(id).md", sha: BlobStore.hash(validData), size: validData.count)
        let source = SearchPrefetchSource([invalid.path: invalidData, valid.path: validData])
        let state = AppState(); try await state.startDemoForTesting(source: source)
        state.stopPrefetch(); state.index = VaultIndex([missing, invalid, valid]); state.treeSHA = id
        state.startPrefetch()
        defer { state.stopPrefetch() }
        for _ in 0..<100 where state.isPrefetching { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertFalse(state.isPrefetching)
        XCTAssertEqual(state.prefetchTotal, 2); XCTAssertEqual(state.prefetchCompleted, 1)
        XCTAssertEqual(state.searchCoverage.metadataOnly, 1, "Invalid UTF-8 keeps metadata instead of remaining in the retry queue")
        XCTAssertNotNil(state.prefetchError)
        let requests = await source.requested
        XCTAssertTrue(requests.contains(missing.path)); XCTAssertTrue(requests.contains(valid.path))
        let hits = try await state.searchIndex.search("后续 正文")
        XCTAssertEqual(hits.map(\.path), [valid.path])
        XCTAssertGreaterThan(state.searchRevision, 0)
    }
    @MainActor func testSearchOpensAtMatchAndPreservesSubsequentReadingPosition() async throws {
        let state = AppState(); try await state.startDemoForTesting(); state.stopPrefetch()
        let path = "search-location.md", phrase = "独特定位文字"
        let markdown = "# Search fixture\n\n" + (1...60).map { "## Section \($0)\n\n" + ($0 == 40 ? "**独特**定位文字 CAFÉ。" : "Synthetic paragraph for scrolling. Read this paragraph slowly.") + "\n\n" }.joined()
        let data = Data(markdown.utf8), entry = TreeEntry(path: path, sha: BlobStore.hash(data), size: data.count)
        try await state.blobs?.put(data, entry: entry)
        state.index = VaultIndex(state.index.entries + [entry]); state.treeSHA += "-search"
        var saved = ReadingRecord(path: path, title: "Search fixture", kind: .markdown)
        saved.location = ReadingLocation(heading: nil, withinHeading: 0, fraction: 0.05)
        state.reading.record(saved, immediately: true)
        let probe = NavigationProbe(), scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ProbeStack(state: state, probe: probe, root: NoteRoute(path: path, reading: true, searchTerms: [phrase, "cafe"])))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; state.stopPrefetch() }
        func settle(_ expected: String) async throws -> WKWebView {
            for _ in 0..<150 {
                if let web = ReaderWebViewRegistry.views.allObjects.first(where: { $0.window === window && ($0.navigationDelegate as? RendererWebView.Coordinator)?.parent.path == expected }),
                   web.accessibilityIdentifier == "reader-ready" { return web }
                try await Task.sleep(for: .milliseconds(100))
            }
            let attached = ReaderWebViewRegistry.views.allObjects.map { web in
                "\((web.navigationDelegate as? RendererWebView.Coordinator)?.parent.path ?? "released") ready=\(web.accessibilityIdentifier ?? "no") attached=\(web.window === window)"
            }
            XCTFail("Search reader failed to appear at \(expected): \(attached)")
            throw VaultError.missing
        }
        var web = try await settle(path)
        XCTAssertGreaterThan(web.scrollView.contentOffset.y, 2500, "Search overrides the old book bookmark")
        let geometry = try await web.evaluateJavaScript("JSON.stringify({top:document.querySelector('mark.search-hit').getBoundingClientRect().top,height:innerHeight,text:[...document.querySelectorAll('mark.search-hit')].map(x=>x.textContent).join('')})")
        let json = try XCTUnwrap(geometry as? String)
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertGreaterThan(values["top"] as? Double ?? -1, 0)
        XCTAssertLessThan(values["top"] as? Double ?? 10000, values["height"] as? Double ?? 0)
        XCTAssertEqual(values["text"] as? String, phrase + "CAFÉ")
        let snapshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let shot = XCTAttachment(image: snapshot); shot.name = "search-located-in-book"; shot.lifetime = .keepAlways; add(shot)
        web.scrollView.setContentOffset(CGPoint(x: 0, y: 1800), animated: false)
        try await Task.sleep(for: .milliseconds(500))
        // Reflow does not reveal the first result again.
        let coordinator = try XCTUnwrap(web.navigationDelegate as? RendererWebView.Coordinator)
        coordinator.lastRenderKey = ""; coordinator.update()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(web.scrollView.contentOffset.y, 1800, accuracy: 25)
        probe.path.append(.note(NoteRoute(path: "长文.md")))
        try await Task.sleep(for: .milliseconds(400))
        _ = try await settle("长文.md")
        probe.path.removeAll()
        try await Task.sleep(for: .milliseconds(500))
        web = try await settle(path)
        for _ in 0..<30 where abs(web.scrollView.contentOffset.y - 1800) > 25 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(web.scrollView.contentOffset.y, 1800, accuracy: 25, "Returning restores the new position, not the first hit")
        let restoredHighlights = try await web.evaluateJavaScript("document.querySelectorAll('mark.search-hit').length")
        XCTAssertEqual(restoredHighlights as? Int, 3)
    }
}

extension M1bWebTests {
    @MainActor func testPersistentSearchRestoresWithoutParsingAfterStateRecreationAndVaultSwitch() async throws {
        func prepared(_ state: AppState) async throws {
            for _ in 0..<200 where state.isPrefetching { try await Task.sleep(for: .milliseconds(25)) }
            XCTAssertFalse(state.isPrefetching)
            XCTAssertEqual(state.prefetchCompleted, state.prefetchTotal)
            XCTAssertGreaterThan(state.prefetchCompleted, 10)
            XCTAssertNil(state.prefetchError)
        }
        let first = AppState(); try await first.startDemoForTesting(); try await prepared(first)
        first.stopPrefetch()
        let expected = try await first.searchIndex.search("银杏 慢慢")
        let reopened = AppState(); try await reopened.startDemoForTesting()
        defer { reopened.stopPrefetch() }
        try await prepared(reopened)
        let stats = await reopened.searchIndex.diagnostics
        XCTAssertGreaterThan(stats.restoredDocuments, 10)
        XCTAssertEqual(stats.builtDocuments, 0, "Restart uses the persisted projection, without reparsing Markdown")
        XCTAssertEqual(stats.cacheWriteFailures, 0)
        let results = try await reopened.searchIndex.search("银杏 慢慢")
        XCTAssertEqual(results.map(\.path), expected.map(\.path)); XCTAssertEqual(results.map(\.snippet), expected.map(\.snippet))
        let original = reopened.config, other = try XCTUnwrap(reopened.library.repositories.first { $0.storageKey != original.storageKey })
        await reopened.selectRepository(other)
        for _ in 0..<200 where reopened.isPrefetching { try await Task.sleep(for: .milliseconds(25)) }
        let unrelated = try await reopened.searchIndex.search("慢慢")
        XCTAssertTrue(unrelated.isEmpty)
        await reopened.selectRepository(original); try await prepared(reopened)
        let switched = await reopened.searchIndex.diagnostics
        XCTAssertGreaterThan(switched.restoredDocuments, 10); XCTAssertEqual(switched.builtDocuments, 0)
        let restored = try await reopened.searchIndex.search("银杏 慢慢")
        XCTAssertEqual(restored.map(\.path), expected.map(\.path))
    }
}
