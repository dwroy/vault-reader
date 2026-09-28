import SwiftUI

enum AppDocument: String {
    case privacy = "PRIVACY", support = "SUPPORT"
    var title: String { self == .privacy ? L10n.text("Privacy Policy") : L10n.text("Help") }
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
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [L10n.text("This document could not be loaded. Please open the online version.")] }
        // Keep the reviewed policy wording intact. Other interfaces show the English document.
        let useChinese = L10n.language.hasPrefix("zh")
        let sections = text.components(separatedBy: document == .support ? "\n## English quick start\n" : "\n## English\n")
        let selected: String
        if sections.count == 2 {
            if useChinese { selected = sections[0] }
            else { selected = "# Vault Reader\n\n" + sections[1] }
        } else { selected = text }
        return selected.components(separatedBy: "\n\n").filter { !$0.isEmpty }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !L10n.language.hasPrefix("zh") && L10n.language != "en" {
                    Text(L10n.text("This document is available in English and Simplified Chinese."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    if paragraph.hasPrefix("# ") { Text(String(paragraph.dropFirst(2))).font(.title.bold()) }
                    else if paragraph.hasPrefix("## ") { Text(String(paragraph.dropFirst(3))).font(.title3.bold()) }
                    else { Text((try? AttributedString(markdown: paragraph)) ?? AttributedString(paragraph)).font(.body) }
                }
                .environment(\.layoutDirection, .leftToRight)
                Link(L10n.text("Online version"), destination: document.webURL)
                Link(L10n.text("Contact support"), destination: URL(string: "https://github.com/dwroy/vault-reader/issues")!)
            }.frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity).padding(24).textSelection(.enabled)
        }.navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
    }
}
