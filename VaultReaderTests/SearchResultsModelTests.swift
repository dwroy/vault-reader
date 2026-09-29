import XCTest
import VaultCore
@testable import VaultReader

final class SearchResultsModelTests: XCTestCase {
    @MainActor func testIndexProgressDoesNotRestartInputDebounceOrStarveFirstResult() async throws {
        let engine = SearchIndex(), entry = TreeEntry(path: "result.md", sha: "a", size: 20)
        await engine.update([entry]); await engine.insert("独特正文", for: entry)
        let model = SearchResultsModel(), start = ContinuousClock.now
        defer { model.cancel() }
        model.update(query: "独特", repository: "one", engine: engine, revision: 0, hideDotFiles: false)
        var firstResult: Duration?
        for revision in 1...30 {
            try await Task.sleep(for: .milliseconds(20))
            model.update(query: "独特", repository: "one", engine: engine, revision: revision, hideDotFiles: false)
            if !model.hits.isEmpty && firstResult == nil { firstResult = start.duration(to: .now) }
        }
        XCTAssertEqual(model.hits.map(\.path), [entry.path])
        XCTAssertLessThan(try XCTUnwrap(firstResult), .milliseconds(400), "Results must arrive while progress keeps changing")
    }
    @MainActor func testNewQueryAndRepositoryReplaceOldResults() async throws {
        let one = SearchIndex(), two = SearchIndex()
        let a = TreeEntry(path: "alpha.md", sha: "a", size: 1), b = TreeEntry(path: "beta.md", sha: "b", size: 1)
        await one.update([a, b]); await one.insert("alpha", for: a); await one.insert("beta", for: b)
        await two.update([])
        let model = SearchResultsModel(); defer { model.cancel() }
        model.update(query: "alpha", repository: "one", engine: one, revision: 0, hideDotFiles: false)
        model.update(query: "beta", repository: "one", engine: one, revision: 0, hideDotFiles: false)
        for _ in 0..<50 where model.hits.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.hits.map(\.path), [b.path])
        model.update(query: "beta", repository: "two", engine: two, revision: 0, hideDotFiles: false)
        XCTAssertTrue(model.hits.isEmpty)
        for _ in 0..<50 where model.displayedRepository != "two" { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.displayedRepository, "two"); XCTAssertTrue(model.hits.isEmpty)
    }
    @MainActor func testPrefetchSkipsAttachmentsAndLargeFilesAndBoundsUnknownSizes() async throws {
        let id = UUID().uuidString, validData = Data("可以搜索正文 \(UUID().uuidString)".utf8)
        let known = TreeEntry(path: "a-large-\(id).md", sha: BlobStore.hash(Data((id + "a").utf8)), size: 8 * 1024 * 1024)
        let unknown = TreeEntry(path: "b-unknown-\(id).md", sha: BlobStore.hash(Data((id + "b").utf8)), size: nil)
        let image = TreeEntry(path: "c-image-\(id).png", sha: BlobStore.hash(Data((id + "c").utf8)), size: 1)
        let valid = TreeEntry(path: "d-small-\(id).txt", sha: BlobStore.hash(validData), size: validData.count)
        let source = BoundedSearchSource(unknown: unknown.path, valid: valid.path, data: validData)
        let state = AppState(); try await state.startDemoForTesting(source: source); state.stopPrefetch()
        state.index = VaultIndex([known, unknown, image, valid]); state.treeSHA = id; state.startPrefetch()
        defer { state.stopPrefetch() }
        for _ in 0..<200 where state.isPrefetching { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(state.isPrefetching); XCTAssertNil(state.prefetchError)
        XCTAssertEqual(state.searchCoverage.indexed, 1); XCTAssertEqual(state.searchCoverage.metadataOnly, 3); XCTAssertEqual(state.searchCoverage.pending, 0)
        let requested = await source.requested
        XCTAssertEqual(requested.map(\.path), [unknown.path, valid.path])
        XCTAssertTrue(requested.allSatisfy { $0.limit == 512 * 1024 })
        let hits = try await state.searchIndex.search("可以 搜索")
        XCTAssertEqual(hits.map(\.path), [valid.path])
        state.startPrefetch()
        for _ in 0..<200 where state.isPrefetching { try await Task.sleep(for: .milliseconds(25)) }
        let retried = await source.requested
        XCTAssertEqual(retried.count, 2, "A recorded oversized decision is not downloaded on every retry")
    }
}
private actor BoundedSearchSource: RepositorySource {
    struct Request: Sendable { let path: String; let limit: Int }
    let unknown: String, valid: String, data: Data
    private(set) var requested: [Request] = []
    init(unknown: String, valid: String, data: Data) { self.unknown = unknown; self.valid = valid; self.data = data }
    func branch(etag: String?) async throws -> BranchSnapshot? { nil }
    func tree(sha: String) async throws -> GitTree { throw VaultError.missing }
    func recent(etag: String?) async throws -> RecentSnapshot? { nil }
    func commitFiles(sha: String) async throws -> CommitFiles { throw VaultError.missing }
    func blob(_ entry: TreeEntry, progress: (@Sendable (Double) -> Void)?) async throws -> Data { XCTFail("Unbounded prefetch"); throw VaultError.missing }
    func blob(_ entry: TreeEntry, maximumBytes: Int, progress: (@Sendable (Double) -> Void)?) async throws -> Data {
        requested.append(Request(path: entry.path, limit: maximumBytes))
        if entry.path == unknown { throw VaultError.tooLarge }
        guard entry.path == valid else { throw VaultError.missing }; return data
    }
}
