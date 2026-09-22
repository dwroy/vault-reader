import Foundation
import CryptoKit

public actor BlobStore {
    public static let maximumFileBytes = 100 * 1024 * 1024
    public let root: URL
    private var pinned = Set<String>()
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var root = root; try root.setResourceValues(excluded)
        if let data = try? Data(contentsOf: root.appendingPathComponent("pinned.json")), let values = try? JSONDecoder().decode(Set<String>.self, from: data) { pinned = values }
    }
    public static func hash(_ data: Data) -> String {
        var input = Data("blob \(data.count)\0".utf8); input.append(data)
        return Insecure.SHA1.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
    private func url(_ sha: String) throws -> URL {
        guard sha.count == 40 && sha.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { throw VaultError.corruptBlob }
        return root.appendingPathComponent(sha)
    }
    public func data(for sha: String) throws -> Data? {
        let url = try url(sha)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard Self.hash(data) == sha else { try FileManager.default.removeItem(at: url); return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }
    public func put(_ data: Data, entry: TreeEntry) throws {
        guard data.count <= Self.maximumFileBytes else { throw VaultError.tooLarge }
        guard Self.hash(data) == entry.sha else { throw VaultError.corruptBlob }
        try data.writeProtected(to: url(entry.sha))
        if entry.isPinned {
            pinned.insert(entry.sha)
            try JSONEncoder().encode(pinned).write(to: root.appendingPathComponent("pinned.json"), options: .atomic)
        }
    }
    public func previewURL(sha: String, filename: String) throws -> URL {
        guard let data = try data(for: sha) else { throw VaultError.missing }
        let directory = root.deletingLastPathComponent().appendingPathComponent("previews").appendingPathComponent(sha)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent((filename as NSString).lastPathComponent)
        if !FileManager.default.fileExists(atPath: url.path) { try data.writeProtected(to: url) }
        return url
    }
    public func releasePreview(_ url: URL) throws {
        let previews = root.deletingLastPathComponent().appendingPathComponent("previews").standardizedFileURL
        guard url.standardizedFileURL.path.hasPrefix(previews.path + "/") else { throw VaultError.missing }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    public func usage() throws -> Int { try cachedFiles().reduce(0) { $0 + $1.bytes } }
    private func cachedFiles() throws -> [(url: URL, bytes: Int, date: Date)] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]).filter { $0.lastPathComponent.count == 40 }.map {
            let values = try $0.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return ($0, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
    }
    public func evict(to bytes: Int, keeping: Set<String> = [], clearPreviews: Bool = true) throws {
        let files = try cachedFiles().sorted { $0.date < $1.date }
        var total = files.reduce(0) { $0 + $1.bytes }
        for file in files where total > max(0, bytes) && !pinned.contains(file.url.lastPathComponent) && !keeping.contains(file.url.lastPathComponent) {
            try FileManager.default.removeItem(at: file.url); total -= file.bytes
        }
        let previews = root.deletingLastPathComponent().appendingPathComponent("previews")
        if clearPreviews && FileManager.default.fileExists(atPath: previews.path) { try FileManager.default.removeItem(at: previews) }
    }
}
