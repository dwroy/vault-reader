import VaultCore
import SwiftUI

struct DirView: View {
    let state: AppState
    let path: String
    var body: some View {
        List {
            if path.isEmpty {
                VaultSuitabilityNotice(state: state)
                Section { Text("\(state.config.owner) / \(state.config.repo)").font(.subheadline).foregroundStyle(.secondary) } footer: { Text(L10n.format("Files: %1$ld · %2$@", state.visibleEntries.count, state.config.branch)) }
            }
            ForEach(state.index.children(of: path).filter { state.fileDisplay.includes($0.path) }) { item in
                if item.isDirectory { NavigationLink(value: ReaderRoute.directory(item.path)) { row(item) } }
                else if item.entry?.isMarkdown == true { NavigationLink(value: ReaderRoute.note(NoteRoute(path: item.path))) { row(item) } }
                else {
                    NavigationLink(value: ReaderRoute.file(item.path)) { row(item) }
                }
            }
        }
        .libraryNavigationTitle(path.isEmpty ? L10n.text("Files") : (path as NSString).lastPathComponent, state: state)
        .refreshable { await state.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L10n.text("Refresh"), systemImage: "arrow.clockwise") { Task { await state.refresh() } }
                        .disabled(state.isRefreshing || state.switchingRepository)
                    Button(L10n.text("Settings"), systemImage: "gearshape") { state.addingRepository = false; state.showSettings = true }.accessibilityIdentifier("openSettings")
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel(L10n.text("Directory actions")).accessibilityIdentifier("directoryActions")
            }
        }
    }
    private func row(_ item: DirectoryItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.isDirectory ? "folder" : item.entry?.isMarkdown == true ? "doc.text" : "doc").foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.body)
                if let bytes = item.entry?.size { Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
            }.padding(.vertical, 4)
        }
    }
}
