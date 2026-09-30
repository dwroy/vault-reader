import Foundation
import Observation
import VaultCore

struct SearchReaderRoute: Hashable {
    let repository: String
    let route: ReaderRoute
}

/// Selected vaults keep independent catalogs, credentials, readers and query generations.
@MainActor @Observable final class SearchScopeModel {
    private(set) var selected = Set<String>()
    private(set) var current = ""
    private(set) var contexts: [String: AppState] = [:]
    private(set) var results: [String: SearchResultsModel] = [:]
    private(set) var loading = Set<String>()

    func followCurrent(_ state: AppState) {
        guard current != state.config.storageKey else { return }
        stop()
        current = state.config.storageKey; selected = [current]
        contexts = [current: state]; results = [current: SearchResultsModel()]; loading = []
    }
    func toggle(_ config: RepositoryConfig) {
        if selected.contains(config.storageKey) { selected.remove(config.storageKey) }
        else { selected.insert(config.storageKey) }
        cancelQueries()
    }
    func load(_ state: AppState) async {
        let available = Set(state.library.repositories.map(\.storageKey)).union([state.config.storageKey])
        selected.formIntersection(available)
        let auxiliaryCount = selected.subtracting([current]).count
        // Auxiliary search bodies share a 32 MiB accounted budget in addition to the active index.
        let bytes = SearchLimits().residentBytes / max(1, auxiliaryCount)
        for key in Array(contexts.keys) where !selected.contains(key) || (key != current && contexts[key]?.searchIndex.limits.residentBytes != bytes) {
            if key != current { contexts[key]?.stopPrefetch() }
            contexts.removeValue(forKey: key); results.removeValue(forKey: key)?.cancel()
            loading.remove(key)
        }
        for config in state.library.repositories where selected.contains(config.storageKey) {
            guard !Task.isCancelled else { return }
            let key = config.storageKey
            if results[key] == nil { results[key] = SearchResultsModel() }
            if key == current { contexts[key] = state }
            if contexts[key] == nil {
                let context = AppState(searchConfig: config, sample: state.demo, limits: SearchLimits(residentBytes: bytes), fileDisplay: state.fileDisplay)
                contexts[key] = context; loading.insert(key)
                await context.loadForSearch()
                loading.remove(key)
                guard !Task.isCancelled else { context.stopPrefetch(); return }
            } else if let context = contexts[key], !context.ready {
                loading.insert(key); await context.loadForSearch(); loading.remove(key)
                guard !Task.isCancelled else { context.stopPrefetch(); return }
            }
        }
    }
    func cancelQueries() { for result in results.values { result.cancel() } }
    func stop() {
        cancelQueries()
        for (key, context) in contexts where key != current { context.stopPrefetch() }
    }
    func resume() { for context in contexts.values where context.ready { context.startPrefetch() } }
}
