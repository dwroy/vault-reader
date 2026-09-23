import SwiftUI
import WebKit

struct NoteShareContent: Identifiable {
    let id = UUID()
    let text: String

    /// Read the sanitized article, without frontmatter, navigation or repository credentials.
    @MainActor static func read(from web: WKWebView) async throws -> NoteShareContent {
        let value = try await web.evaluateJavaScript("""
        (() => {
            const content = document.getElementById('content');
            if (!content) return '';
            const copy = content.cloneNode(true);
            copy.removeAttribute('id');
            copy.querySelectorAll(':scope > .tags, :scope > .properties').forEach(node => node.remove());
            copy.querySelectorAll('details').forEach(node => node.open = true);
            copy.querySelectorAll('img').forEach(node => node.replaceWith(document.createTextNode(node.alt || '')));
            copy.style.cssText = 'position:fixed;left:-100000px;top:0;width:800px;pointer-events:none';
            copy.setAttribute('aria-hidden', 'true');
            document.body.append(copy);
            try { return copy.innerText; } finally { copy.remove(); }
        })()
        """)
        let text = (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ShareError.empty }
        return NoteShareContent(text: text)
    }

    enum ShareError: LocalizedError {
        case empty
        var errorDescription: String? { "这篇文章没有可分享的正文，请确认文章已加载完成。" }
    }
}

struct NoteShareSheet: UIViewControllerRepresentable {
    let content: NoteShareContent
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [content.text], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
