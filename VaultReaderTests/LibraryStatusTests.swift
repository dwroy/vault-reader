import XCTest
import UIKit
import VaultCore
@testable import VaultReader

final class LibraryStatusTests: XCTestCase {
    func testFailureKindsDoNotMislabelTimeoutAsOfflineOrSuccess() {
        for error in [VaultError.network(URLError.timedOut.rawValue), .network(URLError.cannotFindHost.rawValue), .http(503)] {
            let status = LibraryStatus.failure(error)
            XCTAssertEqual(status.kind, .notUpdated)
            XCTAssertEqual(status.action, .retry)
            XCTAssertTrue(status.needsAttention)
            XCTAssertEqual(status.message, error.localizedDescription)
        }
        XCTAssertEqual(LibraryStatus.failure(URLError(.timedOut)).kind, .notUpdated)
        XCTAssertEqual(LibraryStatus.failure(VaultError.network(URLError.notConnectedToInternet.rawValue)).kind, .offline)
        XCTAssertEqual(LibraryStatus.failure(VaultError.unauthorized).action, .settings)
        XCTAssertEqual(LibraryStatus.failure(VaultError.forbidden).kind, .authorization)
        XCTAssertEqual(LibraryStatus.failure(VaultError.rateLimited(nil)).kind, .rateLimited)
        XCTAssertEqual(LibraryStatus.failure(VaultError.corruptBlob).action, .none, "A library refresh cannot retry a failed file operation")
    }
    func testStatusSymbolsExistAndShortLabelsAreLocalized() {
        let kinds: [LibraryStatus.Kind] = [.updating, .notUpdated, .offline, .authorization, .rateLimited, .sample, .cached, .attention]
        for kind in kinds {
            let status = LibraryStatus(kind: kind, message: "Synthetic detail", action: .none)
            XCTAssertNotNil(UIImage(systemName: status.symbol), status.symbol)
            for language in L10n.supported {
                let english = L10n.text("Library status", language: language)
                XCTAssertFalse(english.isEmpty)
            }
        }
        XCTAssertEqual(L10n.text("Not updated", language: "zh-Hans"), "未更新")
        XCTAssertEqual(L10n.text("Sign in", language: "zh-Hans"), "待授权")
    }
    @MainActor func testUnchangedBranchClearsPreviousFailure() async throws {
        let state = AppState()
        try await state.startDemoForTesting(source: StatusSource())
        state.stopPrefetch(); state.demo = false
        defer { state.stopPrefetch() }
        state.libraryStatus = .failure(VaultError.network(URLError.timedOut.rawValue))
        await state.refresh()
        XCTAssertNil(state.libraryStatus, "A successful 304 must clear the old timeout")
        XCTAssertFalse(state.isRefreshing)
        XCTAssertTrue(state.canRefresh)
    }
    @MainActor func testRefreshFailureAndRepositorySwitchResetStatus() async throws {
        let state = AppState()
        try await state.startDemoForTesting(source: StatusSource(error: .network(URLError.timedOut.rawValue)))
        state.stopPrefetch(); state.demo = false
        defer { state.stopPrefetch() }
        await state.refresh()
        XCTAssertEqual(state.libraryStatus?.kind, .notUpdated)
        XCTAssertFalse(state.isRefreshing)
        state.demo = true
        let other = try XCTUnwrap(state.library.repositories.first { $0.storageKey != state.config.storageKey })
        await state.selectRepository(other)
        XCTAssertEqual(state.libraryStatus?.kind, .sample)
        XCTAssertFalse(state.canRefresh)
    }
}

private actor StatusSource: RepositorySource {
    let error: VaultError?
    init(error: VaultError? = nil) { self.error = error }
    func branch(etag: String?) async throws -> BranchSnapshot? {
        if let error { throw error }; return nil
    }
    func tree(sha: String) async throws -> GitTree { throw VaultError.missing }
    func blob(_ entry: TreeEntry, progress: (@Sendable (Double) -> Void)?) async throws -> Data { throw VaultError.missing }
    func recent(etag: String?) async throws -> RecentSnapshot? { nil }
    func commitFiles(sha: String) async throws -> CommitFiles { throw VaultError.missing }
}
