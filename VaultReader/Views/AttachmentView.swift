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
                ContentUnavailableView { Label("文件超过 100 MB", systemImage: "doc") } actions: { Link("在 \(state.config.provider.title) 打开", destination: state.config.fileURL(path: path)) }
            } else if let error {
                ContentUnavailableView { Label(cancelled ? "下载已取消" : "无法预览", systemImage: "doc") } description: { Text(error) } actions: { Button("重试") { cancelled = false; attempt += 1 } }
            } else {
                VStack(spacing: 16) {
                    Text((path as NSString).lastPathComponent)
                    if let size = state.index.files[path]?.size { Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)).foregroundStyle(.secondary) }
                    if let progress { ProgressView(value: progress).frame(maxWidth: 240) } else { ProgressView("正在准备预览…") }
                    Button("取消") { cancelled = true; error = "附件尚未下载完成。" }
                }.padding()
            }
        }
        .navigationTitle((path as NSString).lastPathComponent).navigationBarTitleDisplayMode(.inline)
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
        NavigationStack { AttachmentView(state: state, path: path).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } } }
    }
}
struct VideoSheet: View {
    let url: URL
    @State private var player = AVPlayer()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { VideoPlayer(player: player).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } } }
            .onAppear { player.replaceCurrentItem(with: AVPlayerItem(url: url)); player.play() }.onDisappear { player.pause() }
    }
}
