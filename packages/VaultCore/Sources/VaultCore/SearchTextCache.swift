import Foundation
import CryptoKit

/// One branch's disposable derived text. The caller supplies an already repository/branch-scoped root.
/// Original blobs and the current tree remain authoritative; no manifest can expose obsolete paths.
struct SearchTextCache: Sendable {
    // Bump when the Markdown projection, case folding, checkpoint layout or storage format changes.
    static let schemaVersion = 1
    static let maximumEntryBytes = 256 * 1024 * 1024
    struct Envelope: Codable {
        let version: Int
        let sha: String
        let checksum: Data
        let payload: Data
    }
    let root: URL
    private var prepared = false
    init(root: URL) { self.root = root }
    func url(for sha: String) -> URL { root.appendingPathComponent(MetaStore.key(sha) + ".searchtext") }
    func load(sha: String) -> SearchDocument? {
        let file = url(for: sha)
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maximumEntryBytes, let data = try? Data(contentsOf: file) else { return nil }
        // IO failures (e.g. a locked device) leave the cache alone; invalid cache bytes are discarded.
        if let envelope = try? PropertyListDecoder().decode(Envelope.self, from: data),
           envelope.version == Self.schemaVersion, envelope.sha == sha,
           Data(SHA256.hash(data: envelope.payload)) == envelope.checksum,
           let stored = try? PropertyListDecoder().decode(SearchDocument.Stored.self, from: envelope.payload),
           let document = SearchDocument(stored: stored) { return document }
        try? FileManager.default.removeItem(at: file)
        return nil
    }
    mutating func save(_ document: SearchDocument, sha: String) throws {
        if !prepared {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var directory = root; try directory.setResourceValues(values)
            prepared = true
        }
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let payload = try encoder.encode(document.stored)
        let envelope = Envelope(version: Self.schemaVersion, sha: sha, checksum: Data(SHA256.hash(data: payload)), payload: payload)
        let data = try encoder.encode(envelope)
        guard data.count <= Self.maximumEntryBytes else { throw VaultError.tooLarge }
        try data.writeProtected(to: url(for: sha))
    }
    func prune(keeping shas: Set<String>) {
        let names = Set(shas.map { url(for: $0).lastPathComponent })
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "searchtext" && !names.contains(file.lastPathComponent) {
            guard !Task.isCancelled else { return }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
