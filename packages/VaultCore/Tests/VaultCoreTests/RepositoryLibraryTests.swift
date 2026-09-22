import XCTest
@testable import VaultCore

final class RepositoryLibraryTests: XCTestCase {
    func testProfilesDeduplicateByRepositoryAndBranchAndPersistNoCredential() throws {
        var a = RepositoryConfig(); a.owner = "Example"; a.repo = "Notes"
        var b = a; b.repo = "work"
        var branch = a; branch.branch = "archive"
        var library = RepositoryLibrary([a, b, branch])
        a.home = "index.md"; library.remember(a)
        XCTAssertEqual(library.repositories.count, 3)
        XCTAssertEqual(library.repositories[0].home, "index.md")
        XCTAssertNotEqual(a.storageKey, branch.storageKey)
        XCTAssertEqual(a.identity, branch.identity)
        let restored = try JSONDecoder().decode(RepositoryLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(restored.repositories, library.repositories)
    }
}
