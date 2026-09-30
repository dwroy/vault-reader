import SwiftUI
import VaultCore

struct SearchView: View {
    let state: AppState
    let scope: SearchScopeModel
    @State private var query = ""
    @State private var showingVaults = false
    private struct Revision: Hashable {
        let repository: String
        let tree: String
        let revision: Int
        let ready: Bool
        let engine: ObjectIdentifier
    }
    private struct Request: Hashable {
        let query: String
        let selection: [String]
        let revisions: [Revision]
        let hideDotFiles: Bool
    }
    private var vaults: [RepositoryConfig] { state.library.repositories.filter { scope.selected.contains($0.storageKey) } }
    private var selection: [String] { scope.selected.sorted() }
    private var loadRequest: [String] { [state.config.storageKey] + selection + state.library.repositories.map(\.storageKey) }
    private var request: Request {
        Request(query: query, selection: selection, revisions: vaults.compactMap { config in
            guard let context = scope.contexts[config.storageKey] else { return nil }
            return Revision(repository: config.storageKey, tree: context.treeSHA, revision: context.searchRevision, ready: context.ready, engine: ObjectIdentifier(context.searchIndex))
        }, hideDotFiles: state.fileDisplay.hideDotFiles)
    }
    private var terms: [String] { SearchQuery(query).terms }
    private var title: String { vaults.count == 1 ? vaults[0].repo : L10n.text("Search") }
    private var titleState: AppState { vaults.count == 1 ? scope.contexts[vaults[0].storageKey] ?? state : state }
    private func hits(_ config: RepositoryConfig) -> [SearchHit] {
        guard let context = scope.contexts[config.storageKey], let result = scope.results[config.storageKey], result.displayedQuery == query, result.displayedRepository == config.storageKey else { return [] }
        return result.hits.filter { context.index.files[$0.path]?.sha == $0.sha && state.fileDisplay.includes($0.path) }
    }
    var body: some View {
        List {
            Section {
                Button { showingVaults = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checklist")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.text("Search vaults"))
                            Text(vaults.isEmpty ? L10n.text("Select at least one vault") : vaults.map(\.repo).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("searchVaultPicker")
            }
            if scope.selected.contains(state.config.storageKey) { VaultSuitabilityNotice(state: state, compact: true) }
            ForEach(vaults, id: \.storageKey) { config in
                if let context = scope.contexts[config.storageKey] {
                    Section {
                        coverage(context)
                        if scope.loading.contains(config.storageKey) { ProgressView(L10n.text("Opening library…")) }
                        if let result = scope.results[config.storageKey] {
                            if result.searching && !terms.isEmpty { ProgressView(L10n.text("Searching…")) }
                            ForEach(hits(config)) { hit in
                                NavigationLink(value: SearchReaderRoute(repository: config.storageKey, route: destination(hit, context: context))) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(highlight((hit.path as NSString).lastPathComponent))
                                        Text(highlight(hit.path)).font(.caption).foregroundStyle(.secondary)
                                        Text(highlight(metadataLabel(hit))).font(.caption).foregroundStyle(.secondary)
                                        if let reason = hit.metadataOnlyReason { Text(exclusionLabel(reason)).font(.caption).foregroundStyle(.secondary) }
                                        if let snippet = hit.snippet { Text(highlight(snippet)).font(.callout).lineLimit(4).foregroundStyle(.secondary) }
                                    }.padding(.vertical, 3)
                                }.accessibilityIdentifier("searchResult:" + config.repo + ":" + hit.path)
                            }
                            if result.displayedQuery == query && result.total > result.hits.count {
                                Text(L10n.format("Showing %1$ld of %2$ld matches. Add keywords to narrow the results.", result.hits.count, result.total)).font(.caption).foregroundStyle(.secondary)
                            }
                            if !terms.isEmpty && hits(config).isEmpty && !result.searching && context.ready && !(context.isPrefetching && context.searchCoverage.indexed + context.searchCoverage.pending + context.searchCoverage.metadataOnly == 0) {
                                Text(L10n.text("No results")).foregroundStyle(.secondary)
                                if context.prefetchTotal > context.prefetchCompleted { Text(L10n.text("Some text is not available yet. Results may be incomplete.")).font(.callout).foregroundStyle(.secondary) }
                            }
                        }
                        if context.ready && context.index.entries.isEmpty { Text(L10n.text("No saved files. Open and refresh this vault first.")).font(.callout).foregroundStyle(.secondary) }
                        if let error = context.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    } header: { Text(config.displayName) }
                }
            }
        }
        .listSectionSpacing(12)
        .libraryNavigationTitle(title, state: titleState, retry: { await titleState.refresh(); titleState.startPrefetch() })
        .searchable(text: $query, prompt: L10n.text("Search names, text or file types"))
        .onAppear { scope.followCurrent(state); scope.resume() }
        .task(id: loadRequest) { await scope.load(state) }
        .task(id: request) {
            for config in vaults {
                guard let context = scope.contexts[config.storageKey], context.ready, let result = scope.results[config.storageKey] else { continue }
                result.update(query: query, repository: config.storageKey, engine: context.searchIndex, revision: context.searchRevision, hideDotFiles: state.fileDisplay.hideDotFiles)
            }
        }
        .onDisappear { scope.cancelQueries() }
        .sheet(isPresented: $showingVaults) {
            NavigationStack {
                List {
                    Section {
                        ForEach(state.library.repositories, id: \.storageKey) { config in
                            Button { scope.toggle(config) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: scope.selected.contains(config.storageKey) ? "checkmark.square.fill" : "square")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(config.repo).foregroundStyle(.primary)
                                        Text(config.displayName).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }.contentShape(Rectangle())
                            }.accessibilityIdentifier("searchVault:" + config.repo)
                                .accessibilityValue(L10n.text(scope.selected.contains(config.storageKey) ? "Selected" : "Not selected"))
                                .accessibilityAddTraits(scope.selected.contains(config.storageKey) ? .isSelected : [])
                        }
                    } footer: { Text(L10n.text("Search uses saved vault files. Open and refresh a vault to update its file list.")) }
                }
                .navigationTitle(L10n.text("Search vaults")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { showingVaults = false } } }
            }
        }
    }
    private func coverage(_ context: AppState) -> some View {
        DisclosureGroup {
            Text(L10n.format("Searches names, paths, file types, sizes and SHA. Markdown/TXT up to %1$@ also include text. All words must match.", ByteCountFormatter.string(fromByteCount: Int64(context.searchIndex.limits.sourceBytes), countStyle: .binary)))
            if context.searchCoverage.limited > 0 { Text(L10n.text("Index capacity reached. Some files are searchable by metadata only.")) }
            if context.prefetchTotal > context.prefetchCompleted {
                HStack {
                    Text(L10n.format("Not yet searchable: %1$ld", context.prefetchTotal - context.prefetchCompleted)).accessibilityIdentifier("searchRemaining")
                    Spacer()
                    if !context.isPrefetching { Button(L10n.text("Continue")) { context.startPrefetch() } }
                }
            }
            if let error = context.prefetchError { Text(error) }
        } label: {
            HStack {
                if context.isPrefetching { ProgressView().controlSize(.small) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.format("Text searchable: %1$ld/%2$ld", context.prefetchCompleted, context.prefetchTotal))
                    if context.searchCoverage.metadataOnly > 0 { Text(L10n.format("Metadata only: %1$ld", context.searchCoverage.metadataOnly)).accessibilityIdentifier("searchMetadataCount") }
                }
            }
        }.font(.caption).foregroundStyle(.secondary)
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
    private func destination(_ hit: SearchHit, context: AppState) -> ReaderRoute {
        context.index.files[hit.path]?.isMarkdown == true ? .note(NoteRoute(path: hit.path, searchTerms: hit.bodyTerms)) : .file(hit.path)
    }
    private func highlight(_ text: String) -> AttributedString {
        var value = AttributedString(text)
        for match in SearchQuery.ranges(in: text, terms: terms) {
            if let range = Range(match, in: value) { value[range].foregroundColor = .primary; value[range].backgroundColor = .yellow.opacity(0.35) }
        }
        return value
    }
}
