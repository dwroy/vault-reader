import Foundation

public struct VaultIndex: Sendable {
    public let entries: [TreeEntry]
    public let files: [String: TreeEntry]
    public init(_ entries: [TreeEntry] = []) {
        self.entries = entries.filter { $0.type == "blob" && Self.normalized($0.path) == $0.path && !$0.path.isEmpty }
        files = Dictionary(self.entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    }
    public static func normalized(_ path: String) -> String? {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return nil }
        var parts: [String] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { guard !parts.isEmpty else { return nil }; parts.removeLast() }
            else { parts.append(String(part)) }
        }
        return parts.joined(separator: "/")
    }
    public func children(of path: String) -> [DirectoryItem] {
        let prefix = path.isEmpty ? "" : path + "/"
        var result: [String: DirectoryItem] = [:]
        for entry in entries where entry.path.hasPrefix(prefix) {
            let tail = String(entry.path.dropFirst(prefix.count))
            let name = String(tail.split(separator: "/")[0])
            let folder = tail.contains("/")
            result[name] = DirectoryItem(path: prefix + name, name: name, isDirectory: folder, entry: folder ? nil : entry)
        }
        return result.values.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    public func changedCount(from old: VaultIndex) -> Int {
        Set(files.keys).union(old.files.keys).filter { files[$0]?.sha != old.files[$0]?.sha }.count
    }
}
public struct DirectoryItem: Identifiable {
    public init(path: String, name: String, isDirectory: Bool, entry: TreeEntry?) {
        self.path = path; self.name = name; self.isDirectory = isDirectory; self.entry = entry
    }
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let entry: TreeEntry?
    public var id: String { path }
}
