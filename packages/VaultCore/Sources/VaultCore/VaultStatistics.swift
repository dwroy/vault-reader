import Foundation

/// Metadata-only totals for one complete file catalog. No attachment downloads are needed.
public struct VaultStatistics: Sendable, Equatable {
    public struct FileType: Sendable, Equatable, Identifiable {
        public let ext: String
        public let fileCount: Int
        public let knownBytes: Int64
        public let unknownSizeCount: Int
        public var id: String { ext }
    }
    public let fileCount: Int
    public let folderCount: Int
    public let knownBytes: Int64
    public let unknownSizeCount: Int
    public let fileTypes: [FileType]

    public init(index: VaultIndex, hideDotFiles: Bool = false) {
        let files = index.files.values.filter { !hideDotFiles || !$0.path.split(separator: "/").contains { $0.hasPrefix(".") } }
        var folders = Set<String>()
        var types: [String: (count: Int, bytes: Int64, unknown: Int)] = [:]
        for file in files {
            let parts = file.path.split(separator: "/")
            for end in 1..<parts.count { folders.insert(parts[..<end].joined(separator: "/")) }
            var type = types[file.ext, default: (0, 0, 0)]
            type.count += 1
            if let size = file.size, size >= 0 { type.bytes += Int64(size) }
            else { type.unknown += 1 }
            types[file.ext] = type
        }
        fileCount = files.count
        folderCount = folders.count
        knownBytes = types.values.reduce(0) { $0 + $1.bytes }
        unknownSizeCount = types.values.reduce(0) { $0 + $1.unknown }
        fileTypes = types.map { FileType(ext: $0.key, fileCount: $0.value.count, knownBytes: $0.value.bytes, unknownSizeCount: $0.value.unknown) }.sorted {
            $0.fileCount == $1.fileCount ? $0.ext < $1.ext : $0.fileCount > $1.fileCount
        }
    }
}
