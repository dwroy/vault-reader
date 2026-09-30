import XCTest
@testable import VaultCore

final class VaultStatisticsTests: XCTestCase {
    func testCatalogCountsNestedFoldersCaseInsensitiveTypesAndUnknownSizes() {
        let files = [
            TreeEntry(path: "README.md", sha: "a", size: 10),
            TreeEntry(path: "notes/deep/Note.MD", sha: "b", size: nil),
            TreeEntry(path: "notes/photo.png", sha: "c", size: 200),
            TreeEntry(path: "LICENSE", sha: "d", size: 0),
            TreeEntry(path: "notes/old.txt", sha: "e", size: -1),
            TreeEntry(path: "README.md", sha: "a", size: 10), // One path is one file.
            TreeEntry(path: "submodule", sha: "x", size: nil, type: "commit"),
            TreeEntry(path: "../escape.pdf", sha: "x", size: 99)
        ]
        let statistics = VaultStatistics(index: VaultIndex(files))
        XCTAssertEqual(statistics.fileCount, 5)
        XCTAssertEqual(statistics.folderCount, 2)
        XCTAssertEqual(statistics.knownBytes, 210)
        XCTAssertEqual(statistics.unknownSizeCount, 2)
        XCTAssertEqual(statistics.fileTypes.map(\.ext), ["md", "", "png", "txt"])
        let markdown = statistics.fileTypes[0]
        XCTAssertEqual(markdown.fileCount, 2)
        XCTAssertEqual(markdown.knownBytes, 10)
        XCTAssertEqual(markdown.unknownSizeCount, 1)
        XCTAssertEqual(statistics.fileTypes.reduce(0) { $0 + $1.fileCount }, statistics.fileCount)
    }
    func testHiddenFilePreferenceExcludesWholeSubtreesAndTheirFolders() {
        let index = VaultIndex([
            TreeEntry(path: ".obsidian/plugins/config.json", sha: "a", size: 20),
            TreeEntry(path: "notes/.draft.md", sha: "b", size: 30),
            TreeEntry(path: ".gitignore", sha: "c", size: 5),
            TreeEntry(path: "notes/visible.md", sha: "d", size: 10)
        ])
        let all = VaultStatistics(index: index)
        XCTAssertEqual(all.fileCount, 4)
        XCTAssertEqual(all.folderCount, 3)
        XCTAssertEqual(all.knownBytes, 65)
        let visible = VaultStatistics(index: index, hideDotFiles: true)
        XCTAssertEqual(visible.fileCount, 1)
        XCTAssertEqual(visible.folderCount, 1)
        XCTAssertEqual(visible.knownBytes, 10)
        XCTAssertEqual(visible.fileTypes.map(\.ext), ["md"])
    }
    func testEmptyCatalogAndRefreshReplaceTotals() {
        let empty = VaultStatistics(index: VaultIndex())
        XCTAssertEqual(empty.fileCount, 0)
        XCTAssertEqual(empty.folderCount, 0)
        XCTAssertEqual(empty.knownBytes, 0)
        XCTAssertEqual(empty.unknownSizeCount, 0)
        XCTAssertTrue(empty.fileTypes.isEmpty)
        let changed = VaultStatistics(index: VaultIndex([TreeEntry(path: "file.pdf", sha: "a", size: nil)]))
        XCTAssertEqual(changed.fileCount, 1)
        XCTAssertEqual(changed.unknownSizeCount, 1)
        XCTAssertEqual(changed.fileTypes.map(\.ext), ["pdf"])
    }
}
