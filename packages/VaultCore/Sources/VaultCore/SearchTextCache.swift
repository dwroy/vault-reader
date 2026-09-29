import Foundation
import CryptoKit

struct SearchTextCache: Sendable {
    // v2 adds text kind, source size and durable metadata-only decisions; v1 is safely rebuilt.
    static let schemaVersion = 2
    static let maximumEntryBytes = 4 * 1024 * 1024
    struct Envelope: Codable {
        let version: Int
        let sha: String
        let checksum: Data
        let payload: Data
        var kind: SearchTextKind = .markdown
        var sourceBytes: Int = 0
        var exclusion: SearchExclusion? = nil
        var decisionLimit: Int = 0
    }
    let root: URL
    private var prepared = false
    init(root: URL) { self.root = root }
    func url(for sha: String, kind: SearchTextKind = .markdown) -> URL {
        root.appendingPathComponent(MetaStore.key(kind.rawValue + ":" + sha) + ".searchtext")
    }
    func load(sha: String) -> SearchDocument? {
        if case .document(let document, _, _, _) = restore(sha: sha, kind: .markdown, limits: SearchLimits()) { return document }
        return nil
    }
    func restore(sha: String, kind: SearchTextKind, limits: SearchLimits) -> SearchPreparationResult {
        let file = url(for: sha, kind: kind)
        guard !Task.isCancelled,
              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maximumEntryBytes, let data = try? Data(contentsOf: file) else { return .missing }
        if let envelope = try? PropertyListDecoder().decode(Envelope.self, from: data),
           envelope.version == Self.schemaVersion, envelope.sha == sha, envelope.kind == kind,
           Data(SHA256.hash(data: envelope.payload)) == envelope.checksum {
            if let reason = envelope.exclusion {
                switch reason {
                case .tooLarge where limits.sourceBytes <= envelope.decisionLimit: return .excluded(reason)
                case .contentLimit where limits.documentBytes <= envelope.decisionLimit: return .excluded(reason)
                case .encoding: return .excluded(reason)
                default: return .missing
                }
            }
            if envelope.sourceBytes > limits.sourceBytes { return .excluded(.tooLarge) }
            if let stored = try? PropertyListDecoder().decode(SearchDocument.Stored.self, from: envelope.payload),
               let document = SearchDocument(stored: stored), !Task.isCancelled {
                guard document.memoryCost <= limits.documentBytes else { return .excluded(.contentLimit) }
                return .document(document, sourceBytes: envelope.sourceBytes, restored: true, writeFailed: false)
            }
        }
        try? FileManager.default.removeItem(at: file)
        return .missing
    }
    mutating func save(_ document: SearchDocument, sha: String, kind: SearchTextKind = .markdown, sourceBytes: Int = 0) throws {
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let payload = try encoder.encode(document.stored)
        var envelope = Envelope(version: Self.schemaVersion, sha: sha, checksum: Data(SHA256.hash(data: payload)), payload: payload)
        envelope.kind = kind; envelope.sourceBytes = sourceBytes
        try write(envelope)
    }
    mutating func saveExclusion(_ reason: SearchExclusion, sha: String, kind: SearchTextKind, limit: Int) throws {
        let payload = Data()
        var envelope = Envelope(version: Self.schemaVersion, sha: sha, checksum: Data(SHA256.hash(data: payload)), payload: payload)
        envelope.kind = kind; envelope.exclusion = reason; envelope.decisionLimit = limit
        try write(envelope)
    }
    private mutating func write(_ envelope: Envelope) throws {
        try Task.checkCancellation()
        if !prepared {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var directory = root; try directory.setResourceValues(values); prepared = true
        }
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let data = try encoder.encode(envelope)
        guard data.count <= Self.maximumEntryBytes else { throw VaultError.tooLarge }
        try Task.checkCancellation()
        try data.writeProtected(to: url(for: envelope.sha, kind: envelope.kind))
    }
    func pruneDocuments(keeping keys: Set<String>) {
        let names = Set(keys.map { MetaStore.key($0) + ".searchtext" })
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "searchtext" && !names.contains(file.lastPathComponent) {
            guard !Task.isCancelled else { return }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
