import UIKit
import WebKit
import VaultCore

/// SwiftUI can retain offscreen navigation views. Retain only this empty shell, not WebKit.
@MainActor final class ReaderSession {
    var scrollY: Double?
    var position: ReadingLocation?
    var onPosition: ((ReadingLocation) -> Void)?
    var onOutline: (([ReadingOutline]) -> Void)?
    var onSave: (() -> Void)?
    var sectionRequest: String?
    func go(to section: String) {
        guard let web = container?.web else { sectionRequest = section; return }
        sectionRequest = nil
        Task { _ = try? await web.callAsyncJavaScript("VaultReader.scrollToSection(id); return true", arguments: ["id": section], in: nil, contentWorld: .page) }
    }
    weak var container: WebViewContainer?
    func resume() { container?.mount() }
    func suspend() { container?.releaseWebView() }
}
@MainActor final class WebViewContainer: UIView {
    var web: WKWebView?
    var create: (() -> WKWebView?)?
    var beforeRelease: ((WKWebView) -> Void)?
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil && window != nil { releaseWebView() }
        super.willMove(toWindow: newWindow)
    }
    func mount() {
        guard web == nil, let next = create?() else { return }
        web = next; next.frame = bounds; next.autoresizingMask = [.flexibleWidth, .flexibleHeight]; addSubview(next)
    }
    func releaseWebView() {
        guard let web else { return }
        beforeRelease?(web)
        web.stopLoading(); web.configuration.userContentController.removeAllScriptMessageHandlers()
        web.navigationDelegate = nil; web.uiDelegate = nil; web.scrollView.delegate = nil
        web.removeFromSuperview(); self.web = nil
    }
}
