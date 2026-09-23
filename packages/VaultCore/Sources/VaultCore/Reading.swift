import Foundation

public enum ReadingKind: String, Codable, Sendable { case markdown, html, pdf }
public enum ReadingTheme: String, Codable, CaseIterable, Sendable { case system, light, sepia, dark }
public struct ReadingLocation: Codable, Equatable, Sendable {
    public var heading: String? = nil
    public var withinHeading: Double = 0
    public var fraction: Double = 0
    public var page: Int? = nil
    public init(heading: String? = nil, withinHeading: Double = 0, fraction: Double = 0, page: Int? = nil) {
        self.heading = heading
        self.withinHeading = Self.unit(withinHeading)
        self.fraction = Self.unit(fraction)
        self.page = page.map { max(0, $0) }
    }
    public static func unit(_ number: Double) -> Double { number.isFinite ? min(1, max(0, number)) : 0 }
}
public struct ReadingOutline: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let level: Int
    public init(id: String, title: String, level: Int) { self.id = id; self.title = title; self.level = level }
}
public struct ReadingRecord: Codable, Identifiable, Equatable, Sendable {
    public var path: String
    public var title: String
    public var kind: ReadingKind
    public var location: ReadingLocation
    public var fontScale: Double = 1
    public var theme: ReadingTheme = .system
    public var updatedAt: Date
    public var id: String { path }
    public init(path: String, title: String, kind: ReadingKind, location: ReadingLocation = .init(), updatedAt: Date = Date()) {
        self.path = path; self.title = title; self.kind = kind; self.location = location; self.updatedAt = updatedAt
    }
}
public struct ReadingHistory: Codable, Sendable {
    public private(set) var records: [String: ReadingRecord] = [:]
    public init() {}
    public mutating func remember(_ record: ReadingRecord) {
        guard !record.path.isEmpty, VaultIndex.normalized(record.path) == record.path else { return }
        var record = record
        record.location = ReadingLocation(heading: record.location.heading, withinHeading: record.location.withinHeading, fraction: record.location.fraction, page: record.location.page)
        record.fontScale = record.fontScale.isFinite ? min(1.6, max(0.8, record.fontScale)) : 1
        records[record.path] = record
        for old in recent.dropFirst(200) { records.removeValue(forKey: old.path) }
    }
    public var recent: [ReadingRecord] { records.values.sorted { $0.updatedAt > $1.updatedAt } }
    /// Recent reading lists Markdown only. PDF and HTML keep their progress for the book page.
    public func recentMarkdown(limit: Int, where include: (ReadingRecord) -> Bool = { _ in true }) -> [ReadingRecord] {
        Array(recent.filter { $0.kind == .markdown && include($0) }.prefix(limit))
    }
}
public struct ShelfBook: Identifiable, Sendable {
    public let id: String
    public let title: String
    public var editions: [TreeEntry]
}
public struct BookCatalog: Sendable {
    public let books: [ShelfBook]
    public let indexes: [TreeEntry]
    public static func root(for path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let i = parts.dropLast().firstIndex(where: { ["read", "reading", "books", "papers", "articles"].contains($0.lowercased()) }) else { return nil }
        return parts[...i].joined(separator: "/")
    }
    public static func supports(_ entry: TreeEntry) -> Bool { entry.isMarkdown || entry.isHTML || entry.ext == "pdf" }
    public init(index: VaultIndex, linkedPDFs: Set<String> = []) {
        var groups: [String: ShelfBook] = [:], indexes: [TreeEntry] = []
        for entry in index.entries where Self.supports(entry) {
            guard let root = Self.root(for: entry.path) else { continue }
            let tail = String(entry.path.dropFirst(root.count + 1)).split(separator: "/")
            if tail.count == 1, entry.isMarkdown { indexes.append(entry); continue }
            let id = tail.count > 1 ? root + "/" + String(tail[0]) : entry.path
            let title = tail.count > 1 ? String(tail[0]) : (entry.name as NSString).deletingPathExtension
            if groups[id] == nil { groups[id] = ShelfBook(id: id, title: title, editions: []) }
            groups[id]?.editions.append(entry)
        }
        for path in linkedPDFs.sorted() {
            guard let entry = index.files[path], entry.ext == "pdf", !groups.values.contains(where: { $0.editions.contains(entry) }) else { continue }
            let name = (entry.name as NSString).deletingPathExtension
            let group = groups.values.sorted { $0.title.count > $1.title.count }.first { name.hasPrefix($0.title) }
            if let group { groups[group.id]?.editions.append(entry) }
            else { groups[path] = ShelfBook(id: path, title: name, editions: [entry]) }
        }
        books = groups.values.map { book in
            var book = book
            book.editions.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return book
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        self.indexes = indexes.sorted { $0.path < $1.path }
    }
    /// Only indexed, repository-relative PDF targets are discovered. External links are never fetched.
    public static func linkedPDFs(in markdown: String, at path: String, index: VaultIndex) -> Set<String> {
        let pattern = #"\]\(\s*(?:<([^>\n]+)>|([^\s)]+))(?:\s+\"[^\"]*\")?\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = markdown as NSString, directory = (path as NSString).deletingLastPathComponent
        var result = Set<String>()
        for match in regex.matches(in: markdown, range: NSRange(location: 0, length: source.length)) {
            let range = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
            let target = source.substring(with: range)
            guard let url = URLComponents(string: target), url.scheme == nil, url.host == nil,
                  let decoded = url.percentEncodedPath.removingPercentEncoding,
                  let normalized = VaultIndex.normalized(directory.isEmpty ? decoded : directory + "/" + decoded),
                  index.files[normalized]?.ext == "pdf" else { continue }
            result.insert(normalized)
        }
        return result
    }
}
