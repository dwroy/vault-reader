import XCTest
@testable import VaultReader
final class KeychainTests: XCTestCase {
    func testCredentialRoundTripAndDeletion() throws {
        let account = "test-" + UUID().uuidString
        defer { try? Keychain.delete(account) }
        try Keychain.save("synthetic-test-credential", account: account)
        XCTAssertEqual(try Keychain.read(account), "synthetic-test-credential")
        try Keychain.save("updated-test-credential", account: account)
        XCTAssertEqual(try Keychain.read(account), "updated-test-credential")
        try Keychain.delete(account)
        XCTAssertNil(try Keychain.read(account))
    }
}
