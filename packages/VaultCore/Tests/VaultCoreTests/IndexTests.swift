import XCTest
@testable import VaultCore
final class IndexTests: XCTestCase {
    func testTraversalCannotEscapeVault() {
        XCTAssertNil(VaultIndex.normalized("../../private"))
        XCTAssertNil(VaultIndex.normalized("/etc/passwd"))
        XCTAssertEqual(VaultIndex.normalized("notes/../README.md"), "README.md")
    }
    func testDirectoryListingAndDeletedFileDiff() {
        let entries = [TreeEntry(path: "README.md", sha: "a", size: 1), TreeEntry(path: "生活/日记.md", sha: "b", size: 2)]
        let original = VaultIndex(entries), updated = VaultIndex([entries[1]])
        XCTAssertEqual(original.children(of: "").map(\.name), ["生活", "README.md"])
        XCTAssertEqual(original.children(of: "生活").map(\.name), ["日记.md"])
        XCTAssertEqual(updated.changedCount(from: original), 1)
    }
}
