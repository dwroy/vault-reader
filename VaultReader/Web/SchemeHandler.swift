import VaultCore
import Foundation
import WebKit
import UniformTypeIdentifiers

@MainActor
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    let read: @MainActor (String) async throws -> Data
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    init(read: @escaping @MainActor (String) async throws -> Data) { self.read = read }
    func webView(_ webView: WKWebView, start schemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(schemeTask)
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { tasks.removeValue(forKey: id) }
            do {
                guard let url = schemeTask.request.url else { throw VaultError.missing }
                let path = String(url.path.dropFirst())
                let data: Data, mime: String
                if url.host == "app" {
                    guard let normalized = VaultIndex.normalized(path), normalized == path,
                          let root = Bundle.main.url(forResource: "renderer", withExtension: nil) else { throw VaultError.missing }
                    data = try Data(contentsOf: root.appendingPathComponent(path))
                    mime = Self.mime(path)
                } else if url.host == "file" {
                    guard VaultIndex.normalized(path) == path else { throw VaultError.missing }
                    data = try await read(path); mime = Self.mime(path)
                } else { throw VaultError.missing }
                try Task.checkCancellation()
                guard tasks[id] != nil else { return }
                schemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime.hasPrefix("text/") || mime.contains("javascript") ? "utf-8" : nil))
                schemeTask.didReceive(data); schemeTask.didFinish()
            } catch {
                if !Task.isCancelled && tasks[id] != nil { schemeTask.didFailWithError(error) }
            }
        }
    }
    func webView(_ webView: WKWebView, stop schemeTask: any WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(schemeTask))?.cancel()
    }
    static func mime(_ path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "js": "application/javascript"
        case "css": "text/css"
        case "html", "htm": "text/html"
        case "svg": "image/svg+xml"
        case "md": "text/plain"
        default: UTType(filenameExtension: (path as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
