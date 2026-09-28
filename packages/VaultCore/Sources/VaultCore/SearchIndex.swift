import Foundation

public struct SearchQuery: Sendable {
    public let terms: [String]
    public init(_ query: String) {
        var seen = Set<String>()
        terms = query.split(whereSeparator: \.isWhitespace).map(String.init).filter {
            let folded = Self.fold($0)
            return !folded.isEmpty && seen.insert(folded).inserted
        }
    }
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    /// Original-string ranges, including case/diacritic matches, for native result highlighting.
    public static func ranges(in text: String, terms: [String]) -> [Range<String.Index>] {
        var matches: [Range<String.Index>] = []
        for term in terms where !term.isEmpty {
            var start = text.startIndex
            while start < text.endIndex, let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: start..<text.endIndex), !range.isEmpty {
                matches.append(range); start = range.upperBound
            }
        }
        var merged: [Range<String.Index>] = []
        for range in matches.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else { merged.append(range) }
        }
        return merged
    }
}

public struct SearchHit: Sendable, Identifiable {
    public let path: String
    public let sha: String
    public let snippet: String?
    /// Path-only hits do not move the reader's position.
    public let bodyTerms: [String]
    public var id: String { path }
}

/// Searches run off the UI executor; only text matching the current tree's SHA is visible.
public actor SearchIndex {
    private struct Entry {
        let file: TreeEntry
        let path: Data
        let name: String
        let stem: String
    }
    private struct Document {
        let sha: String
        let text: String
        let folded: Data
        let checkpoints: [(offset: Int, index: String.Index)]
        init(sha: String, text: String) {
            self.sha = sha; self.text = text
            var folded = Data(), checkpoints: [(Int, String.Index)] = [], start = text.startIndex
            // Sparse original-text checkpoints keep snippets faithful without rescanning a whole book.
            while start < text.endIndex {
                let end = text.index(start, offsetBy: 256, limitedBy: text.endIndex) ?? text.endIndex
                checkpoints.append((folded.count, start))
                folded.append(contentsOf: SearchQuery.fold(String(text[start..<end])).utf8); start = end
            }
            self.folded = folded; self.checkpoints = checkpoints
        }
        func checkpoint(after offset: Int) -> Int {
            var lower = 0, upper = checkpoints.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if checkpoints[middle].offset <= offset { lower = middle + 1 } else { upper = middle }
            }
            return lower
        }
    }
    private var entries: [Entry] = []
    private var current: [String: String] = [:]
    private var texts: [String: Document] = [:]
    public init() {}
    public func update(_ files: [TreeEntry]) {
        entries = files.map { Entry(file: $0, path: Data(SearchQuery.fold($0.path).utf8), name: SearchQuery.fold($0.name), stem: SearchQuery.fold(($0.name as NSString).deletingPathExtension)) }
        current = Dictionary(files.map { ($0.path, $0.sha) }, uniquingKeysWith: { a, _ in a })
        texts = texts.filter { current[$0.key] == $0.value.sha }
    }
    public func insert(_ markdown: String, for entry: TreeEntry) {
        guard current[entry.path] == entry.sha, texts[entry.path]?.sha != entry.sha else { return }
        let text = MarkdownSearchText.plain(markdown)
        texts[entry.path] = Document(sha: entry.sha, text: text)
    }
    public var count: Int { texts.count }
    public func search(_ query: String, fullText: Bool = true) throws -> [SearchHit] {
        let terms = SearchQuery(query).terms
        guard !terms.isEmpty else { return [] }
        let folded = terms.map(SearchQuery.fold), bytes = folded.map { Data($0.utf8) }
        let phrase = folded.joined(separator: " ")
        var hits: [(hit: SearchHit, rank: Int, nameMatches: Int)] = []
        for entry in entries {
            try Task.checkCancellation()
            let document = fullText ? texts[entry.file.path] : nil
            var bodyTerms: [String] = [], nameMatches = 0, matched = true
            var firstMatch: (range: Range<Int>, term: String)?
            for (i, term) in bytes.enumerated() {
                let bodyRange = document?.folded.range(of: term)
                guard bodyRange != nil || entry.path.range(of: term) != nil else { matched = false; break }
                if let bodyRange {
                    bodyTerms.append(terms[i])
                    if firstMatch == nil || bodyRange.lowerBound < firstMatch!.range.lowerBound { firstMatch = (bodyRange, terms[i]) }
                }
                if entry.name.contains(folded[i]) { nameMatches += 1 }
            }
            guard matched else { continue }
            // Exact name, name prefix, all name terms, partial name, body, then directory-only hits.
            let rank = entry.name == phrase || entry.stem == phrase ? 5 : entry.name.hasPrefix(phrase) ? 4 : nameMatches == terms.count ? 3 : nameMatches > 0 ? 2 : !bodyTerms.isEmpty ? 1 : 0
            let snippet = document.flatMap { document in firstMatch.flatMap { Self.snippet(document, match: $0.range, term: $0.term) } }
            hits.append((SearchHit(path: entry.file.path, sha: entry.file.sha, snippet: snippet, bodyTerms: bodyTerms), rank, nameMatches))
        }
        return hits.sorted {
            if $0.rank != $1.rank { return $0.rank > $1.rank }
            if $0.nameMatches != $1.nameMatches { return $0.nameMatches > $1.nameMatches }
            return $0.hit.path < $1.hit.path
        }.map(\.hit)
    }
    private static func snippet(_ document: Document, match folded: Range<Int>, term: String) -> String? {
        let text = document.text
        let lower = max(0, document.checkpoint(after: folded.lowerBound) - 1)
        let upper = document.checkpoint(after: folded.upperBound)
        let searchEnd = upper < document.checkpoints.count ? document.checkpoints[upper].index : text.endIndex
        guard let match = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: document.checkpoints[lower].index..<searchEnd) else { return nil }
        let start = text.index(match.lowerBound, offsetBy: -45, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: 110, limitedBy: text.endIndex) ?? text.endIndex
        return (start == text.startIndex ? "" : "…") + text[start..<end] + (end == text.endIndex ? "" : "…")
    }
}
