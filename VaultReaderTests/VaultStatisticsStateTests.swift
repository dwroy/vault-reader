import XCTest
import VaultCore
@testable import VaultReader

final class VaultStatisticsStateTests: XCTestCase {
    @MainActor func testCatalogReplacementResetsBothVisibilitySnapshots() throws {
        let suite = "VaultStatisticsTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FileDisplayPreferences(defaults: defaults)
        let state = AppState(searchConfig: RepositoryConfig(), sample: true, limits: SearchLimits(), fileDisplay: preferences)
        state.index = VaultIndex([
            TreeEntry(path: "notes/readme.md", sha: "a", size: 10),
            TreeEntry(path: ".hidden/file.pdf", sha: "b", size: nil)
        ])
        XCTAssertEqual(state.vaultStatistics.fileCount, 2)
        XCTAssertEqual(state.vaultStatistics.unknownSizeCount, 1)
        XCTAssertEqual(state.vaultStatisticsHidingDotFiles.fileCount, 1)
        XCTAssertEqual(state.vaultStatisticsHidingDotFiles.unknownSizeCount, 0)
        state.index = VaultIndex([TreeEntry(path: "new.txt", sha: "c", size: 30)])
        XCTAssertEqual(state.vaultStatistics.fileTypes.map(\.ext), ["txt"])
        XCTAssertEqual(state.vaultStatisticsHidingDotFiles.knownBytes, 30)
        state.index = VaultIndex()
        XCTAssertEqual(state.vaultStatistics.fileCount, 0)
        XCTAssertTrue(state.vaultStatisticsHidingDotFiles.fileTypes.isEmpty)
    }
}
