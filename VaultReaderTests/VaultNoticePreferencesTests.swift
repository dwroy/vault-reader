import XCTest
import VaultCore
@testable import VaultReader

final class VaultNoticePreferencesTests: XCTestCase {
    @MainActor func testDismissalPersistsForVaultBranchAndDoesNotLeakToOtherScopes() throws {
        let suite = "VaultNoticeTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var config = RepositoryConfig(); config.owner = "example"; config.repo = "notes"
        let preferences = VaultNoticePreferences(defaults: defaults)
        XCTAssertFalse(preferences.isDismissed(for: config, isSample: false))
        preferences.dismiss(for: config, isSample: false)
        let reopened = VaultNoticePreferences(defaults: defaults)
        XCTAssertTrue(reopened.isDismissed(for: config, isSample: false))
        XCTAssertFalse(reopened.isDismissed(for: config, isSample: true))
        var other = config; other.repo = "photos"
        XCTAssertFalse(reopened.isDismissed(for: other, isSample: false))
        other = config; other.branch = "archive"
        XCTAssertFalse(reopened.isDismissed(for: other, isSample: false))
        other = config; other.provider = .gitlab
        XCTAssertFalse(reopened.isDismissed(for: other, isSample: false))
        reopened.dismiss(for: config, isSample: true)
        reopened.resetSample(for: config)
        XCTAssertTrue(reopened.isDismissed(for: config, isSample: false), "UI fixture resets cannot clear the real-vault preference")
        XCTAssertFalse(reopened.isDismissed(for: config, isSample: true))
    }
}
