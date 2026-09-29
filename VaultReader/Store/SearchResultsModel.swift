import Foundation
import Observation
import VaultCore

/// Input changes cancel stale queries; progress changes only request a subsequent refresh.
/// A first result can publish even while indexing keeps advancing.
@MainActor @Observable final class SearchResultsModel {
    private(set) var hits: [SearchHit] = []
    private(set) var total = 0
    private(set) var searching = false
    private(set) var displayedQuery = ""
    private(set) var displayedRepository = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var engine: SearchIndex?
    @ObservationIgnored private var query = ""
    @ObservationIgnored private var repository = ""
    @ObservationIgnored private var hideDotFiles = false
    @ObservationIgnored private var revision = -1
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var needsRefresh = true
    func update(query: String, repository: String, engine: SearchIndex, revision: Int, hideDotFiles: Bool) {
        let inputChanged = self.query != query || self.repository != repository || self.engine !== engine || self.hideDotFiles != hideDotFiles
        let progressChanged = self.revision != revision
        self.query = query; self.repository = repository; self.engine = engine; self.revision = revision; self.hideDotFiles = hideDotFiles
        if inputChanged {
            cancel(); hits = []; total = 0; searching = !SearchQuery(query).terms.isEmpty
            start(debounce: true)
        } else if task == nil && (progressChanged || needsRefresh) { start(debounce: false) }
    }
    func cancel() { generation += 1; task?.cancel(); task = nil; needsRefresh = true; searching = false }
    private func start(debounce: Bool) {
        guard let engine, !SearchQuery(query).terms.isEmpty else { hits = []; total = 0; searching = false; needsRefresh = false; return }
        let expected = generation, query = query, repository = repository, hideDotFiles = hideDotFiles
        needsRefresh = false
        task = Task { [weak self] in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(120)) }
                while !Task.isCancelled {
                    guard let self, expected == self.generation else { return }
                    let readingRevision = self.revision
                    let result = try await engine.searchResults(query, hideDotFiles: hideDotFiles)
                    try Task.checkCancellation()
                    guard expected == self.generation else { return }
                    self.hits = result.hits; self.total = result.total; self.displayedQuery = query; self.displayedRepository = repository; self.searching = false
                    if readingRevision == self.revision { self.task = nil; return }
                    // Coalesce progress bursts without discarding the result just obtained.
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch {
                guard let self, expected == self.generation else { return }
                self.task = nil; self.searching = false; self.needsRefresh = true
            }
        }
    }
}
