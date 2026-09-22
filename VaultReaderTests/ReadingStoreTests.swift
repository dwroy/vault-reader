import XCTest
import VaultCore
@testable import VaultReader

final class ReadingStoreTests: XCTestCase {
    @MainActor func testProgressPersistsAndIsolatesRepositoryBranchAndProvider() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var config = RepositoryConfig(); config.owner = "example"; config.repo = "reader"
        let store = ReadingStore(config: config, root: root)
        let book = BookSession(path: "read/original.md", kind: .markdown, store: store)
        book.record.fontScale = 1.3; book.record.theme = .sepia
        book.save(.init(heading: "chapter::0", withinHeading: 0.25, fraction: 0.4)); store.flush()
        let reopened = ReadingStore(config: config, root: root)
        XCTAssertEqual(reopened.history.records[book.record.path]?.location.heading, "chapter::0")
        XCTAssertEqual(reopened.history.records[book.record.path]?.fontScale, 1.3)
        XCTAssertEqual(reopened.history.records[book.record.path]?.theme, .sepia)
        var other = config; other.repo = "other"
        XCTAssertTrue(ReadingStore(config: other, root: root).history.records.isEmpty)
        other = config; other.branch = "other"
        XCTAssertTrue(ReadingStore(config: other, root: root).history.records.isEmpty)
        other = config; other.provider = .gitlab
        XCTAssertTrue(ReadingStore(config: other, root: root).history.records.isEmpty)
        XCTAssertNil(store.saveError)
    }
}
