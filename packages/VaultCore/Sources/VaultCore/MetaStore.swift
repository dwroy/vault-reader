import Foundation
import CryptoKit

public actor MetaStore {
    public let root: URL
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    public static func key(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    public func read<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T? {
        let file = root.appendingPathComponent(name + ".json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: file))
    }
    public func write<T: Encodable & Sendable>(_ value: T, name: String) throws {
        try JSONEncoder().encode(value).writeProtected(to: root.appendingPathComponent(name + ".json"))
    }
}
