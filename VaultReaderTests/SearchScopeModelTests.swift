import XCTest
import VaultCore
@testable import VaultReader

final class SearchScopeModelTests: XCTestCase {
    @MainActor func testDefaultScopeAndSamePathResultsKeepTheirRepository() async throws {
        let state = AppState(); try await state.startDemoForTesting()
        let original = state.config, saved = UserDefaults.standard.data(forKey: "repository")
        let scope = SearchScopeModel(); defer { scope.stop(); state.stopPrefetch() }
        scope.followCurrent(state); await scope.load(state)
        XCTAssertEqual(scope.selected, [original.storageKey])
        XCTAssertTrue(scope.contexts[original.storageKey] === state)
        let other = try XCTUnwrap(state.library.repositories.first { $0.storageKey != original.storageKey })
        scope.toggle(other); await scope.load(state)
        for context in scope.contexts.values {
            for _ in 0..<200 where context.isPrefetching { try await Task.sleep(for: .milliseconds(10)) }
        }
        let second = try XCTUnwrap(scope.contexts[other.storageKey])
        XCTAssertFalse(second === state)
        XCTAssertTrue(second.fileDisplay === state.fileDisplay)
        XCTAssertEqual(state.config, original)
        XCTAssertEqual(UserDefaults.standard.data(forKey: "repository"), saved)
        let firstData = try await state.file("README.md"), secondData = try await second.file("README.md")
        XCTAssertNotEqual(firstData, secondData)
        XCTAssertTrue(String(decoding: secondData, as: UTF8.self).contains("第二个知识库"))
        for config in state.library.repositories {
            let context = try XCTUnwrap(scope.contexts[config.storageKey])
            scope.results[config.storageKey]?.update(query: "README", repository: config.storageKey, engine: context.searchIndex, revision: context.searchRevision, hideDotFiles: false)
        }
        for _ in 0..<100 where scope.results.values.contains(where: { $0.searching }) { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(scope.results[original.storageKey]?.hits.map(\.path), ["README.md"])
        XCTAssertEqual(scope.results[other.storageKey]?.hits.map(\.path), ["README.md"])
        XCTAssertEqual(scope.results[other.storageKey]?.displayedRepository, other.storageKey)
        let secondHits = try await second.searchIndex.search("第二个")
        XCTAssertEqual(secondHits.map(\.path), ["README.md"])
        let firstHits = try await state.searchIndex.search("第二个")
        XCTAssertTrue(firstHits.isEmpty)
        scope.toggle(other); await scope.load(state)
        XCTAssertNil(scope.contexts[other.storageKey]); XCTAssertNil(scope.results[other.storageKey])
        XCTAssertEqual(scope.selected, [original.storageKey])
        scope.toggle(original); await scope.load(state)
        XCTAssertTrue(scope.selected.isEmpty); XCTAssertTrue(scope.contexts.isEmpty)
        scope.followCurrent(state)
        XCTAssertTrue(scope.selected.isEmpty, "An explicit empty selection survives returning to Search")
        await state.selectRepository(other); scope.followCurrent(state)
        XCTAssertEqual(scope.selected, [other.storageKey], "A newly active vault starts with its own default scope")
    }
    @MainActor func testAuxiliaryBudgetAndNoCachedCatalogRemainBounded() async throws {
        let state = AppState(); try await state.startDemoForTesting()
        let scope = SearchScopeModel(); defer { scope.stop(); state.stopPrefetch() }
        var third = state.config; third.repo = "uncached-" + UUID().uuidString
        state.library.remember(third)
        scope.followCurrent(state)
        for config in state.library.repositories where config != state.config { scope.toggle(config) }
        await scope.load(state)
        let extra = scope.contexts.filter { $0.key != state.config.storageKey }.map(\.value)
        XCTAssertEqual(extra.count, 2)
        XCTAssertEqual(extra.reduce(0) { $0 + $1.searchIndex.limits.residentBytes }, SearchLimits().residentBytes)
        let empty = try XCTUnwrap(scope.contexts[third.storageKey])
        XCTAssertTrue(empty.ready); XCTAssertTrue(empty.index.entries.isEmpty)
        scope.toggle(third); await scope.load(state)
        let remaining = try XCTUnwrap(scope.contexts[state.library.repositories[1].storageKey])
        XCTAssertEqual(remaining.searchIndex.limits.residentBytes, SearchLimits().residentBytes)
    }
}
