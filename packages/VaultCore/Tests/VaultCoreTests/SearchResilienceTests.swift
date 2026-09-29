import XCTest
@testable import VaultCore

private actor BuildFlag {
    private(set) var finished = false
    func finish() { finished = true }
}
final class SearchResilienceTests: XCTestCase {
    private func note(_ path: String, _ data: Data, knownSize: Bool = true) -> TreeEntry {
        TreeEntry(path: path, sha: BlobStore.hash(data), size: knownSize ? data.count : nil)
    }
    func testNonTextAndKnownOversizedFilesRemainSearchableByMetadata() async throws {
        let limits = SearchLimits(sourceBytes: 16)
        let index = SearchIndex(limits: limits)
        let image = TreeEntry(path: "photos/holiday.png", sha: "abc123456789", size: 4096)
        let pdf = TreeEntry(path: "reports/year.pdf", sha: "def123456789", size: 8000)
        let large = TreeEntry(path: "books/large.md", sha: "aaa123456789", size: 100)
        await index.update([image, pdf, large])
        await index.insert("This body must not be indexed", for: large)
        let pictures = try await index.search("图片 holiday"), type = try await index.search("application/pdf"), size = try await index.search("4096"), sha = try await index.search("abc1234")
        XCTAssertEqual(pictures.map(\.path), [image.path]); XCTAssertEqual(type.map(\.path), [pdf.path])
        XCTAssertEqual(size.map(\.path), [image.path]); XCTAssertEqual(sha.map(\.path), [image.path])
        let body = try await index.search("must"), coverage = await index.coverage, stats = await index.diagnostics
        XCTAssertTrue(body.isEmpty); XCTAssertEqual(coverage.pending, 0); XCTAssertEqual(coverage.metadataOnly, 3)
        XCTAssertEqual(coverage.oversized, 1); XCTAssertEqual(stats.builtDocuments, 0)
        XCTAssertEqual(pictures.first?.metadataOnlyReason, .fileType)
        let largeHit = try await index.search("large")
        XCTAssertEqual(largeHit.first?.metadataOnlyReason, .tooLarge)
    }
    func testUnknownSizeAndInvalidEncodingDecisionsSurviveRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data(String(repeating: "x", count: 32).utf8), invalidData = Data([0xff, 0xfe])
        let large = note("large.md", data, knownSize: false), invalid = note("invalid.txt", invalidData)
        let limits = SearchLimits(sourceBytes: 16)
        let first = SearchIndex(cacheDirectory: root, limits: limits)
        await first.update([large, invalid]); await first.insert(data: data, for: large); await first.insert(data: invalidData, for: invalid)
        let warm = SearchIndex(cacheDirectory: root, limits: limits)
        await warm.update([large, invalid]); _ = await warm.restoreCachedText(for: large); _ = await warm.restoreCachedText(for: invalid)
        let needsLarge = await warm.needsBody(for: large), needsInvalid = await warm.needsBody(for: invalid), coverage = await warm.coverage
        XCTAssertFalse(needsLarge); XCTAssertFalse(needsInvalid); XCTAssertEqual(coverage.metadataOnly, 2); XCTAssertEqual(coverage.pending, 0)
        // Raising a future source limit must reconsider the old size decision.
        let raised = SearchIndex(cacheDirectory: root, limits: SearchLimits(sourceBytes: 64))
        await raised.update([large]); _ = await raised.restoreCachedText(for: large)
        let retry = await raised.needsBody(for: large)
        XCTAssertTrue(retry); await raised.insert(data: data, for: large)
        let results = try await raised.search("xxxx")
        XCTAssertEqual(results.count, 1)
    }
    func testMarkdownAndPlainTextWithSameSHAUseDifferentProjections() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("**bold**".utf8), md = note("one.md", data), txt = note("two.txt", data)
        let first = SearchIndex(cacheDirectory: root)
        await first.update([md, txt]); await first.insert(data: data, for: md); await first.insert(data: data, for: txt)
        let warm = SearchIndex(cacheDirectory: root); await warm.update([md, txt])
        _ = await warm.restoreCachedText(for: md); _ = await warm.restoreCachedText(for: txt)
        let literal = try await warm.search("**bold**"), plain = try await warm.search("bold")
        XCTAssertEqual(literal.map(\.path), [txt.path]); XCTAssertEqual(plain.count, 2)
        XCTAssertEqual(plain.first(where: { $0.path == md.path })?.snippet, "bold")
        XCTAssertEqual(plain.first(where: { $0.path == txt.path })?.snippet, "**bold**")
    }
    func testMemoryAndDocumentLimitsKeepMetadataAndRecoverAfterTreeChange() async throws {
        let limits = SearchLimits(residentBytes: 4096, documentCount: 2)
        let index = SearchIndex(limits: limits)
        let data = (0..<3).map { Data(("unique-\($0) " + String(repeating: "x", count: 180)).utf8) }
        let entries = data.enumerated().map { note("note-\($0).txt", $1) }
        await index.update(entries)
        for (entry, value) in zip(entries, data) { await index.insert(data: value, for: entry) }
        let coverage = await index.coverage
        XCTAssertLessThanOrEqual(coverage.residentBytes, limits.residentBytes); XCTAssertEqual(coverage.indexed, 2)
        XCTAssertEqual(coverage.metadataOnly, 1); XCTAssertEqual(coverage.limited, 1); XCTAssertEqual(coverage.pending, 0)
        let names = try await index.search("note-")
        XCTAssertEqual(names.count, 3); XCTAssertEqual(names.last?.metadataOnlyReason, .memoryBudget)
        await index.update([entries[2]]); await index.insert(data: data[2], for: entries[2])
        let recovered = try await index.search("unique-2")
        XCTAssertEqual(recovered.count, 1); XCTAssertNil(recovered[0].metadataOnlyReason)
    }
    func testResidentBudgetStopsBodyWorkAndRetainsSearchableMetadata() async throws {
        let data = (0..<3).map { Data(("distinct-\($0) " + String(repeating: "x", count: 512)).utf8) }
        let entries = data.enumerated().map { note("note-\($0).txt", $1) }
        let index = SearchIndex(limits: SearchLimits(residentBytes: 3200))
        await index.update(entries)
        for (entry, value) in zip(entries, data) { await index.insert(data: value, for: entry) }
        let coverage = await index.coverage, stats = await index.diagnostics
        XCTAssertEqual(coverage.indexed, 1); XCTAssertEqual(coverage.metadataOnly, 2)
        XCTAssertEqual(coverage.limited, 2); XCTAssertEqual(coverage.pending, 0)
        XCTAssertLessThanOrEqual(coverage.residentBytes, 3200); XCTAssertEqual(stats.builtDocuments, 1)
        let needsBody = await index.needsBody(for: entries[2])
        XCTAssertFalse(needsBody)
        let all = try await index.search("note-"), ready = try await index.search("distinct-0")
        XCTAssertEqual(all.count, 3); XCTAssertEqual(ready.count, 1)
        XCTAssertEqual(all.filter { $0.metadataOnlyReason == .memoryBudget }.count, 2)
    }
    func testCandidatePlanBoundsUnknownSizesAndSharesDuplicateBodies() async throws {
        let data = Data("shared content".utf8)
        let a = note("a.txt", data, knownSize: false), duplicate = note("z.txt", data, knownSize: false)
        let preferred = note("preferred.txt", Data("priority".utf8), knownSize: false)
        let rest = (0..<30).map { TreeEntry(path: "other-\($0).txt", sha: "unique-\($0)", size: nil) }
        let index = SearchIndex(limits: SearchLimits(documentCount: 2))
        await index.update([a, duplicate, preferred] + rest, preferredPath: preferred.path)
        let candidates = await index.bodyCandidates(preferredPath: preferred.path)
        XCTAssertEqual(candidates.map(\.path), [preferred.path, a.path, duplicate.path])
        let coverage = await index.coverage
        XCTAssertEqual(coverage.pending, 3); XCTAssertEqual(coverage.metadataOnly, 30)
        await index.insert(data: data, for: a)
        let built = await index.coverage
        XCTAssertEqual(built.indexed, 2, "Two paths reuse one retained body")
    }
    func testExistingSearchRunsDuringPreparationAndStaleBuildCannotPublish() async throws {
        let unit = "## Heading\n\n普通正文 **公园** some words.\n\n"
        let body = String(repeating: unit, count: 1024 * 1024 / unit.utf8.count)
        let data = Data(body.utf8), large = note("large.md", data), readyData = Data("ready body".utf8), ready = note("ready.md", readyData)
        let index = SearchIndex(limits: SearchLimits(sourceBytes: 2 * 1024 * 1024, documentBytes: 8 * 1024 * 1024))
        await index.update([ready, large]); await index.insert(data: readyData, for: ready)
        let flag = BuildFlag()
        let builder = Task.detached(priority: .utility) { await index.insert(data: data, for: large); await flag.finish() }
        try await Task.sleep(for: .milliseconds(60))
        let start = ContinuousClock.now
        let result = try await index.search("ready", fullText: false)
        let elapsed = start.duration(to: .now), finished = await flag.finished
        print("Query during 1 MB construction: \(elapsed); builderFinished=\(finished)")
        XCTAssertEqual(result.map(\.path), [ready.path]); XCTAssertFalse(finished, "Existing results publish before the build completes")
        XCTAssertLessThan(elapsed, .milliseconds(200))
        // Change the tree while preparation is still running; its old result must not be committed.
        await index.update([ready]); await builder.value
        let stale = try await index.search("公园"), count = await index.count
        XCTAssertTrue(stale.isEmpty); XCTAssertEqual(count, 1)
    }
    func testBoundedSearchResultsAndHiddenFiles() async throws {
        let index = SearchIndex()
        let files = (0..<600).map { TreeEntry(path: "photo-\($0).png", sha: String($0), size: 10) }
        await index.update(files + [TreeEntry(path: ".cache/hidden.png", sha: "hidden", size: 10)])
        let result = try await index.searchResults("image", hideDotFiles: true)
        XCTAssertEqual(result.total, 600); XCTAssertEqual(result.hits.count, 200)
        XCTAssertTrue(result.hits.allSatisfy { !$0.path.hasPrefix(".") && $0.metadataOnlyReason == .fileType })
        let exact = try await index.searchResults("photo-500.png", limit: 1)
        XCTAssertEqual(exact.hits.first?.path, "photo-500.png")
    }
    func testLibraryProfileCountsDocumentsNotAttachmentBytesOrConfigurationFiles() {
        let one = TreeEntry(path: "README.md", sha: "a", size: 10)
        let movie = TreeEntry(path: "film.mp4", sha: "b", size: 10_000_000_000)
        XCTAssertFalse(VaultContentProfile([one, movie]).needsSuitabilityNotice)
        let config = (0..<20).map { TreeEntry(path: ".obsidian/\($0).png", sha: String($0), size: 1) }
        XCTAssertFalse(VaultContentProfile([one] + config).needsSuitabilityNotice)
        let images = (0..<5).map { TreeEntry(path: "photos/\($0).png", sha: String($0), size: 1) }
        XCTAssertTrue(VaultContentProfile([one] + images).needsSuitabilityNotice)
        XCTAssertTrue(VaultContentProfile([movie]).needsSuitabilityNotice)
        XCTAssertFalse(VaultContentProfile([]).needsSuitabilityNotice)
    }
    func testNoteLibrariesWithAttachmentsAndNativePDFDoNotNeedSuitabilityWarning() {
        let notes = (0..<40).map { TreeEntry(path: "notes/\($0).md", sha: "note-\($0)", size: 100) }
        let images = (0..<60).map { TreeEntry(path: "files/\($0).jpeg", sha: "image-\($0)", size: 1000) }
        let profile = VaultContentProfile(notes + images)
        XCTAssertFalse(profile.needsSuitabilityNotice, "Illustrations can outnumber notes in a suitable reading vault")
        XCTAssertEqual(profile.readableFiles, 40)
        let pdfs = (0..<10).map { TreeEntry(path: "papers/\($0).pdf", sha: "pdf-\($0)", size: 1000) }
        XCTAssertFalse(VaultContentProfile(pdfs).needsSuitabilityNotice, "Native PDF reading is supported")
        XCTAssertFalse(VaultContentProfile([notes[0]] + Array(images.prefix(3))).needsSuitabilityNotice, "25 percent is not a clear mismatch")
        XCTAssertTrue(VaultContentProfile([notes[0]] + images).needsSuitabilityNotice, "A media archive with one README still receives guidance")
        let script = TreeEntry(path: "scripts/task.PS1", sha: "script", size: 100)
        XCTAssertEqual(VaultContentProfile([script]).textFiles, 1)
        XCTAssertTrue(SearchFileMetadata(script).isText)
    }
    func testCachedBlobLimitChecksBeforeReturningOversizedSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BlobStore(root: root), data = Data(repeating: 65, count: 4096), entry = note("source.md", Data(repeating: 65, count: 4096))
        try await store.put(data, entry: entry)
        do { _ = try await store.data(for: entry.sha, maximumBytes: 1024); XCTFail("Oversized source admitted") }
        catch { XCTAssertEqual(error as? VaultError, .tooLarge) }
        let original = try await store.data(for: entry.sha)
        XCTAssertEqual(original, data, "Indexing limits do not prevent an explicit normal file open")
    }
}
