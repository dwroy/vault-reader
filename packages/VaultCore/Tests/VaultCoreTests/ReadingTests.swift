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
    func testRecentReadingListsOnlyLatestThreeMarkdownDocuments() {
        var history = ReadingHistory()
        let kinds: [ReadingKind] = [.markdown, .pdf, .markdown, .html, .markdown, .markdown, .pdf]
        for (i, kind) in kinds.enumerated() { history.remember(ReadingRecord(path: "read/\(i).\(kind.rawValue)", title: "\(i)", kind: kind, updatedAt: Date(timeIntervalSince1970: Double(i)))) }
        XCTAssertEqual(history.recentMarkdown(limit: 3).map(\.path), ["read/5.markdown", "read/4.markdown", "read/2.markdown"])
        XCTAssertEqual(history.recentMarkdown(limit: 3) { $0.path != "read/4.markdown" }.map(\.title), ["5", "2", "0"])
        XCTAssertEqual(history.records.count, 7, "PDF and HTML progress stays available to book pages")
    }
    func testBookListGroupsBooksAndResolvesEveryFileRole() throws {
        let index = VaultIndex(["study/read/书单.md", "study/read/夜航/夜航-精简版.md", "study/read/夜航/夜航-原文.md", "study/read/夜航/夜航-复习笔记.md",
                                "study/read/夜航/夜航-阅读器.html", "files/夜航 原书.pdf", "files/灯塔.pdf", "study/read/灯塔/灯塔书评.md", "thoughts/灯塔书评.md"].map(entry))
        let md = """
        ---
        tags: [清单]
        ---
        # 书单

        格式说明：- 作者：这一行不在书里，不应被解析。

        ## 在读

        ### 夜航手记
        - **作者**：示例作者
        - 状态：复习中（[[夜航-复习笔记|复习]]）
        - 评分：⭐️⭐️⭐️⭐️
        - 原书：[PDF](<../../files/夜航 原书.pdf>)（380 页，扫描本）
        - 全文：[[夜航-原文|OCR 全文]]
        - 精简版：[逐章详版](夜航/夜航-精简版.md)、[[夜航-精简版]]
        - 阅读器：[📖 阅读器](夜航/%E5%A4%9C%E8%88%AA-%E9%98%85%E8%AF%BB%E5%99%A8.html)、<https://example.com/night>
        - 笔记：
          - [[夜航-复习笔记\\|复习笔记]]
          - [[不存在的笔记]]
        - 评论：合成的短评。
        - 备注：第二遍重读。

        ### 仅有标题的小节

        ## 读完

        ### 灯塔
        - 原书：[PDF](../../files/灯塔.pdf)
        - 书评：[[灯塔书评]]
        - 相关：https://example.com/lighthouse

        ```
        ### 代码里的书
        - 作者：不应解析
        ```

        ## 单独成书
        - 作者：二级标题也可以是书

        ## 相关
        - 索引：[[学习索引]]
        """
        let list = BookList(markdown: md, at: "study/read/书单.md", index: index)
        XCTAssertEqual(list.books.map(\.title), ["夜航手记", "灯塔", "单独成书"])
        XCTAssertEqual(BookList.groups(list.books).map(\.title), ["在读", "读完", nil])
        let night = list.books[0]
        XCTAssertEqual(night.author, "示例作者")
        XCTAssertEqual(night.status, "复习中（复习）")
        XCTAssertEqual(night.rating, "⭐️⭐️⭐️⭐️")
        XCTAssertEqual(night.remarks, ["第二遍重读。"])
        XCTAssertEqual(night.comments, ["合成的短评。"])
        XCTAssertEqual(night.links(.original).map(\.path), ["files/夜航 原书.pdf"])
        XCTAssertEqual(night.links(.original).first?.detail, "380 页，扫描本")
        XCTAssertEqual(night.links(.fulltext).map(\.label), ["OCR 全文"])
        XCTAssertEqual(night.links(.condensed).map(\.path), ["study/read/夜航/夜航-精简版.md"], "the same file is listed once")
        XCTAssertEqual(night.links(.reader).map(\.path), ["study/read/夜航/夜航-阅读器.html", nil])
        XCTAssertEqual(night.links(.reader).last?.url?.absoluteString, "https://example.com/night")
        XCTAssertEqual(night.links(.notes).map(\.path), ["study/read/夜航/夜航-复习笔记.md", nil])
        XCTAssertEqual(night.links(.notes).map(\.label), ["复习笔记", "不存在的笔记"])
        let lighthouse = list.books[1]
        XCTAssertEqual(lighthouse.group, "读完")
        XCTAssertEqual(lighthouse.links(.review).map(\.path), ["thoughts/灯塔书评.md"], "same as the renderer: a shallower path wins")
        XCTAssertEqual(lighthouse.links(.other).first?.url?.host, "example.com")
        XCTAssertNil(list.books[2].group)
    }
    func testBookListRejectsTraversalAndUnsupportedSchemes() {
        let index = VaultIndex(["read/书单.md", "secret.pdf", "read/a.pdf"].map(entry))
        let md = "## 书\n- 原书：[escape](../../secret.pdf)、[app](obsidian://open?vault=x)、[ok](a.pdf)、[file](file:///etc/hosts)"
        let book = BookList(markdown: md, at: "read/书单.md", index: index).books.first
        XCTAssertEqual(book?.links.map(\.path), [nil, "read/a.pdf"])
        XCTAssertEqual(book?.links.compactMap(\.url), [])
    }
    func testProgressHistoryIsBoundedWithoutDroppingLatest() {
        var history = ReadingHistory()
        for i in 0..<205 { history.remember(ReadingRecord(path: "read/\(i).pdf", title: "Book", kind: .pdf, location: .init(page: i), updatedAt: Date(timeIntervalSince1970: Double(i)))) }
        XCTAssertEqual(history.records.count, 200)
        XCTAssertNil(history.records["read/0.pdf"])
        XCTAssertEqual(history.recent.first?.location.page, 204)
    }
}
