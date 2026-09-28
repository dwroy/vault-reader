import SwiftUI
import VaultCore

struct SearchView: View {
    let state: AppState
    @State private var query = ""
    @State private var fullText = false
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    private var visibleHits: [SearchHit] { hits.filter { state.fileDisplay.includes($0.path) } }
    var body: some View {
        List {
            Section {
                HStack {
                    if state.isPrefetching { ProgressView().controlSize(.small) }
                    Text(L10n.format("Text cached: %1$ld/%2$ld", state.prefetchCompleted, state.prefetchTotal)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !state.isPrefetching && state.prefetchCompleted < state.prefetchTotal {
                        Button(L10n.text("Continue")) { state.startPrefetch() }
                    }
                }
                if let error = state.prefetchError { Text(error).font(.caption).foregroundStyle(.secondary) }
                if !query.isEmpty {
                    Button(fullText ? L10n.text("Searching names and text") : L10n.text("Search text")) { fullText = true }.disabled(fullText)
                }
            }
            ForEach(visibleHits) { hit in
                NavigationLink(value: ReaderRoute.file(hit.path)) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text((hit.path as NSString).lastPathComponent)
                        Text(hit.path).font(.caption).foregroundStyle(.secondary)
                        if let snippet = hit.snippet { Text(snippet).font(.callout).lineLimit(3).foregroundStyle(.secondary) }
                    }.padding(.vertical, 3)
                }
            }
            if !query.isEmpty && visibleHits.isEmpty && !searching { Text(L10n.text("No results")).foregroundStyle(.secondary) }
        }
        .navigationTitle(L10n.text("Search"))
        .task { state.startPrefetch() }
        .searchable(text: $query, prompt: L10n.text("Filename; return to search text"))
        .onChange(of: query) { _, _ in fullText = false }
        .onSubmit(of: .search) { fullText = true }
        .task(id: "\(query)|\(fullText)|\(state.prefetchCompleted)|\(state.treeSHA)") {
            searching = true
            do {
                // Debounce typing; actor work and cancellation keep the UI responsive.
                try await Task.sleep(for: .milliseconds(120))
                let found = try await state.searchIndex.search(query, fullText: fullText)
                try Task.checkCancellation(); hits = found; searching = false
            } catch { if !Task.isCancelled { searching = false } }
        }
        .safeAreaInset(edge: .top, spacing: 0) { StatusBanner(state: state) }
    }
}
