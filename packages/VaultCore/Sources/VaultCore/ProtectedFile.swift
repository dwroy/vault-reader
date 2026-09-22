import Foundation
extension Data {
    func writeProtected(to url: URL) throws {
        #if os(iOS)
        try write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try write(to: url, options: .atomic)
        #endif
    }
}
