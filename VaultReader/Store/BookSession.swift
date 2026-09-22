import Foundation
import Observation
import VaultCore

@MainActor @Observable final class BookSession {
    var record: ReadingRecord
    var outline: [ReadingOutline] = []
    let store: ReadingStore
    let viewport = ReaderSession()
    init(path: String, kind: ReadingKind, store: ReadingStore) {
        self.store = store
        record = store.history.records[path] ?? ReadingRecord(path: path, title: ((path as NSString).lastPathComponent as NSString).deletingPathExtension, kind: kind)
        viewport.position = record.location
        viewport.onPosition = { [weak self] location in self?.save(location) }
        viewport.onOutline = { [weak self] sections in self?.outline = sections }
        viewport.onSave = { [store] in store.flush() }
    }
    func opened() { record.updatedAt = Date(); store.record(record, immediately: true) }
    func save(_ location: ReadingLocation) {
        record.location = location; record.updatedAt = Date(); store.record(record, immediately: record.kind != .html)
    }
    func preferencesChanged() { record.updatedAt = Date(); store.record(record, immediately: true) }
    var percent: Int { Int((ReadingLocation.unit(record.location.fraction) * 100).rounded()) }
}
