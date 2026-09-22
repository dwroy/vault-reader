import XCTest
@testable import VaultCore

@MainActor final class BlobStoreTests: XCTestCase {
    func testBlobIntegrityPinningAndEviction() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BlobStore(root: root)
        let md = Data("# Kept".utf8), pdf = Data("%PDF-test".utf8)
        let note = TreeEntry(path: "note.md", sha: BlobStore.hash(md), size: md.count)
        let file = TreeEntry(path: "a.pdf", sha: BlobStore.hash(pdf), size: pdf.count)
        try await store.put(md, entry: note); try await store.put(pdf, entry: file)
        let preview = try await store.previewURL(sha: file.sha, filename: "a.pdf")
        XCTAssertEqual(preview.pathExtension, "pdf")
        do { try await store.put(pdf, entry: note); XCTFail("Corrupt blob accepted") } catch { XCTAssertEqual(error as? VaultError, .corruptBlob) }
        try await store.evict(to: 0)
        let cached = try await store.data(for: note.sha), removed = try await store.data(for: file.sha)
        XCTAssertEqual(cached, md); XCTAssertNil(removed)
        let reopened = try BlobStore(root: root)
        try await reopened.evict(to: 0)
        let preserved = try await reopened.data(for: note.sha)
        XCTAssertEqual(preserved, md)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preview.path))
    }
    func testKnownGitHashAndInvalidKey() async throws {
        XCTAssertEqual(BlobStore.hash(Data("hello\n".utf8)), "ce013625030ba8dba906f756967f9e9ca394464a")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BlobStore(root: root)
        do { _ = try await store.data(for: "../outside"); XCTFail("Traversal accepted") } catch { XCTAssertEqual(error as? VaultError, .corruptBlob) }
    }
}
