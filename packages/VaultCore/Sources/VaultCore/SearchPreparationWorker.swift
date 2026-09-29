import Foundation

enum SearchPreparationResult: Sendable {
    case missing
    case document(SearchDocument, sourceBytes: Int, restored: Bool, writeFailed: Bool)
    case excluded(SearchExclusion)
}
/// Parsing, cache validation, encoding and IO never execute on the query/state actor.
/// This serial worker allows only one bounded document operation at a time per index.
actor SearchPreparationWorker {
    private var revision = 0
    private var cache: SearchTextCache?
    init(cacheDirectory: URL?) { cache = cacheDirectory.map { SearchTextCache(root: $0) } }
    func reconcile(_ entries: [TreeEntry], limits: SearchLimits, revision: Int) {
        guard !Task.isCancelled, revision >= self.revision else { return }
        self.revision = revision
        cache?.pruneDocuments(keeping: Set(entries.filter { $0.searchExclusion(limits: limits) == nil }.compactMap(\.searchDocumentKey)))
    }
    func restore(_ entry: TreeEntry, limits: SearchLimits, revision: Int) -> SearchPreparationResult {
        guard !Task.isCancelled, revision == self.revision, let kind = entry.searchTextKind else { return .missing }
        return autoreleasepool { cache?.restore(sha: entry.sha, kind: kind, limits: limits) ?? .missing }
    }
    func prepare(_ data: Data, entry: TreeEntry, limits: SearchLimits, revision: Int) -> SearchPreparationResult {
        // Drain Foundation parser/plist temporaries at the document boundary, even on a busy executor.
        autoreleasepool { prepareDocument(data, entry: entry, limits: limits, revision: revision) }
    }
    private func prepareDocument(_ data: Data, entry: TreeEntry, limits: SearchLimits, revision: Int) -> SearchPreparationResult {
        guard !Task.isCancelled, revision == self.revision, let kind = entry.searchTextKind else { return .missing }
        if data.count > limits.sourceBytes { return exclude(entry, reason: .tooLarge, limit: limits.sourceBytes, revision: revision) }
        guard let source = String(data: data, encoding: .utf8) else { return exclude(entry, reason: .encoding, limit: 0, revision: revision) }
        do {
            try Task.checkCancellation()
            let text = kind == .markdown ? try MarkdownSearchText.plainCancellable(source) : source
            let document = try SearchDocument(cancellableText: text)
            try Task.checkCancellation()
            guard document.memoryCost <= limits.documentBytes else { return exclude(entry, reason: .contentLimit, limit: limits.documentBytes, revision: revision) }
            var failed = false
            do { try cache?.save(document, sha: entry.sha, kind: kind, sourceBytes: data.count) } catch { failed = true }
            return .document(document, sourceBytes: data.count, restored: false, writeFailed: failed)
        } catch { return .missing }
    }
    func exclude(_ entry: TreeEntry, reason: SearchExclusion, limit: Int, revision: Int) -> SearchPreparationResult {
        guard !Task.isCancelled, revision == self.revision, let kind = entry.searchTextKind else { return .missing }
        try? cache?.saveExclusion(reason, sha: entry.sha, kind: kind, limit: limit)
        return .excluded(reason)
    }
}
