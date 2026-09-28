import SwiftUI

enum AppDocument: String {
    case privacy = "PRIVACY", support = "SUPPORT"
    var title: String { self == .privacy ? "隐私政策" : "使用帮助" }
    var webURL: URL { URL(string: "https://github.com/dwroy/vault-reader/blob/main/docs/\(rawValue).md")! }
}

/// The same reviewed Markdown ships in the app and is published on the support site.
struct AppDocumentView: View {
    let document: AppDocument
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))"
    }
    private var paragraphs: [String] {
        guard let url = Bundle.main.url(forResource: document.rawValue, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return ["文档暂时无法读取，请查看在线版本。"] }
        return text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    if paragraph.hasPrefix("# ") { Text(String(paragraph.dropFirst(2))).font(.title.bold()) }
                    else if paragraph.hasPrefix("## ") { Text(String(paragraph.dropFirst(3))).font(.title3.bold()) }
                    else { Text(LocalizedStringKey(paragraph)).font(.body) }
                }
                Link("查看在线版本 / Online version", destination: document.webURL)
                Link("联系支持 / Contact support", destination: URL(string: "https://github.com/dwroy/vault-reader/issues")!)
            }.frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity).padding(24).textSelection(.enabled)
        }.navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
    }
}
