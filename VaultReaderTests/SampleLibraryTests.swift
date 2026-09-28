import XCTest
import VaultCore
@testable import VaultReader

final class SampleLibraryTests: XCTestCase {
    @MainActor func testSamplesPreserveSavedConnectionAndRestoreWelcome() async throws {
        let defaults = UserDefaults.standard
        let keys = ["repository", "repositoryLibrary", "sampleLibraryActive"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        let state = AppState()
        try await state.startSamples()
        XCTAssertTrue(state.demo); XCTAssertTrue(state.reading.isSample)
        XCTAssertFalse(state.needsSetup)
        XCTAssertNil(defaults.data(forKey: "repository"))
        XCTAssertNil(defaults.data(forKey: "repositoryLibrary"))
        let reopened = AppState(); await reopened.start()
        XCTAssertTrue(reopened.demo)
        XCTAssertEqual(reopened.index.entries.filter { $0.ext == "pdf" }.count, 1)
        await reopened.leaveSamples()
        XCTAssertFalse(reopened.demo); XCTAssertTrue(reopened.needsSetup)
        XCTAssertTrue(reopened.library.repositories.isEmpty)
        XCTAssertTrue(reopened.index.entries.isEmpty)
        XCTAssertTrue(reopened.config.owner.isEmpty)
        state.stopPrefetch(); reopened.stopPrefetch()

        var real = RepositoryConfig(); real.owner = "test-example"; real.repo = "preserved-connection"
        let connection = try JSONEncoder().encode(real)
        let library = try JSONEncoder().encode(RepositoryLibrary([real]))
        defaults.set(connection, forKey: "repository"); defaults.set(library, forKey: "repositoryLibrary")
        let connected = AppState(); try await connected.startSamples()
        XCTAssertEqual(defaults.data(forKey: "repository"), connection)
        XCTAssertEqual(defaults.data(forKey: "repositoryLibrary"), library)
        await connected.leaveSamples()
        XCTAssertEqual(connected.config, real)
        XCTAssertEqual(connected.library.repositories, [real])
        connected.stopPrefetch()
    }

    @MainActor func testSampleReadingAndHTMLCannotOverlapRealRepository() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var config = RepositoryConfig(); config.owner = "example"; config.repo = "synthetic-vault"
        let sample = ReadingStore(config: config, root: root, isSample: true)
        let session = BookSession(path: "README.md", kind: .markdown, store: sample)
        session.save(.init(fraction: 0.5)); sample.flush()
        XCTAssertTrue(ReadingStore(config: config, root: root).history.records.isEmpty)
        XCTAssertFalse(ReadingStore(config: config, root: root, isSample: true).history.records.isEmpty)
        XCTAssertNotEqual(HTMLLocation(config: config, path: "reader.html").host,
                          HTMLLocation(config: config, path: "reader.html", isSample: true).host)
    }
}
