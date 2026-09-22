import XCTest
@testable import VaultCore

final class SearchTests: XCTestCase {
    func testFilenameAndChineseFullTextAndTreeInvalidation() async throws {
        let index = SearchIndex()
        let a = TreeEntry(path: "日记/公园.md", sha: "a", size: 1), b = TreeEntry(path: "文档.pdf", sha: "b", size: 1)
        await index.update([a, b]); await index.insert("叶子像一只小船。CAFÉ 很安静。", for: a)
        let filename = try await index.search("公园", fullText: false)
        let noBody = try await index.search("小船", fullText: false)
        let body = try await index.search("小船", fullText: true)
        let folded = try await index.search("cafe", fullText: true)
        XCTAssertEqual(filename.map(\.path), [a.path]); XCTAssertTrue(noBody.isEmpty)
        XCTAssertEqual(body.map(\.path), [a.path]); XCTAssertTrue(body[0].snippet!.contains("小船")); XCTAssertEqual(folded.count, 1)
        await index.update([TreeEntry(path: a.path, sha: "new", size: 1)])
        await index.insert("过时的小船", for: a)
        let stale = try await index.search("小船", fullText: true), deleted = try await index.search("pdf", fullText: false)
        XCTAssertTrue(stale.isEmpty); XCTAssertTrue(deleted.isEmpty)
    }
    func testFiveMegabyteSearchBudget() async throws {
        let index = SearchIndex()
        let entries = (0..<400).map { TreeEntry(path: "note-\($0).md", sha: String($0), size: 13000) }
        await index.update(entries)
        for entry in entries { await index.insert(String(repeating: "普通正文 some words. ", count: 650) + "独特匹配", for: entry) }
        let start = ContinuousClock.now
        let result = try await index.search("独特匹配", fullText: true)
        let elapsed = start.duration(to: .now)
        print("Search corpus >5 MB: \(elapsed)")
        XCTAssertEqual(result.count, 400); XCTAssertLessThan(elapsed, .milliseconds(200))
    }
}
