import Foundation

/// Prepared Markdown plus a sparse mapping back to original text. Disk offsets are UTF-8 bytes,
/// never serialized String.Index values, which are valid only for their original String.
struct SearchDocument: Sendable {
    struct Checkpoint: Codable, Sendable {
        let foldedOffset: Int
        let originalOffset: Int
    }
    struct Stored: Codable {
        let text: String
        let folded: Data
        let checkpoints: [Checkpoint]
    }
    let text: String
    let folded: Data
    let checkpoints: [(offset: Int, index: String.Index)]
    private let storedCheckpoints: [Checkpoint]

    init(text: String) { self = try! SearchDocument(cancellableText: text, checkCancellation: false) }
    init(cancellableText text: String, checkCancellation: Bool = true) throws {
        self.text = text
        var folded = Data(), checkpoints: [(Int, String.Index)] = [], stored: [Checkpoint] = []
        var start = text.startIndex, originalOffset = 0
        while start < text.endIndex {
            if checkCancellation { try Task.checkCancellation() }
            let end = text.index(start, offsetBy: 256, limitedBy: text.endIndex) ?? text.endIndex
            checkpoints.append((folded.count, start))
            stored.append(Checkpoint(foldedOffset: folded.count, originalOffset: originalOffset))
            let chunk = text[start..<end]
            folded.append(contentsOf: SearchQuery.fold(String(chunk)).utf8)
            originalOffset += chunk.utf8.count; start = end
        }
        self.folded = folded; self.checkpoints = checkpoints; storedCheckpoints = stored
    }
    init?(stored: Stored) {
        var text = stored.text
        text.makeContiguousUTF8()
        let bytes = text.utf8
        if text.isEmpty {
            guard stored.folded.isEmpty, stored.checkpoints.isEmpty else { return nil }
        } else {
            guard stored.checkpoints.first?.originalOffset == 0, stored.checkpoints.first?.foldedOffset == 0 else { return nil }
        }
        var checkpoints: [(Int, String.Index)] = [], previousOriginal = -1, previousFolded = 0
        for point in stored.checkpoints {
            guard point.originalOffset > previousOriginal, point.originalOffset < bytes.count,
                  point.foldedOffset >= previousFolded, point.foldedOffset <= stored.folded.count else { return nil }
            let offset = bytes.index(bytes.startIndex, offsetBy: point.originalOffset)
            guard let index = String.Index(offset, within: text) else { return nil }
            if point.foldedOffset < stored.folded.count, stored.folded[point.foldedOffset] & 0xc0 == 0x80 { return nil }
            checkpoints.append((point.foldedOffset, index))
            previousOriginal = point.originalOffset; previousFolded = point.foldedOffset
        }
        self.text = text; folded = stored.folded; self.checkpoints = checkpoints; storedCheckpoints = stored.checkpoints
    }
    /// Conservative retained-payload accounting; excludes parser temporaries and the host/renderer.
    var memoryCost: Int { text.utf8.count * 2 + folded.count + checkpoints.count * 96 + 1024 }
    var stored: Stored { Stored(text: text, folded: folded, checkpoints: storedCheckpoints) }
    func checkpoint(after offset: Int) -> Int {
        var lower = 0, upper = checkpoints.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if checkpoints[middle].offset <= offset { lower = middle + 1 } else { upper = middle }
        }
        return lower
    }
}
