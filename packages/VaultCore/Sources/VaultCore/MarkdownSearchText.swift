import Foundation

/// Local text projection using Foundation's Markdown parser; code stays literal.
/// Common Obsidian syntax is projected to its displayed label before parsing.
enum MarkdownSearchText {
    private static let frontmatter = regex(#"\A\uFEFF?---\r?\n[\s\S]*?\r?\n---(?:\r?\n|\z)"#)
    private static let literalOrComment = regex(#"(?m)^ {0,3}(`{3,}|~{3,})[^\n]*(?:\n|\z)[\s\S]*?(?:^ {0,3}\1[ \t]*(?:\n|\z)|\z)|(`+)[^\n]*?\2(?!`)|%%[\s\S]*?%%|<!--[\s\S]*?-->|(?i:<(script|style|iframe|object|form|video|audio)\b[^>]*>[\s\S]*?</\3\s*>)"#)
    private static let comments = regex(#"%%[\s\S]*?%%|<!--[\s\S]*?-->"#)
    private static let forbiddenHTML = regex(#"(?i)<(script|style|iframe|object|form|video|audio)\b[^>]*>[\s\S]*?</\1\s*>"#)
    private static let blockHTML = regex(#"(?i)</?(?:p|div|br|li|h[1-6]|tr|pre|blockquote|details|summary)\b[^>]*>"#)
    private static let html = regex(#"</?[A-Za-z][A-Za-z0-9-]*(?:\s+[^>]*|\s*/?)>"#)
    private static let wiki = regex(#"!?\[\[([^\]\n]+)\]\]"#)
    private static let highlight = regex(#"==([^\n]+?)=="#)
    private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }
    private static func replace(_ regex: NSRegularExpression, in text: String, with value: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: value)
    }
    static func plain(_ markdown: String) -> String { (try? plainCancellable(markdown)) ?? "" }
    static func plainCancellable(_ markdown: String) throws -> String {
        try Task.checkCancellation()
        let source = replace(frontmatter, in: markdown, with: "")
        var prepared = "", cursor = source.startIndex
        for match in literalOrComment.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            try Task.checkCancellation()
            guard let range = Range(match.range, in: source) else { continue }
            prepared += try prose(String(source[cursor..<range.lowerBound]))
            if match.range(at: 1).location != NSNotFound || match.range(at: 2).location != NSNotFound { prepared += source[range] }
            cursor = range.upperBound
        }
        prepared += try prose(String(source[cursor...]))
        try Task.checkCancellation()
        guard let parsed = try? AttributedString(markdown: prepared) else { return prepared }
        try Task.checkCancellation()
        var result = "", block: Int?
        for run in parsed.runs {
            try Task.checkCancellation()
            let next = run.presentationIntent?.components.first?.identity
            if next != block, !result.isEmpty { result += "\n" }
            result += String(parsed[run.range].characters); block = next
        }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private static func prose(_ source: String) throws -> String {
        try Task.checkCancellation()
        var text = replace(comments, in: source, with: "")
        text = replace(forbiddenHTML, in: text, with: "")
        text = replace(blockHTML, in: text, with: "\n")
        text = replace(html, in: text, with: "")
        for match in wiki.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            try Task.checkCancellation()
            guard let range = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text) else { continue }
            let parts = text[inner].split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let label = String(parts.count > 1 && !parts[1].isEmpty ? parts[1] : parts[0])
            let escaped = label.reduce(into: "") { value, char in
                if #"\`*_{}[]<>#"#.contains(char) { value += "\\" }; value.append(char)
            }
            text.replaceSubrange(range, with: escaped)
        }
        return replace(highlight, in: text, with: "$1")
    }
}
