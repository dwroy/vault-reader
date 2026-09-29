import Foundation

public struct SearchLimits: Sendable {
    public let sourceBytes: Int
    public let documentBytes: Int
    public let residentBytes: Int
    public let documentCount: Int
    public init(sourceBytes: Int = 512 * 1024, documentBytes: Int = 2 * 1024 * 1024, residentBytes: Int = 32 * 1024 * 1024, documentCount: Int = 5000) {
        self.sourceBytes = max(1, sourceBytes); self.documentBytes = max(1, documentBytes)
        self.residentBytes = max(1, residentBytes); self.documentCount = max(1, documentCount)
    }
}
public enum SearchTextKind: String, Codable, Sendable { case markdown, plain }
public enum SearchExclusion: String, Codable, Sendable { case fileType, tooLarge, contentLimit, memoryBudget, encoding }
public struct SearchCoverage: Sendable {
    public var indexed = 0
    public var pending = 0
    public var metadataOnly = 0
    public var oversized = 0
    public var limited = 0
    public var residentBytes = 0
    public init() {}
}
public struct VaultContentProfile: Sendable {
    public let totalFiles: Int
    public let textFiles: Int
    public let readableFiles: Int
    /// A conservative suitability hint: attachments can outnumber the notes they illustrate.
    public var needsSuitabilityNotice: Bool { totalFiles > 0 && (readableFiles == 0 || (totalFiles >= 5 && readableFiles * 4 < totalFiles)) }
    public init(_ entries: [TreeEntry]) {
        // Configuration folders do not describe the owner's reading material. Count files, not bytes.
        let files = entries.filter { !$0.path.split(separator: "/").contains { $0.hasPrefix(".") } }
        totalFiles = files.count; textFiles = files.filter { SearchFileMetadata.textExtensions.contains($0.ext) }.count
        // PDF is a native reading format even though its body is not part of text search.
        readableFiles = textFiles + files.filter { $0.ext == "pdf" }.count
    }
}
public struct SearchFileMetadata: Sendable {
    static let textExtensions: Set<String> = ["md", "markdown", "txt", "text", "html", "htm", "json", "yaml", "yml", "csv", "tsv", "xml", "toml", "ini", "js", "ts", "jsx", "tsx", "swift", "c", "cpp", "h", "cs", "py", "go", "rs", "java", "kt", "lua", "sh", "ps1", "psm1", "psd1", "css", "sql", "rst", "org", "adoc", "tex", "log"]
    public let typeLabel: String
    public let mimeType: String
    public let isText: Bool
    public let byteCount: Int?
    let terms: String
    public init(_ entry: TreeEntry) {
        let ext = entry.ext
        let category: (String, String, Bool)
        switch ext {
        case "md", "markdown": category = ("Markdown", "text/markdown", true)
        case "txt", "text": category = ("Text", "text/plain", true)
        case "html", "htm": category = ("HTML", "text/html", true)
        case "pdf": category = ("PDF", "application/pdf", false)
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "avif", "tiff", "bmp": category = ("Image", ext == "svg" ? "image/svg+xml" : "image/" + (ext == "jpg" ? "jpeg" : ext), false)
        case "mp4", "mov", "m4v", "mkv", "webm", "avi": category = ("Video", "video/" + (ext == "mov" ? "quicktime" : ext), false)
        case "mp3", "wav", "m4a", "aac", "flac", "ogg": category = ("Audio", "audio/" + (ext == "mp3" ? "mpeg" : ext), false)
        case "zip", "7z", "rar", "gz", "tar": category = ("Archive", "application/" + ext, false)
        case "json", "yaml", "yml", "csv", "tsv", "xml", "toml", "ini": category = ("Data file", "text/" + ext, true)
        case "js", "ts", "jsx", "tsx", "swift", "c", "cpp", "h", "cs", "py", "go", "rs", "java", "kt", "lua", "sh", "ps1", "psm1", "psd1", "css", "sql": category = ("Code", "text/plain", true)
        case "rst", "org", "adoc", "tex", "log": category = ("Text", "text/plain", true)
        default: category = ("File", "application/octet-stream", false)
        }
        let knownMIME = ["m4v": "video/mp4", "mkv": "video/x-matroska", "avi": "video/x-msvideo", "m4a": "audio/mp4", "7z": "application/x-7z-compressed", "rar": "application/vnd.rar", "gz": "application/gzip", "tar": "application/x-tar", "json": "application/json", "yaml": "application/yaml", "yml": "application/yaml", "xml": "application/xml", "tsv": "text/tab-separated-values"]
        typeLabel = category.0; mimeType = knownMIME[ext] ?? category.1; isText = category.2; byteCount = entry.size.flatMap { $0 >= 0 ? $0 : nil }
        let aliases: String
        switch category.0 {
        case "Image": aliases = "图片 圖片 图像 圖像 画像 이미지 imagen imagem bild صورة छवि gambar"
        case "Video": aliases = "视频 影片 動画 동영상 vídeo vidéo فيديو वीडियो"
        case "Audio": aliases = "音频 音訊 音声 오디오 son áudio صوت ऑडियो suara"
        case "Archive": aliases = "压缩包 壓縮檔 アーカイブ 압축 archivo archiv أرشيف arsip"
        case "Markdown", "Text": aliases = "文本 正文 文字 テキスト 텍스트 texto texte نص पाठ teks"
        case "Code": aliases = "代码 程式碼 コード 코드 código kode"
        case "Data file": aliases = "数据 資料 データ 데이터 datos données daten بيانات data"
        default: aliases = ""
        }
        let size = byteCount.map { bytes in
            let displayed = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            return "\(bytes) bytes " + displayed + " " + displayed.filter { !$0.isWhitespace }
        } ?? ""
        terms = SearchQuery.fold([entry.ext, category.0, mimeType, aliases, size].joined(separator: " "))
    }
}
extension TreeEntry {
    public var searchTextKind: SearchTextKind? {
        if isMarkdown { return .markdown }
        return ["txt", "text"].contains(ext) ? .plain : nil
    }
    var searchDocumentKey: String? { searchTextKind.map { $0.rawValue + ":" + sha } }
    func searchExclusion(limits: SearchLimits) -> SearchExclusion? {
        guard searchTextKind != nil else { return .fileType }
        return (size ?? 0) > limits.sourceBytes ? .tooLarge : nil
    }
}
