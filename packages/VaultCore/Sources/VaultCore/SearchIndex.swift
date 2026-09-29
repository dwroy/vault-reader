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
    public let bodyTerms: [String]
    public let metadata: SearchFileMetadata
    public let metadataOnlyReason: SearchExclusion?
    public var id: String { path }
}
public struct SearchResults: Sendable {
    public let hits: [SearchHit]
    public let total: Int
}
/// Owns small state transitions and immutable snapshots. Expensive preparation and queries run elsewhere.
public actor SearchIndex {
    private struct Entry: Sendable {
        let file: TreeEntry
        let path: Data
        let name: String
        let stem: String
        let metadata: SearchFileMetadata
        let metadataText: Data
        var exclusion: SearchExclusion?
    }
    public struct Diagnostics: Sendable {
        public fileprivate(set) var restoredDocuments = 0
        public fileprivate(set) var builtDocuments = 0
        public fileprivate(set) var cacheWriteFailures = 0
    }
    public private(set) var diagnostics = Diagnostics()
    public private(set) var coverage = SearchCoverage()
    public private(set) var profile = VaultContentProfile([])
    public var count: Int { coverage.indexed }
    public nonisolated let limits: SearchLimits
    private let worker: SearchPreparationWorker
    private var revision = 0
    private var capacityReached = false
    private var entries: [Entry] = []
    private var current: [String: TreeEntry] = [:]
    private var texts: [String: SearchDocument] = [:]
    private var references: [String: Int] = [:]
    private var exclusions: [String: SearchExclusion] = [:]

    public init(cacheDirectory: URL? = nil, limits: SearchLimits = SearchLimits()) {
        self.limits = limits; worker = SearchPreparationWorker(cacheDirectory: cacheDirectory)
    }
    private nonisolated static func detached<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated) { try autoreleasepool(invoking: operation) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    public func update(_ files: [TreeEntry], preferredPath: String = "") async {
        guard !Task.isCancelled else { return }
        revision += 1
        let expected = revision, limits = limits
        guard let result = try? await Self.detached({
            var entries = try files.map { file -> Entry in
                try Task.checkCancellation()
                let metadata = SearchFileMetadata(file)
                return Entry(file: file, path: Data(SearchQuery.fold(file.path).utf8), name: SearchQuery.fold(file.name), stem: SearchQuery.fold((file.name as NSString).deletingPathExtension), metadata: metadata, metadataText: Data(metadata.terms.utf8), exclusion: file.searchExclusion(limits: limits))
            }
            // Bound body work before any cache reads/downloads, including files whose sizes are unknown.
            let candidates = entries.indices.filter { entries[$0].exclusion == nil }.sorted {
                let a = entries[$0].file.path, b = entries[$1].file.path
                if (a == preferredPath) != (b == preferredPath) { return a == preferredPath }
                return a < b
            }
            var planned = Set<String>()
            for i in candidates {
                try Task.checkCancellation()
                guard let key = entries[i].file.searchDocumentKey else { continue }
                if planned.contains(key) { continue }
                if planned.count < limits.documentCount { planned.insert(key) } else { entries[i].exclusion = .memoryBudget }
            }
            let current = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
            let references = Dictionary(entries.filter { $0.exclusion == nil }.compactMap { $0.file.searchDocumentKey.map { ($0, 1) } }, uniquingKeysWith: +)
            var coverage = SearchCoverage()
            for entry in entries {
                try Task.checkCancellation()
                if let reason = entry.exclusion {
                    coverage.metadataOnly += 1
                    if reason == .tooLarge { coverage.oversized += 1 }
                    if reason == .memoryBudget { coverage.limited += 1 }
                } else { coverage.pending += 1 }
            }
            return (entries, VaultContentProfile(files), current, references, coverage)
        }), expected == revision, !Task.isCancelled else { return }
        let prepared = result.0
        entries = prepared; profile = result.1
        current = result.2; references = result.3; capacityReached = false
        texts = texts.filter { references[$0.key] != nil }
        exclusions = exclusions.filter { references[$0.key] != nil && $0.value != .memoryBudget }
        coverage = result.4
        for (key, document) in texts { coverage.indexed += references[key] ?? 0; coverage.pending -= references[key] ?? 0; coverage.residentBytes += document.memoryCost }
        for (key, reason) in exclusions { let n = references[key] ?? 0; coverage.pending -= n; addMetadata(reason, count: n) }
        await worker.reconcile(files, limits: limits, revision: expected)
    }
    public func bodyCandidates(preferredPath: String = "") async -> [TreeEntry] {
        let snapshot = entries
        return (try? await Self.detached {
            try Task.checkCancellation()
            return snapshot.filter { $0.exclusion == nil }.map(\.file).sorted {
                if ($0.path == preferredPath) != ($1.path == preferredPath) { return $0.path == preferredPath }
                return $0.path < $1.path
            }
        }) ?? []
    }
    private func key(for entry: TreeEntry) -> String? {
        guard !Task.isCancelled, let actual = current[entry.path], actual.sha == entry.sha, actual.searchTextKind == entry.searchTextKind,
              actual.searchExclusion(limits: limits) == nil, entry.searchExclusion(limits: limits) == nil else { return nil }
        guard let key = entry.searchDocumentKey, references[key] != nil else { return nil }
        return key
    }
    public func needsBody(for entry: TreeEntry) -> Bool {
        guard let key = key(for: entry), texts[key] == nil, exclusions[key] == nil, !capacityReached else { return false }
        if texts.count + exclusions.count >= limits.documentCount || coverage.residentBytes >= limits.residentBytes {
            reachCapacity(); return false
        }
        return true
    }
    public func restoreCachedText(for entry: TreeEntry) async -> Bool {
        guard let key = key(for: entry) else { return false }
        if texts[key] != nil { return true }
        guard needsBody(for: entry) else { return false }
        let expected = revision
        let result = await worker.restore(entry, limits: limits, revision: expected)
        return publish(result, for: key, revision: expected)
    }
    public func insert(_ markdown: String, for entry: TreeEntry) async {
        guard needsBody(for: entry) else { return }
        guard markdown.utf8.count <= limits.sourceBytes else { await excludeOversized(entry); return }
        await insert(data: Data(markdown.utf8), for: entry)
    }
    public func insert(data: Data, for entry: TreeEntry) async {
        guard let key = key(for: entry), needsBody(for: entry) else { return }
        let expected = revision
        let result = await worker.prepare(data, entry: entry, limits: limits, revision: expected)
        _ = publish(result, for: key, revision: expected)
    }
    public func excludeOversized(_ entry: TreeEntry) async {
        guard let key = key(for: entry), texts[key] == nil else { return }
        let expected = revision
        exclude(key, reason: .tooLarge)
        _ = await worker.exclude(entry, reason: .tooLarge, limit: limits.sourceBytes, revision: expected)
    }
    private func publish(_ result: SearchPreparationResult, for key: String, revision expected: Int) -> Bool {
        guard expected == revision, !Task.isCancelled, references[key] != nil else { return false }
        if texts[key] != nil { return true }
        guard !capacityReached else { return false }
        if texts.count + exclusions.count >= limits.documentCount { reachCapacity(); return false }
        switch result {
        case .missing: return false
        case .excluded(let reason): exclude(key, reason: reason); return false
        case .document(let document, _, let restored, let failed):
            if failed { diagnostics.cacheWriteFailures += 1 }
            guard texts.count < limits.documentCount, document.memoryCost <= limits.residentBytes - coverage.residentBytes else {
                reachCapacity(); return false
            }
            guard exclusions[key] == nil else { return false }
            texts[key] = document
            let n = references[key] ?? 0; coverage.indexed += n; coverage.pending -= n; coverage.residentBytes += document.memoryCost
            if restored { diagnostics.restoredDocuments += 1 } else { diagnostics.builtDocuments += 1 }
            return true
        }
    }
    private func reachCapacity() {
        guard !capacityReached else { return }
        capacityReached = true
        coverage.metadataOnly += coverage.pending; coverage.limited += coverage.pending; coverage.pending = 0
    }
    private func exclude(_ key: String, reason: SearchExclusion) {
        guard texts[key] == nil, exclusions[key] == nil, !capacityReached else { return }
        exclusions[key] = reason
        let n = references[key] ?? 0; coverage.pending -= n; addMetadata(reason, count: n)
    }
    private func addMetadata(_ reason: SearchExclusion, count n: Int) {
        coverage.metadataOnly += n
        if reason == .tooLarge { coverage.oversized += n }
        if reason == .memoryBudget || reason == .contentLimit { coverage.limited += n }
    }
    public func search(_ query: String, fullText: Bool = true) async throws -> [SearchHit] {
        try await searchResults(query, fullText: fullText, limit: Int.max).hits
    }
    public func searchResults(_ query: String, fullText: Bool = true, limit: Int = 200, hideDotFiles: Bool = false) async throws -> SearchResults {
        let entries = entries, texts = texts, exclusions = exclusions, capacityReached = capacityReached
        return try await Self.detached { try Self.match(query, fullText: fullText, limit: max(1, limit), hideDotFiles: hideDotFiles, entries: entries, texts: texts, exclusions: exclusions, capacityReached: capacityReached) }
    }
    private struct Candidate {
        let entry: Entry
        let bodyTerms: [String]
        let firstMatch: (range: Range<Int>, term: String)?
        let rank: Int
        let nameMatches: Int
        func precedes(_ other: Candidate) -> Bool {
            if rank != other.rank { return rank > other.rank }
            if nameMatches != other.nameMatches { return nameMatches > other.nameMatches }
            return entry.file.path < other.entry.file.path
        }
    }
    private nonisolated static func match(_ query: String, fullText: Bool, limit: Int, hideDotFiles: Bool, entries: [Entry], texts: [String: SearchDocument], exclusions: [String: SearchExclusion], capacityReached: Bool) throws -> SearchResults {
        let terms = SearchQuery(query).terms
        guard !terms.isEmpty else { return SearchResults(hits: [], total: 0) }
        let folded = terms.map(SearchQuery.fold), bytes = folded.map { Data($0.utf8) }, phrase = folded.joined(separator: " ")
        var top: [Candidate] = [], total = 0
        for entry in entries {
            try Task.checkCancellation()
            if hideDotFiles && entry.file.path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            let document = fullText && entry.exclusion == nil ? entry.file.searchDocumentKey.flatMap { texts[$0] } : nil
            var bodyTerms: [String] = [], nameMatches = 0, matched = true
            var firstMatch: (range: Range<Int>, term: String)?
            for (i, term) in bytes.enumerated() {
                try Task.checkCancellation()
                let bodyRange = document?.folded.range(of: term)
                let shaMatch = folded[i].count >= 7 && entry.file.sha.lowercased().hasPrefix(folded[i])
                guard bodyRange != nil || entry.path.range(of: term) != nil || entry.metadataText.range(of: term) != nil || shaMatch else { matched = false; break }
                if let bodyRange {
                    bodyTerms.append(terms[i])
                    if firstMatch == nil || bodyRange.lowerBound < firstMatch!.range.lowerBound { firstMatch = (bodyRange, terms[i]) }
                }
                if entry.name.contains(folded[i]) { nameMatches += 1 }
            }
            guard matched else { continue }
            total += 1
            let rank = entry.name == phrase || entry.stem == phrase ? 5 : entry.name.hasPrefix(phrase) ? 4 : nameMatches == terms.count ? 3 : nameMatches > 0 ? 2 : !bodyTerms.isEmpty ? 1 : 0
            let candidate = Candidate(entry: entry, bodyTerms: bodyTerms, firstMatch: firstMatch, rank: rank, nameMatches: nameMatches)
            if top.count == limit, let last = top.last, !candidate.precedes(last) { continue }
            var lower = 0, upper = top.count
            while lower < upper { let middle = (lower + upper) / 2; if top[middle].precedes(candidate) { lower = middle + 1 } else { upper = middle } }
            top.insert(candidate, at: lower); if top.count > limit { top.removeLast() }
        }
        let hits = try top.map { candidate -> SearchHit in
            try Task.checkCancellation()
            let entry = candidate.entry, key = entry.file.searchDocumentKey
            let snippet = key.flatMap { texts[$0] }.flatMap { document in candidate.firstMatch.flatMap { Self.snippet(document, match: $0.range, term: $0.term) } }
            return SearchHit(path: entry.file.path, sha: entry.file.sha, snippet: snippet, bodyTerms: candidate.bodyTerms, metadata: entry.metadata, metadataOnlyReason: entry.exclusion ?? key.flatMap { exclusions[$0] ?? (capacityReached && texts[$0] == nil ? .memoryBudget : nil) })
        }
        return SearchResults(hits: hits, total: total)
    }
    private nonisolated static func snippet(_ document: SearchDocument, match folded: Range<Int>, term: String) -> String? {
        let text = document.text
        let lower = max(0, document.checkpoint(after: folded.lowerBound) - 1), upper = document.checkpoint(after: folded.upperBound)
        let endOfSearch = upper < document.checkpoints.count ? document.checkpoints[upper].index : text.endIndex
        guard let match = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: document.checkpoints[lower].index..<endOfSearch) else { return nil }
        let start = text.index(match.lowerBound, offsetBy: -45, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: 110, limitedBy: text.endIndex) ?? text.endIndex
        return (start == text.startIndex ? "" : "…") + text[start..<end] + (end == text.endIndex ? "" : "…")
    }
}
