import SwiftUI
import VaultCore

struct SearchView: View {
    let state: AppState
    @State private var query = ""
    @State private var fullText = false
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    var body: some View {
        List {
            Section {
                HStack {
                    if state.isPrefetching { ProgressView().controlSize(.small) }
                    Text("正文已补全 \(state.prefetchCompleted)/\(state.prefetchTotal)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !state.isPrefetching && state.prefetchCompleted < state.prefetchTotal {
                        Button("继续") { state.startPrefetch() }
                    }
                }
                if let error = state.prefetchError { Text(error).font(.caption).foregroundStyle(.secondary) }
                if !query.isEmpty {
                    Button(fullText ? "正在搜索文件名与正文" : "搜索正文") { fullText = true }.disabled(fullText)
                }
            }
            ForEach(hits) { hit in
                NavigationLink(value: ReaderRoute.file(hit.path)) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text((hit.path as NSString).lastPathComponent)
                        Text(hit.path).font(.caption).foregroundStyle(.secondary)
                        if let snippet = hit.snippet { Text(snippet).font(.callout).lineLimit(3).foregroundStyle(.secondary) }
                    }.padding(.vertical, 3)
                }
            }
            if !query.isEmpty && hits.isEmpty && !searching { Text("没有匹配的结果").foregroundStyle(.secondary) }
        }
        .navigationTitle("搜索")
        .task { state.startPrefetch() }
        .searchable(text: $query, prompt: "文件名；回车搜索正文")
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
