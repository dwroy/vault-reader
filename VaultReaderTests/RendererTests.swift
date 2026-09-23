import XCTest
import WebKit
@testable import VaultReader

@MainActor private final class RendererPage: NSObject, WKNavigationDelegate {
    let view: WKWebView
    var continuation: CheckedContinuation<Void, Error>?
    var imageRequests = 0
    override init() {
        let configuration = WKWebViewConfiguration()
        let handler = SchemeHandler { path in
            guard path == "files/image.svg" else { throw NSError(domain: "test", code: 404) }
            return Data("<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20'><rect width='20' height='20' fill='green'/></svg>".utf8)
        }
        configuration.setURLSchemeHandler(handler, forURLScheme: "vault")
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 402, height: 874), configuration: configuration)
        super.init(); view.navigationDelegate = self
    }
    func load() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            view.load(URLRequest(url: URL(string: "vault://app/index.html")!))
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { continuation?.resume(); continuation = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { continuation?.resume(throwing: error); continuation = nil }
}
final class RendererTests: XCTestCase {
    @MainActor func testShareUsesCompleteRenderedBodyWithoutMetadata() async throws {
        let page = RendererPage(); try await page.load()
        let markdown = """
        ---
        private_property: do-not-share-this
        tags: [private-tag]
        ---
        # 分享标题

        这是 **正文**，包含 [链接文字](https://example.com) 和 [[child|双链文字]]。

        %%隐藏备注%%
        <details><summary>补充说明</summary><p>折叠的正文也要分享。</p></details>

        ```swift
        let answer = 42
        ```

        ![图片说明](https://example.com/image.png)

        最后一段。
        """
        _ = try await page.view.callAsyncJavaScript("VaultReader.render(markdown, 'share.md', 1, 'light'); return true", arguments: ["markdown": markdown], in: nil, contentWorld: .page)
        let before = try await page.view.evaluateJavaScript("document.body.innerHTML") as? String
        let content = try await NoteShareContent.read(from: page.view)
        for expected in ["分享标题", "这是 正文", "链接文字", "双链文字", "折叠的正文也要分享。", "let answer = 42", "图片说明", "最后一段。"] {
            XCTAssertTrue(content.text.contains(expected), content.text)
        }
        for excluded in ["do-not-share-this", "private-tag", "隐藏备注", "vault://", "**", "```", "<details>"] {
            XCTAssertFalse(content.text.contains(excluded), content.text)
        }
        XCTAssertTrue(content.text.contains("\n"), "Paragraph boundaries survive text sharing")
        let after = try await page.view.evaluateJavaScript("document.body.innerHTML") as? String
        XCTAssertEqual(before, after, "Sharing does not change the reading page")
        _ = try await page.view.callAsyncJavaScript("VaultReader.render('---\\nsecret: hidden\\n---\\n', 'empty.md', 1, 'light'); return true", arguments: [:], in: nil, contentWorld: .page)
        do { _ = try await NoteShareContent.read(from: page.view); XCTFail("Metadata-only notes must not be shared") }
        catch NoteShareContent.ShareError.empty {}
    }
    @MainActor func testSharedBundleRendersAndSanitizesMarkdown() async throws {
        let page = RendererPage(); try await page.load()
        let script = """
        VaultReader.setTree([{path:'README.md',type:'blob'},{path:'notes/child.md',type:'blob'},{path:'files/image.svg',type:'blob'}]);
        VaultReader.render(markdown,'README.md',1,'light');
        return {
          title:document.querySelector('h1').textContent,
          wiki:document.querySelector('a').getAttribute('href'),
          scripts:document.querySelectorAll('#content script, #content iframe').length,
          events:document.querySelectorAll('#content [onerror], #content [onclick]').length,
          dangerous:document.querySelectorAll('#content img[src^="http:"], #content img[src^="data:"]').length,
          tags:document.querySelector('.tags').textContent,
          anchor:document.querySelector('h2').id,
          image:document.querySelector('img[data-path]').getAttribute('src')
        };
        """
        let markdown = """
        ---
        tags: [阅读, test]
        ---
        # Hello
        [[notes/child|Read child]]
        ![[files/image.svg]]
        ##  Some   Title
        <script>window.compromised=true</script><iframe src="https://example.com"></iframe>
        <img src="http://example.com/a.png" onerror="alert(1)">
        <img src="data:image/svg+xml,x" onclick="alert(1)">
        """
        let result = try await page.view.callAsyncJavaScript(script, arguments: ["markdown": markdown], in: nil, contentWorld: .page) as! [String: Any]
        let fonts = try await page.view.evaluateJavaScript("JSON.stringify({html:getComputedStyle(document.documentElement).font,body:getComputedStyle(document.body).font,h1:getComputedStyle(document.querySelector('h1')).font,scale:getComputedStyle(document.documentElement).getPropertyValue('--font-scale')})")
        print("RENDER_FONT_PROBE", String(describing: fonts))
        print("RENDER_RESULT", result)
        XCTAssertEqual(result["title"] as? String, "Hello")
        XCTAssertEqual(result["wiki"] as? String, "vault://f/notes/child.md")
        XCTAssertEqual(result["scripts"] as? Int, 0); XCTAssertEqual(result["events"] as? Int, 0); XCTAssertEqual(result["dangerous"] as? Int, 0)
        XCTAssertEqual(result["tags"] as? String, "阅读test")
        XCTAssertEqual(result["anchor"] as? String, "some title")
        XCTAssertEqual(result["image"] as? String, "vault://file/files/image.svg")
    }
    @MainActor func testTreeRefreshReresolvesUnchangedMarkdown() async throws {
        let page = RendererPage(); try await page.load()
        let result = try await page.view.callAsyncJavaScript("""
        VaultReader.setTree([]); VaultReader.render('[[new]]','README.md',1,'light');
        const missing = document.querySelectorAll('.dead-link').length;
        VaultReader.setTree([{path:'new.md',type:'blob'}]); VaultReader.render('[[new]]','README.md',1,'light');
        return {missing, href:document.querySelector('a')?.getAttribute('href')};
        """, arguments: [:], in: nil, contentWorld: .page) as! [String: Any]
        XCTAssertEqual(result["missing"] as? Int, 1)
        XCTAssertEqual(result["href"] as? String, "vault://f/new.md")
    }
}
