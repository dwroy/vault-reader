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
    /// Preparation counters contain no paths or text and help distinguish warm restore from rebuilding.
    public struct Diagnostics: Sendable {
        public fileprivate(set) var restoredDocuments = 0
        public fileprivate(set) var builtDocuments = 0
        public fileprivate(set) var cacheWriteFailures = 0
    }
    public private(set) var diagnostics = Diagnostics()
    private var cache: SearchTextCache?
    private var entries: [Entry] = []
    private var current: [String: String] = [:]
    // SHA keys also reuse prepared text after a rename or for multiple paths with identical contents.
    private var texts: [String: SearchDocument] = [:]
    private var references: [String: Int] = [:]
    public private(set) var count = 0
    public init(cacheDirectory: URL? = nil) { cache = cacheDirectory.map { SearchTextCache(root: $0) } }
    public func update(_ files: [TreeEntry]) {
        guard !Task.isCancelled else { return }
        entries = files.map { Entry(file: $0, path: Data(SearchQuery.fold($0.path).utf8), name: SearchQuery.fold($0.name), stem: SearchQuery.fold(($0.name as NSString).deletingPathExtension)) }
        current = Dictionary(files.map { ($0.path, $0.sha) }, uniquingKeysWith: { a, _ in a })
        references = Dictionary(files.filter(\.isMarkdown).map { ($0.sha, 1) }, uniquingKeysWith: +)
        texts = texts.filter { references[$0.key] != nil }
        count = texts.keys.reduce(0) { $0 + (references[$1] ?? 0) }
        cache?.prune(keeping: Set(references.keys))
    }
    /// Restore before opening a source blob. A miss is rebuilt through the ordinary ingestion path.
    public func restoreCachedText(for entry: TreeEntry) -> Bool {
        guard !Task.isCancelled, entry.isMarkdown, current[entry.path] == entry.sha else { return false }
        if texts[entry.sha] != nil { return true }
        guard let document = cache?.load(sha: entry.sha), !Task.isCancelled else { return false }
        texts[entry.sha] = document; count += references[entry.sha] ?? 0; diagnostics.restoredDocuments += 1
        return true
    }
    public func insert(_ markdown: String, for entry: TreeEntry) {
        guard !Task.isCancelled, entry.isMarkdown, current[entry.path] == entry.sha, texts[entry.sha] == nil else { return }
        let document = SearchDocument(text: MarkdownSearchText.plain(markdown))
        guard !Task.isCancelled else { return }
        texts[entry.sha] = document; count += references[entry.sha] ?? 0; diagnostics.builtDocuments += 1
        do { try cache?.save(document, sha: entry.sha) }
        catch { diagnostics.cacheWriteFailures += 1 } // Search stays available even if derived-cache storage fails.
    }
    public func search(_ query: String, fullText: Bool = true) throws -> [SearchHit] {
        let terms = SearchQuery(query).terms
        guard !terms.isEmpty else { return [] }
        let folded = terms.map(SearchQuery.fold), bytes = folded.map { Data($0.utf8) }
        let phrase = folded.joined(separator: " ")
        var hits: [(hit: SearchHit, rank: Int, nameMatches: Int)] = []
        for entry in entries {
            try Task.checkCancellation()
            let document = fullText && entry.file.isMarkdown ? texts[entry.file.sha] : nil
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
    private static func snippet(_ document: SearchDocument, match folded: Range<Int>, term: String) -> String? {
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
