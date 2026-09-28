import SwiftUI
import VaultCore
import AVKit

struct AttachmentView: View {
    let state: AppState
    let path: String
    @State private var url: URL?
    @State private var previewStore: BlobStore?
    @State private var progress: Double?
    @State private var error: String?
    @State private var attempt = 0
    @State private var cancelled = false
    @State private var tooLarge = false
    var body: some View {
        Group {
            if let url { PreviewController(url: url) }
            else if tooLarge || (state.index.files[path]?.size ?? 0) > BlobStore.maximumFileBytes {
                ContentUnavailableView { Label(L10n.text("File exceeds 100 MB"), systemImage: "doc") } actions: { Link(L10n.format("Open in %1$@", state.config.provider.title), destination: state.config.fileURL(path: path)) }
            } else if let error {
                ContentUnavailableView { Label(cancelled ? L10n.text("Download cancelled") : L10n.text("Preview unavailable"), systemImage: "doc") } description: { Text(error) } actions: { Button(L10n.text("Retry")) { cancelled = false; attempt += 1 } }
            } else {
                VStack(spacing: 16) {
                    Text((path as NSString).lastPathComponent)
                    if let size = state.index.files[path]?.size { Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)).foregroundStyle(.secondary) }
                    if let progress { ProgressView(value: progress).frame(maxWidth: 240) } else { ProgressView(L10n.text("Preparing preview…")) }
                    Button(L10n.text("Cancel")) { cancelled = true; error = L10n.text("The attachment has not finished downloading.") }
                }.padding()
            }
        }
        .libraryNavigationTitle((path as NSString).lastPathComponent, state: state)
        .onDisappear {
            if let url, let store = previewStore { Task { try? await store.releasePreview(url) } }
            url = nil; previewStore = nil
        }
        .task(id: "\(attempt)|\(cancelled)") {
            guard !cancelled, url == nil, (state.index.files[path]?.size ?? 0) <= BlobStore.maximumFileBytes else { return }
            error = nil; progress = nil
            do {
                let store = state.blobs
                let file = try await state.preview(path, progress: { value in Task { @MainActor in progress = value } })
                if Task.isCancelled { try? await store?.releasePreview(file); return }
                previewStore = store; url = file
            } catch is CancellationError {} catch { if !Task.isCancelled { tooLarge = (error as? VaultError) == .tooLarge; self.error = error.localizedDescription } }
        }
    }
}
struct AttachmentSheet: View {
    let state: AppState
    let path: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { AttachmentView(state: state, path: path).toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } } } }
    }
}
struct VideoSheet: View {
    let url: URL
    @State private var player = AVPlayer()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { VideoPlayer(player: player).toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } } } }
            .onAppear { player.replaceCurrentItem(with: AVPlayerItem(url: url)); player.play() }.onDisappear { player.pause() }
    }
}
