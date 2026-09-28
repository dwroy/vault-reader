import SwiftUI
import VaultCore

struct SearchView: View {
    let state: AppState
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var appliedQuery = ""
    @State private var appliedRepository = ""
    @State private var searching = false
    private struct Request: Hashable {
        let query: String
        let repository: String
        let tree: String
        let revision: Int
    }
    private var request: Request { Request(query: query, repository: state.config.storageKey, tree: state.treeSHA, revision: state.searchRevision) }
    private var terms: [String] { SearchQuery(query).terms }
    private var remaining: Int { max(0, state.prefetchTotal - state.prefetchCompleted) }
    private var visibleHits: [SearchHit] {
        guard appliedQuery == query, appliedRepository == state.config.storageKey else { return [] }
        return hits.filter { state.index.files[$0.path]?.sha == $0.sha && state.fileDisplay.includes($0.path) }
    }
    var body: some View {
        List {
            Section {
                HStack {
                    if state.isPrefetching { ProgressView().controlSize(.small) }
                    Text(L10n.format("Markdown searchable: %1$ld/%2$ld", state.prefetchCompleted, state.prefetchTotal))
                    Spacer()
                    if !state.isPrefetching && remaining > 0 {
                        Button(L10n.text("Continue")) { state.startPrefetch() }
                    }
                }
                if remaining > 0 {
                    Text(L10n.format("Not yet searchable: %1$ld", remaining))
                        .accessibilityIdentifier("searchRemaining")
                }
                if let error = state.prefetchError { Text(error) }
            } footer: {
                Text(L10n.text("Searches this library. All words must match. PDF, HTML and images are searched by filename only."))
            }.font(.caption).foregroundStyle(.secondary)
            if searching && !terms.isEmpty { ProgressView(L10n.text("Searching…")) }
            ForEach(visibleHits) { hit in
                NavigationLink(value: destination(hit)) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(highlight((hit.path as NSString).lastPathComponent))
                        Text(highlight(hit.path)).font(.caption).foregroundStyle(.secondary)
                        if let snippet = hit.snippet { Text(highlight(snippet)).font(.callout).lineLimit(4).foregroundStyle(.secondary) }
                    }.padding(.vertical, 3)
                }.accessibilityIdentifier("searchResult:" + hit.path)
            }
            if !terms.isEmpty && visibleHits.isEmpty && !searching {
                Text(L10n.text("No results")).foregroundStyle(.secondary)
                if remaining > 0 { Text(L10n.text("Some Markdown text is not available yet. Results may be incomplete.")).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(L10n.text("Search"))
        .task { state.startPrefetch() }
        .searchable(text: $query, prompt: L10n.text("Search filenames and text"))
        .task(id: request) {
            let requested = request, engine = state.searchIndex
            searching = true
            do {
                // Debounce new input; indexing updates use the same mode and refresh immediately.
                if requested.query != appliedQuery { try await Task.sleep(for: .milliseconds(120)) }
                let found = try await engine.search(requested.query)
                try Task.checkCancellation()
                guard requested == request else { return }
                hits = found; appliedQuery = requested.query; appliedRepository = requested.repository; searching = false
            } catch { if !Task.isCancelled { searching = false } }
        }
        .safeAreaInset(edge: .top, spacing: 0) { StatusBanner(state: state) }
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
