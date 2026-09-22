import Foundation
import Observation
import VaultCore

/// One file per repository/branch. A captured store remains tied to its original vault during navigation.
@MainActor @Observable final class ReadingStore {
    let key: String
    private(set) var saveError: String?
    private(set) var history: ReadingHistory
    private let url: URL
    private var pending: Task<Void, Never>?
    init(config: RepositoryConfig, root: URL? = nil) {
        key = config.storageKey
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ReadingProgress")
        url = base.appendingPathComponent(MetaStore.key(key) + ".json")
        history = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ReadingHistory.self, from: $0) } ?? ReadingHistory()
    }
    func record(_ record: ReadingRecord, immediately: Bool = false) {
        history.remember(record)
        pending?.cancel()
        if immediately { flush(); return }
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)); try Task.checkCancellation(); self?.flush() } catch {}
        }
    }
    #if DEBUG
    func clearDemoProgress() { history = ReadingHistory(); flush() }
    #endif
    func flush() {
        pending?.cancel(); pending = nil
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            saveError = nil
        } catch { saveError = "阅读位置暂未保存，请稍后重试。" }
    }
}
