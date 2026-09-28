import XCTest
import CryptoKit
@testable import VaultCore

final class SearchPersistenceTests: XCTestCase {
    private struct Note {
        let entry: TreeEntry
        let text: String
        init(_ path: String, _ text: String) {
            self.text = text
            let data = Data(text.utf8)
            entry = TreeEntry(path: path, sha: BlobStore.hash(data), size: data.count)
        }
    }
    private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("search-tests-" + UUID().uuidString) }

    func testRestoreNeedsNoMarkdownAndPreservesUnicodeSnippetsAndDuplicatePaths() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let note = Note("a.md", String(repeating: "é👨‍👩‍👧原文 ", count: 200) + "**公园**散步 CAFÉ café StraßE")
        let alias = TreeEntry(path: "renamed.md", sha: note.entry.sha, size: note.entry.size)
        let attachment = TreeEntry(path: "attachment.pdf", sha: note.entry.sha, size: note.entry.size)
        let empty = Note("empty.md", "")
        let entries = [note.entry, alias, attachment, empty.entry]
        let first = SearchIndex(cacheDirectory: root)
        await first.update(entries); await first.insert(note.text, for: note.entry); await first.insert(empty.text, for: empty.entry)
        let before = try await first.search("公园散步 cafe")
        let reopened = SearchIndex(cacheDirectory: root)
        await reopened.update(entries)
        for entry in entries where entry.isMarkdown {
            let restored = await reopened.restoreCachedText(for: entry)
            XCTAssertTrue(restored)
        }
        let after = try await reopened.search("公园散步 cafe"), count = await reopened.count, stats = await reopened.diagnostics
        XCTAssertEqual(after.map(\.path), before.map(\.path)); XCTAssertEqual(after.map(\.snippet), before.map(\.snippet))
        XCTAssertEqual(after.map(\.bodyTerms), before.map(\.bodyTerms))
        XCTAssertEqual(after.map(\.path), ["a.md", "renamed.md"])
        XCTAssertEqual(count, 3); XCTAssertEqual(stats.builtDocuments, 0); XCTAssertEqual(stats.restoredDocuments, 2)
        XCTAssertEqual(stats.cacheWriteFailures, 0)
        let excluded = try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertEqual(excluded, true)
    }
    func testTreeChangesReuseRenamesAndRebuildOnlyChangedOrAddedText() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let a = Note("old-name.md", "名字改变正文不变"), b = Note("updated.md", "旧版本词语"), removed = Note("deleted.md", "删除后的词语")
        let first = SearchIndex(cacheDirectory: root)
        await first.update([a.entry, b.entry, removed.entry])
        for note in [a, b, removed] { await first.insert(note.text, for: note.entry) }
        let renamed = TreeEntry(path: "new-name.md", sha: a.entry.sha, size: a.entry.size)
        let updated = Note(b.entry.path, "修改后的正文"), added = Note("new.md", "新增正文")
        let entries = [renamed, updated.entry, added.entry]
        await first.update(entries)
        let memoryReuse = await first.restoreCachedText(for: renamed)
        XCTAssertTrue(memoryReuse)
        let warm = SearchIndex(cacheDirectory: root); await warm.update(entries)
        let renameHit = await warm.restoreCachedText(for: renamed), changedMiss = await warm.restoreCachedText(for: updated.entry)
        XCTAssertTrue(renameHit); XCTAssertFalse(changedMiss)
        await warm.insert(b.text, for: b.entry) // A stale download must never reappear.
        await warm.insert(updated.text, for: updated.entry); await warm.insert(added.text, for: added.entry)
        let stale = try await warm.search("旧版本词语"), deleted = try await warm.search("删除后的词语")
        XCTAssertTrue(stale.isEmpty); XCTAssertTrue(deleted.isEmpty)
        let renamedHit = try await warm.search("正文不变"), stats = await warm.diagnostics
        XCTAssertEqual(renamedHit.map(\.path), [renamed.path])
        XCTAssertEqual(stats.restoredDocuments, 1); XCTAssertEqual(stats.builtDocuments, 2)
        let cache = SearchTextCache(root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.url(for: b.entry.sha).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.url(for: removed.entry.sha).path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 3)
    }
    func testRepositoryAndBranchNamespacesRemainIndependent() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let locations = ["repo-a/main", "repo-a/feature", "repo-b/main"]
        for location in locations {
            let note = Note("same.md", location)
            let index = SearchIndex(cacheDirectory: root.appendingPathComponent(location))
            await index.update([note.entry]); await index.insert(note.text, for: note.entry)
        }
        let cleared = SearchIndex(cacheDirectory: root.appendingPathComponent(locations[1]))
        await cleared.update([])
        for location in [locations[0], locations[2]] {
            let note = Note("same.md", location)
            let index = SearchIndex(cacheDirectory: root.appendingPathComponent(location))
            await index.update([note.entry])
            let restored = await index.restoreCachedText(for: note.entry), result = try await index.search(location)
            XCTAssertTrue(restored); XCTAssertEqual(result.count, 1)
        }
    }
    func testCorruptionWrongSchemaAndInvalidOffsetsRebuildWithoutBreakingSearch() async throws {
        for failure in ["truncated", "checksum", "schema", "sha", "offset"] {
            let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
            let note = Note("note.md", "真实正文 café 🌿")
            let first = SearchIndex(cacheDirectory: root)
            await first.update([note.entry]); await first.insert(note.text, for: note.entry)
            let file = SearchTextCache(root: root).url(for: note.entry.sha)
            let envelope = try PropertyListDecoder().decode(SearchTextCache.Envelope.self, from: Data(contentsOf: file))
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            var payload = envelope.payload, checksum = envelope.checksum
            if failure == "offset" {
                let invalid = SearchDocument.Stored(text: "text", folded: Data("text".utf8), checkpoints: [.init(foldedOffset: 0, originalOffset: -1)])
                payload = try encoder.encode(invalid); checksum = Data(SHA256.hash(data: payload))
            } else if failure == "checksum" { checksum = Data([1, 2, 3]) }
            let broken = SearchTextCache.Envelope(version: failure == "schema" ? 0 : envelope.version, sha: failure == "sha" ? "wrong" : envelope.sha, checksum: checksum, payload: payload)
            try (failure == "truncated" ? Data([0, 1, 2]) : encoder.encode(broken)).write(to: file)
            let warm = SearchIndex(cacheDirectory: root); await warm.update([note.entry])
            let restored = await warm.restoreCachedText(for: note.entry)
            XCTAssertFalse(restored, failure)
            await warm.insert(note.text, for: note.entry)
            let results = try await warm.search("cafe"), stats = await warm.diagnostics
            XCTAssertEqual(results.count, 1, failure); XCTAssertEqual(stats.builtDocuments, 1)
            let repaired = SearchIndex(cacheDirectory: root); await repaired.update([note.entry])
            let usable = await repaired.restoreCachedText(for: note.entry)
            XCTAssertTrue(usable, failure)
        }
    }
    func testUnavailableCacheFallsBackToMemory() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a directory".utf8).write(to: root)
        let note = Note("note.md", "仍然可以搜索")
        let index = SearchIndex(cacheDirectory: root); await index.update([note.entry])
        let restored = await index.restoreCachedText(for: note.entry)
        XCTAssertFalse(restored)
        await index.insert(note.text, for: note.entry)
        let results = try await index.search("可以"), stats = await index.diagnostics
        XCTAssertEqual(results.count, 1); XCTAssertEqual(stats.cacheWriteFailures, 1)
    }
    func testCancelledPreparationDoesNotPruneOrWriteCache() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let note = Note("note.md", "保留已有索引")
        let index = SearchIndex(cacheDirectory: root); await index.update([note.entry]); await index.insert(note.text, for: note.entry)
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream { break }
            await index.update([])
            return await index.restoreCachedText(for: note.entry)
        }
        task.cancel(); continuation.finish()
        let restored = await task.value
        XCTAssertFalse(restored)
        let results = try await index.search("保留")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: SearchTextCache(root: root).url(for: note.entry.sha).path))
    }
    func testColdPreparationAndWarmRestoreMeasurement() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let notes = (0..<400).map { Note("note-\($0).md", "# Note \($0)\n\n" + String(repeating: "普通正文 some words. ", count: 650) + "独特匹配 CAFÉ") }
        let cold = SearchIndex(cacheDirectory: root), start = ContinuousClock.now
        await cold.update(notes.map(\.entry))
        for note in notes { await cold.insert(note.text, for: note.entry) }
        let preparation = start.duration(to: .now), warm = SearchIndex(cacheDirectory: root), reopened = ContinuousClock.now
        await warm.update(notes.map(\.entry))
        for note in notes { _ = await warm.restoreCachedText(for: note.entry) }
        let restoration = reopened.duration(to: .now), stats = await warm.diagnostics
        let queryStart = ContinuousClock.now
        let hits = try await warm.search("独特匹配 cafe")
        let queryTime = queryStart.duration(to: .now)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        print("Search persistence >5 MB / 400 documents: cold=\(preparation), warm=\(restoration), query=\(queryTime), cacheBytes=\(bytes)")
        XCTAssertEqual(stats.restoredDocuments, 400); XCTAssertEqual(stats.builtDocuments, 0)
        XCTAssertEqual(hits.count, 400); XCTAssertLessThan(queryTime, .milliseconds(200))
    }
}
