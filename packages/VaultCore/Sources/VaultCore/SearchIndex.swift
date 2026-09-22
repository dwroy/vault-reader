import Foundation

public struct SearchHit: Sendable, Identifiable {
    public let path: String
    public let snippet: String?
    public var id: String { path }
}
/// Searches run off the UI executor; only text matching the current tree's SHA is visible.
public actor SearchIndex {
    private var entries: [TreeEntry] = []
    private var texts: [String: (sha: String, text: Data, folded: Data)] = [:]
    public init() {}
    public func update(_ entries: [TreeEntry]) {
        self.entries = entries.sorted { $0.path < $1.path }
        let current = Dictionary(entries.map { ($0.path, $0.sha) }, uniquingKeysWith: { a, _ in a })
        texts = texts.filter { current[$0.key] == $0.value.sha }
    }
    public func insert(_ text: String, for entry: TreeEntry) {
        guard entries.contains(where: { $0.path == entry.path && $0.sha == entry.sha }) else { return }
        texts[entry.path] = (entry.sha, Data(text.utf8), Data(Self.fold(text).utf8))
    }
    private static func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    public var count: Int { texts.count }
    public func search(_ query: String, fullText: Bool) throws -> [SearchHit] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let foldedQuery = Data(Self.fold(query).utf8), literalQuery = Data(query.utf8)
        var hits: [SearchHit] = []
        for entry in entries {
            try Task.checkCancellation()
            let nameMatch = entry.path.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            var snippet: String?
            if fullText, let document = texts[entry.path], let foldedMatch = document.folded.range(of: foldedQuery) {
                // Search UTF-8 bytes; normalize once on ingestion, never once per query/document.
                let exact = document.text.range(of: literalQuery)
                let bytes = exact == nil ? document.folded : document.text
                let match = exact ?? foldedMatch
                var start = max(0, match.lowerBound - 100), end = min(bytes.count, match.upperBound + 250)
                while start > 0 && bytes[start] & 0xc0 == 0x80 { start -= 1 }
                while end < bytes.count && bytes[end] & 0xc0 == 0x80 { end += 1 }
                snippet = (start == 0 ? "" : "…") + String(decoding: bytes[start..<end], as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
            }
            if nameMatch || snippet != nil { hits.append(SearchHit(path: entry.path, snippet: snippet)) }
        }
        return hits
    }
}
