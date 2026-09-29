import SwiftUI
import VaultCore

struct SearchView: View {
    let state: AppState
    @State private var query = ""
    @State private var results = SearchResultsModel()
    private struct Request: Hashable {
        let query: String
        let repository: String
        let tree: String
        let revision: Int
        let hideDotFiles: Bool
    }
    private var request: Request { Request(query: query, repository: state.config.storageKey, tree: state.treeSHA, revision: state.searchRevision, hideDotFiles: state.fileDisplay.hideDotFiles) }
    private var terms: [String] { SearchQuery(query).terms }
    private var remaining: Int { max(0, state.prefetchTotal - state.prefetchCompleted) }
    private var visibleHits: [SearchHit] {
        guard results.displayedQuery == query, results.displayedRepository == state.config.storageKey else { return [] }
        return results.hits.filter { state.index.files[$0.path]?.sha == $0.sha && state.fileDisplay.includes($0.path) }
    }
    var body: some View {
        List {
            VaultSuitabilityNotice(state: state, compact: true)
            Section {
                DisclosureGroup {
                    Text(L10n.format("Searches names, paths, file types, sizes and SHA. Markdown/TXT up to %1$@ also include text. All words must match.", ByteCountFormatter.string(fromByteCount: Int64(state.searchIndex.limits.sourceBytes), countStyle: .binary)))
                    if state.searchCoverage.limited > 0 { Text(L10n.text("Index capacity reached. Some files are searchable by metadata only.")) }
                } label: {
                    HStack {
                        if state.isPrefetching { ProgressView().controlSize(.small) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.format("Text searchable: %1$ld/%2$ld", state.prefetchCompleted, state.prefetchTotal))
                            if state.searchCoverage.metadataOnly > 0 {
                                Text(L10n.format("Metadata only: %1$ld", state.searchCoverage.metadataOnly)).accessibilityIdentifier("searchMetadataCount")
                            }
                        }
                    }
                }
                if remaining > 0 {
                    HStack {
                        Text(L10n.format("Not yet searchable: %1$ld", remaining)).accessibilityIdentifier("searchRemaining")
                        Spacer()
                        if !state.isPrefetching { Button(L10n.text("Continue")) { state.startPrefetch() } }
                    }
                }
                if let error = state.prefetchError { Text(error) }
            }.font(.caption).foregroundStyle(.secondary)
            if results.searching && !terms.isEmpty { ProgressView(L10n.text("Searching…")) }
            ForEach(visibleHits) { hit in
                NavigationLink(value: destination(hit)) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(highlight((hit.path as NSString).lastPathComponent))
                        Text(highlight(hit.path)).font(.caption).foregroundStyle(.secondary)
                        Text(highlight(metadataLabel(hit))).font(.caption).foregroundStyle(.secondary)
                        if let reason = hit.metadataOnlyReason { Text(exclusionLabel(reason)).font(.caption).foregroundStyle(.secondary) }
                        if let snippet = hit.snippet { Text(highlight(snippet)).font(.callout).lineLimit(4).foregroundStyle(.secondary) }
                    }.padding(.vertical, 3)
                }.accessibilityIdentifier("searchResult:" + hit.path)
            }
            if results.total > results.hits.count {
                Text(L10n.format("Showing %1$ld of %2$ld matches. Add keywords to narrow the results.", results.hits.count, results.total)).font(.caption).foregroundStyle(.secondary)
            }
            if !terms.isEmpty && visibleHits.isEmpty && !results.searching && !(state.isPrefetching && state.searchCoverage.indexed + state.searchCoverage.pending + state.searchCoverage.metadataOnly == 0) {
                Text(L10n.text("No results")).foregroundStyle(.secondary)
                if remaining > 0 { Text(L10n.text("Some text is not available yet. Results may be incomplete.")).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .listSectionSpacing(12)
        .libraryNavigationTitle(L10n.text("Search"), state: state, retry: { await state.refresh(); state.startPrefetch() })
        .task { state.startPrefetch() }
        .searchable(text: $query, prompt: L10n.text("Search names, text or file types"))
        .task(id: request) {
            results.update(query: query, repository: state.config.storageKey, engine: state.searchIndex, revision: state.searchRevision, hideDotFiles: state.fileDisplay.hideDotFiles)
        }
        .onDisappear { results.cancel() }
    }
    private func metadataLabel(_ hit: SearchHit) -> String {
        let type = L10n.text(hit.metadata.typeLabel)
        return hit.metadata.byteCount.map { type + " · " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? type
    }
    private func exclusionLabel(_ reason: SearchExclusion) -> String {
        switch reason {
        case .fileType: L10n.text("Metadata only · File type")
        case .tooLarge: L10n.text("Metadata only · File too large")
        case .contentLimit, .memoryBudget: L10n.text("Metadata only · Index limit")
        case .encoding: L10n.text("Metadata only · Text encoding")
        }
    }

    private func destination(_ hit: SearchHit) -> ReaderRoute {
        state.index.files[hit.path]?.isMarkdown == true
            ? .note(NoteRoute(path: hit.path, searchTerms: hit.bodyTerms)) : .file(hit.path)
    }
    private func highlight(_ text: String) -> AttributedString {
        var value = AttributedString(text)
        for match in SearchQuery.ranges(in: text, terms: terms) {
            if let range = Range(match, in: value) {
                value[range].foregroundColor = .primary
                value[range].backgroundColor = .yellow.opacity(0.35)
            }
        }
        return value
    }
}
