import Foundation

/// File roles in an explicit reading list. Display order follows `allCases`.
public enum BookRole: String, CaseIterable, Hashable, Sendable { case condensed, fulltext, reader, original, notes, review, other }

public struct BookLink: Identifiable, Hashable, Sendable {
    public let role: BookRole
    public let label: String
    public let target: String
    /// Indexed repository-relative path, when the target resolves inside the vault.
    public let path: String?
    /// External web address; never fetched by VaultCore.
    public let url: URL?
    public var detail: String?
    public var id: String { role.rawValue + ":" + (path ?? url?.absoluteString ?? "?" + target) }
}

public struct ListedBook: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let group: String?
    /// The reading-list Markdown that declared this book.
    public let source: String
    public var author: String?
    public var rating: String?
    public var status: String?
    public var remarks: [String] = []
    public var comments: [String] = []
    public var links: [BookLink] = []
    public var paths: [String] { links.compactMap(\.path) }
    public func links(_ role: BookRole) -> [BookLink] { links.filter { $0.role == role } }
}

public struct BookGroup: Identifiable, Sendable {
    public let title: String?
    public let books: [ListedBook]
    public var id: String { title ?? "" }
}

/// Parses a reading-list Markdown such as `study/read/书单.md`:
///
///     ## 在读                      ← group
///     ### 置身事内                  ← book
///     - 作者：兰小欢
///     - 原书：[PDF](../../files/置身事内.pdf)
///     - 精简版：[[置身事内-精简版]]
///
/// A heading counts as a book only when it has at least one recognized `- key：value` item.
/// Indented list items continue the previous key. Links resolve like the shared renderer:
/// Markdown links relative to the list, wikilinks by Obsidian-style name lookup.
public struct BookList: Sendable {
    enum Field: Hashable { case author, rating, status, remark, link(BookRole) }
    static let fields: [String: Field] = [
        "作者": .author, "author": .author, "评分": .rating, "rating": .rating,
        "状态": .status, "进度": .status, "status": .status, "备注": .remark, "note": .remark,
        "原书": .link(.original), "原版": .link(.original), "导入": .link(.original), "附件": .link(.original), "original": .link(.original),
        "全文": .link(.fulltext), "原文": .link(.fulltext), "整理版": .link(.fulltext), "fulltext": .link(.fulltext),
        "精简版": .link(.condensed), "简化版": .link(.condensed), "精简": .link(.condensed), "详版": .link(.condensed), "condensed": .link(.condensed),
        "阅读器": .link(.reader), "reader": .link(.reader),
        "笔记": .link(.notes), "读书笔记": .link(.notes), "阅读笔记": .link(.notes), "复习笔记": .link(.notes), "notes": .link(.notes),
        "评论": .link(.review), "书评": .link(.review), "短评": .link(.review), "感想": .link(.review), "review": .link(.review),
        "入口": .link(.other), "相关": .link(.other), "其他": .link(.other), "other": .link(.other)
    ]
    public let books: [ListedBook]

    public init(markdown: String, at source: String, index: VaultIndex) {
        let resolver = LinkResolver(index: index)
        var lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(...end)
        }
        var books: [ListedBook] = [], group: String?, current: ListedBook?, currentLevel = 0
        var recognized = false, field: Field?, fence = false
        func finish() {
            if let book = current, recognized {
                books.append(book)
                if currentLevel == 2 { group = nil }
            }
            current = nil; recognized = false; field = nil
        }
        func apply(_ field: Field, _ value: String) {
            guard current != nil else { return }
            let text = Self.plain(value)
            switch field {
            case .author: if !text.isEmpty { current?.author = text }
            case .rating: if !text.isEmpty { current?.rating = text }
            case .status: if !text.isEmpty { current?.status = text }
            case .remark: if !text.isEmpty { current?.remarks.append(text) }
            case .link(let role):
                let found = resolver.links(in: value, role: role, from: source)
                if found.isEmpty {
                    if role == .review, !text.isEmpty { current?.comments.append(text) }
                    return
                }
                let residue = found.count == 1 ? Self.residue(value) : nil
                for var link in found where !(current?.links.contains { $0.id == link.id } ?? true) {
                    link.detail = residue; current?.links.append(link)
                }
            }
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { fence.toggle(); field = nil; continue }
            if fence { continue }
            if let (level, title) = Self.heading(line) {
                guard level <= 3 else { field = nil; continue }
                finish()
                if level == 1 { group = nil; continue }
                if level == 2 { group = title }
                currentLevel = level
                current = ListedBook(id: source + "#" + String(books.count) + ":" + title, title: title, group: level == 3 ? group : nil, source: source)
                continue
            }
            if let (indent, item) = Self.listItem(line) {
                if indent < 2, let (key, value) = Self.keyValue(item), let match = Self.fields[key] {
                    recognized = recognized || current != nil
                    field = match; apply(match, value)
                } else if indent >= 2, let field {
                    apply(field, item)
                } else { field = nil }
                continue
            }
            if !trimmed.isEmpty { field = nil }
        }
        finish()
        self.books = books
    }

    /// Frontmatter keys in the root README that name reading lists, for any vault layout:
    /// `书单: study/read/书单.md`, a YAML list of paths, or `"[[书单]]"`.
    public static let declarationKeys: Set<String> = ["书单", "booklist"]
    /// Conventional list names, found anywhere when the README declares nothing.
    public static let fileNames: Set<String> = ["书单.md", "booklist.md"]
    public static func readme(in index: VaultIndex) -> String? {
        index.entries.filter { !$0.path.contains("/") && $0.name.lowercased() == "readme.md" }.map(\.path).sorted().first
    }
    /// Indexed Markdown paths declared in README frontmatter. Missing, traversing and non-Markdown targets are dropped.
    public static func declared(inReadme markdown: String, at path: String, index: VaultIndex) -> [String] {
        var lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.first?.hasPrefix("\u{FEFF}") == true { lines[0].removeFirst() }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == "---" }) else { return [] }
        var values: [String] = [], inKey = false
        for line in lines[1..<end] {
            if let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t"), !line.hasPrefix("-") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "'\"")).lowercased()
                inKey = declarationKeys.contains(key)
                guard inKey else { continue }
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("["), value.hasSuffix("]"), !value.hasPrefix("[[") {
                    values += value.dropFirst().dropLast().split(separator: ",").map(String.init)
                } else if !value.isEmpty { values.append(value) }
            } else if inKey, let (_, item) = listItem(line) { values.append(item) }
            else if !line.trimmingCharacters(in: .whitespaces).isEmpty, !line.hasPrefix(" "), !line.hasPrefix("\t") { inKey = false }
        }
        let resolver = LinkResolver(index: index)
        var result: [String] = []
        for value in values {
            let item = value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "'\"")).trimmingCharacters(in: .whitespaces)
            let target = resolver.links(in: item, role: .other, from: path).first?.path ?? resolver.relativePath(item, from: path)
            if let target, target != path, index.files[target]?.isMarkdown == true, !result.contains(target) { result.append(target) }
        }
        return result
    }
    /// Without a README declaration: every `书单.md`/`booklist.md`, then top-level Markdown in reading folders.
    public static func conventional(in index: VaultIndex) -> [String] {
        let named = index.entries.filter { fileNames.contains($0.name.lowercased()) }.map(\.path).sorted()
        var result: [String] = []
        for path in named + BookCatalog(index: index).indexes.map(\.path) where !result.contains(path) { result.append(path) }
        return result
    }

    /// Groups in first-appearance order, across one or more lists.
    public static func groups(_ books: [ListedBook]) -> [BookGroup] {
        var order: [String?] = [], members: [String: [ListedBook]] = [:]
        for book in books {
            let key = book.group ?? ""
            if members[key] == nil { order.append(book.group); members[key] = [] }
            members[key]?.append(book)
        }
        return order.map { BookGroup(title: $0, books: members[$0 ?? ""] ?? []) }
    }

    static func heading(_ line: String) -> (Int, String)? {
        guard line.hasPrefix("#") else { return nil }
        let level = line.prefix { $0 == "#" }.count
        let rest = line.dropFirst(level)
        guard level <= 6, rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"\s+#+$"#, with: "", options: .regularExpression)
        return title.isEmpty ? nil : (level, plain(title))
    }
    static func listItem(_ line: String) -> (Int, String)? {
        let expanded = line.replacingOccurrences(of: "\t", with: "  ")
        let indent = expanded.prefix { $0 == " " }.count
        let rest = expanded.dropFirst(indent)
        guard let marker = rest.first, "-*+".contains(marker), rest.dropFirst().first == " " else { return nil }
        return (indent, rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
    }
    static func keyValue(_ item: String) -> (String, String)? {
        guard let colon = item.firstIndex(where: { $0 == "：" || $0 == ":" }) else { return nil }
        let key = item[..<colon].replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "_", with: "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty, key.count <= 12 else { return nil }
        return (key, String(item[item.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
    }
    /// Readable text: links become their labels; emphasis and code markers are removed.
    static func plain(_ value: String) -> String {
        var text = value
        text = text.replacingOccurrences(of: #"!?\[\[([^\]|\n]+)\|([^\]\n]+)\]\]"#, with: "$2", options: .regularExpression)
        text = text.replacingOccurrences(of: #"!?\[\[([^\]\n]+)\]\]"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"!?\[([^\]\n]*)\]\([^)\n]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<(https?://[^>\s]+)>"#, with: "$1", options: .regularExpression)
        for marker in ["**", "__", "`"] { text = text.replacingOccurrences(of: marker, with: "") }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    /// Explanatory text beside a single link, such as `（380 页，扫描本）`.
    static func residue(_ value: String) -> String? {
        var text = value
        for pattern in LinkResolver.patterns { text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression) }
        text = plain(text).trimmingCharacters(in: CharacterSet(charactersIn: " 、，,;；|/·"))
        for (open, close) in [("（", "）"), ("(", ")")] where text.hasPrefix(open) && text.hasSuffix(close) {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return text.isEmpty ? nil : text
    }
}

/// Swift port of `packages/reader-web/src/tree.js` resolution, so the list and the rendered note agree.
struct LinkResolver: Sendable {
    static let patterns = [
        #"!?\[\[([^\]\n]+)\]\]"#,
        #"!?\[([^\]\n]*)\]\(\s*(?:<([^>\n]+)>|([^\s)]+))(?:\s+"[^"]*")?\s*\)"#,
        #"<(https?://[^>\s]+)>"#,
        #"(https?://[^\s<>)）\]]+)"#
    ]
    static var combined: NSRegularExpression? { try? NSRegularExpression(pattern: patterns.map { "(?:" + $0 + ")" }.joined(separator: "|")) }
    let paths: [String]
    let files: Set<String>
    let mdByName: [String: [String]]
    let anyByName: [String: [String]]
    init(index: VaultIndex) {
        paths = index.entries.map(\.path); files = Set(paths)
        var md: [String: [String]] = [:], any: [String: [String]] = [:]
        for path in paths {
            let name = (path as NSString).lastPathComponent.lowercased()
            any[name, default: []].append(path)
            if name.hasSuffix(".md") { md[String(name.dropLast(3)), default: []].append(path) }
        }
        mdByName = md; anyByName = any
    }
    func links(in value: String, role: BookRole, from source: String) -> [BookLink] {
        guard let regex = Self.combined else { return [] }
        let text = value as NSString
        func group(_ match: NSTextCheckingResult, _ i: Int) -> String? {
            let range = match.range(at: i)
            return range.location == NSNotFound ? nil : text.substring(with: range)
        }
        var result: [BookLink] = []
        for match in regex.matches(in: value, range: NSRange(location: 0, length: text.length)) {
            if let wiki = group(match, 1) {
                let parts = wiki.split(separator: "|", maxSplits: 1).map(String.init)
                var target = parts[0].trimmingCharacters(in: .whitespaces)
                if target.hasSuffix("\\") { target.removeLast() }
                let name = ((target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target) as NSString).lastPathComponent
                let label = parts.count > 1 ? parts[1] : ((name as NSString).pathExtension.lowercased() == "md" ? (name as NSString).deletingPathExtension : name)
                result.append(BookLink(role: role, label: label.isEmpty ? target : label, target: target, path: wikiPath(target, from: source), url: nil))
            } else if let target = group(match, 3) ?? group(match, 4) {
                let label = group(match, 2) ?? ""
                if let components = URLComponents(string: target), let scheme = components.scheme?.lowercased() {
                    guard ["http", "https"].contains(scheme), components.host != nil, let url = components.url else { continue }
                    result.append(BookLink(role: role, label: label.isEmpty ? url.host ?? target : BookList.plain(label), target: target, path: nil, url: url))
                    continue
                }
                let path = relativePath(target, from: source)
                let fallback = ((target.removingPercentEncoding ?? target) as NSString).lastPathComponent
                result.append(BookLink(role: role, label: label.isEmpty ? (path.map { ($0 as NSString).lastPathComponent } ?? fallback) : BookList.plain(label), target: target, path: path, url: nil))
            } else if let address = group(match, 5) ?? group(match, 6), let url = URL(string: address), url.host != nil {
                result.append(BookLink(role: role, label: url.host ?? address, target: address, path: nil, url: url))
            }
        }
        return result
    }
    func wikiPath(_ raw: String, from: String) -> String? {
        var name = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespaces)
        if let hash = name.firstIndex(of: "#") { name = String(name[..<hash]) }
        guard !name.isEmpty else { return from }
        let ext = (name as NSString).pathExtension.lowercased()
        let hasExt = !ext.isEmpty && ext != "md"
        if !hasExt, name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
        var candidates: [String]
        if name.contains("/") {
            let wanted = (name.hasPrefix("/") ? String(name.dropFirst()) : name).lowercased()
            candidates = paths.filter { path in
                guard hasExt || path.lowercased().hasSuffix(".md") else { return false }
                let p = (hasExt ? path : String(path.dropLast(3))).lowercased()
                return p == wanted || p.hasSuffix("/" + wanted)
            }
        } else { candidates = (hasExt ? anyByName : mdByName)[name.lowercased()] ?? [] }
        let directory = Self.directory(from)
        return candidates.min { a, b in
            let sameA = Self.directory(a) == directory, sameB = Self.directory(b) == directory
            if sameA != sameB { return sameA }
            let depthA = a.split(separator: "/").count, depthB = b.split(separator: "/").count
            return depthA != depthB ? depthA < depthB : a < b
        }
    }
    func relativePath(_ target: String, from: String) -> String? {
        let raw = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target
        guard !raw.isEmpty else { return from }
        let decoded = raw.removingPercentEncoding ?? raw
        let joined = decoded.hasPrefix("/") ? String(decoded.dropFirst()) : [Self.directory(from), decoded].filter { !$0.isEmpty }.joined(separator: "/")
        guard let path = VaultIndex.normalized(joined) else { return nil }
        return files.contains(path) ? path : files.contains(path + ".md") ? path + ".md" : nil
    }
    static func directory(_ path: String) -> String { (path as NSString).deletingLastPathComponent }
}
