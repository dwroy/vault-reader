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

extension SearchTests {
    func testMultipleWordsAcrossNameAndBodyRankAheadOfDirectoryOnlyMatches() async throws {
        let index = SearchIndex()
        let exact = TreeEntry(path: "Z/公园.md", sha: "z", size: 1)
        let body = TreeEntry(path: "A/杂记.md", sha: "a", size: 1)
        let path = TreeEntry(path: "公园/附件.pdf", sha: "p", size: 1)
        await index.update([body, path, exact])
        await index.insert("孩子的出行记录", for: exact)
        await index.insert("周末在公园看花，孩子很开心。关联：公园.md", for: body)
        let ranked = try await index.search("公园")
        XCTAssertEqual(ranked.map(\.path), [exact.path, body.path, path.path])
        XCTAssertTrue(ranked.last!.bodyTerms.isEmpty)
        let fullName = try await index.search("公园.md")
        XCTAssertEqual(fullName.map(\.path), [exact.path, body.path])
        let multi = try await index.search(" 公园\t孩子 \n公园")
        XCTAssertEqual(multi.map(\.path), [exact.path, body.path])
        XCTAssertEqual(multi[0].bodyTerms, ["孩子"])
        XCTAssertEqual(multi[1].bodyTerms, ["公园", "孩子"])
        let missing = try await index.search("公园 不存在")
        XCTAssertTrue(missing.isEmpty)
        let whitespace = try await index.search(" \n\t ")
        XCTAssertTrue(whitespace.isEmpty)
        let combiningMark = try await index.search("\u{0301}")
        XCTAssertTrue(combiningMark.isEmpty)
    }
    func testMarkdownVisibleTextAndOriginalSpelling() async throws {
        let index = SearchIndex(), entry = TreeEntry(path: "note.md", sha: "a", size: 1)
        await index.update([entry])
        await index.insert("""
        ---
        secret: private-property
        ---
        # 标题

        我们在**公园**散步。[链接文字](https://example.invalid/hidden-url)
        [[folder/hidden-target|双链文字]] 和 ==高亮文字==。CAFÉ Today。
        %%隐藏备注 `秘密代码`%% <!--隐藏注释 `隐藏代码`-->
        <details><summary>更多</summary><p>折叠正文</p></details>

        `%%literal%%` 和 `[[code|literal-code]]`

        ```md
        **literal-code-fence**
        ```
        """, for: entry)
        for query in ["公园散步", "链接文字", "双链文字", "高亮文字", "折叠正文", "%%literal%%", "literal-code", "**literal-code-fence**"] {
            let hits = try await index.search(query)
            XCTAssertEqual(hits.count, 1, query)
        }
        for query in ["private-property", "hidden-url", "hidden-target", "隐藏备注", "隐藏注释", "秘密代码", "隐藏代码", "<details>"] {
            let hits = try await index.search(query)
            XCTAssertTrue(hits.isEmpty, query)
        }
        let cafe = try await index.search("cafe")
        XCTAssertTrue(cafe[0].snippet!.contains("CAFÉ Today"))
    }
    func testSnippetCheckpointBoundariesAndFoldedLengths() async throws {
        let index = SearchIndex(), entry = TreeEntry(path: "note.md", sha: "a", size: 1)
        await index.update([entry])
        await index.insert(String(repeating: "é👨‍👩‍👧a", count: 170) + "CAFÉ 跨越边界的公园散步", for: entry)
        let hits = try await index.search("cafe 公园散步")
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits[0].snippet!.contains("CAFÉ 跨越边界的公园散步"))
        XCTAssertFalse(hits[0].snippet!.contains("�"))
        let text = "CAFÉ café 👨‍👩‍👧公园散步"
        let ranges = SearchQuery.ranges(in: text, terms: ["cafe", "公园", "公园散步"])
        XCTAssertEqual(ranges.map { String(text[$0]) }, ["CAFÉ", "café", "公园散步"])
        XCTAssertEqual(SearchQuery("café CAFE\n公园\t公园").terms, ["café", "公园"])
    }
}
