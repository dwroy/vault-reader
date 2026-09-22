import XCTest
@testable import VaultCore

final class ReadingTests: XCTestCase {
    private func entry(_ path: String) -> TreeEntry { TreeEntry(path: path, sha: String(repeating: "a", count: 40), size: 100) }
    func testCatalogKeepsEditionsAndOnlyDiscoversIndexedRelativePDFs() {
        let index = VaultIndex([entry("study/read/夜航/夜航-原文.md"), entry("study/read/夜航/夜航-精简版.md"), entry("study/read/书单.md"), entry("files/夜航-原书.pdf"), entry("files/private.pdf"), entry("other/note.md")])
        let md = "[PDF](../../files/夜航-原书.pdf) [remote](https://example.com/private.pdf) [escape](../../../files/private.pdf) [missing](../../files/missing.pdf)"
        let linked = BookCatalog.linkedPDFs(in: md, at: "study/read/书单.md", index: index)
        XCTAssertEqual(linked, ["files/夜航-原书.pdf"])
        let catalog = BookCatalog(index: index, linkedPDFs: linked)
        XCTAssertEqual(catalog.books.count, 1)
        XCTAssertEqual(Set(catalog.books[0].editions.map(\.path)), ["study/read/夜航/夜航-原文.md", "study/read/夜航/夜航-精简版.md", "files/夜航-原书.pdf"])
        XCTAssertEqual(catalog.indexes.map(\.path), ["study/read/书单.md"])
        XCTAssertNil(BookCatalog.root(for: "readme/note.md"))
        XCTAssertEqual(BookCatalog.root(for: "research/papers/paper.md"), "research/papers")
    }
    func testReadingHistoryPreservesEditionsAndSurvivesEncoding() throws {
        var history = ReadingHistory()
        let original = ReadingRecord(path: "read/book/original.md", title: "Original", kind: .markdown, location: .init(heading: "chapter::1", withinHeading: 0.4, fraction: 0.65))
        let summary = ReadingRecord(path: "read/book/summary.md", title: "Summary", kind: .markdown, location: .init(fraction: 0.2))
        history.remember(original); history.remember(summary)
        history.remember(ReadingRecord(path: "../outside", title: "Invalid", kind: .pdf))
        let restored = try JSONDecoder().decode(ReadingHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(restored.records.count, 2)
        XCTAssertEqual(restored.records[original.path]?.location, original.location)
        XCTAssertEqual(restored.records[summary.path]?.location.fraction, 0.2)
        var unsafe = original; unsafe.location.fraction = .infinity; unsafe.location.withinHeading = -1; unsafe.fontScale = .nan
        history.remember(unsafe)
        XCTAssertEqual(history.records[original.path]?.location.fraction, 0)
        XCTAssertEqual(history.records[original.path]?.location.withinHeading, 0)
        XCTAssertEqual(history.records[original.path]?.fontScale, 1)
    }
    func testProgressHistoryIsBoundedWithoutDroppingLatest() {
        var history = ReadingHistory()
        for i in 0..<205 { history.remember(ReadingRecord(path: "read/\(i).pdf", title: "Book", kind: .pdf, location: .init(page: i), updatedAt: Date(timeIntervalSince1970: Double(i)))) }
        XCTAssertEqual(history.records.count, 200)
        XCTAssertNil(history.records["read/0.pdf"])
        XCTAssertEqual(history.recent.first?.location.page, 204)
    }
}
