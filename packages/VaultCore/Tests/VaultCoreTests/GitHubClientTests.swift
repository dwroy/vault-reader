import XCTest
@testable import VaultCore

final class MockProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
        var status = 200, headers = [String: String](), data = Data()
        if token == "Bearer offline" { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        if token == "Bearer invalid" { status = 401 }
        else if token == "Bearer limited" { status = 403; headers = ["x-ratelimit-remaining":"0", "x-ratelimit-reset":"1800000000"] }
        else if request.url!.path.contains("trees") { data = Data("{\"sha\":\"abc\",\"tree\":[],\"truncated\":true}".utf8) }
        else if request.value(forHTTPHeaderField: "If-None-Match") == "cached" { status = 304 }
        else {
            headers["ETag"] = "new"
            data = Data("{\"commit\":{\"sha\":\"head\",\"commit\":{\"tree\":{\"sha\":\"tree\"}}}}".utf8)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@MainActor final class GitHubClientTests: XCTestCase {
    private func client(_ token: String = "valid") -> GitHubClient {
        let settings = URLSessionConfiguration.ephemeral; settings.protocolClasses = [MockProtocol.self]
        return GitHubClient(config: RepositoryConfig(), token: token, session: URLSession(configuration: settings))
    }
    func testETagAnd304() async throws {
        let client = client(), first = try await client.branch(etag: nil), second = try await client.branch(etag: "cached")
        XCTAssertEqual(first?.tree, "tree"); XCTAssertEqual(first?.etag, "new"); XCTAssertNil(second)
    }
    func testUnauthorizedAndRateLimitAreDistinct() async throws {
        do { _ = try await client("invalid").branch(etag: nil); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .unauthorized) }
        do { _ = try await client("limited").branch(etag: nil); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .rateLimited(Date(timeIntervalSince1970: 1800000000))) }
    }
    func testTruncatedTreeIsNeverAccepted() async throws {
        do { _ = try await client().tree(sha: "tree"); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .invalidTree) }
    }
    func testOfflineTransportHasActionableChineseMessage() async throws {
        do { _ = try await client("offline").branch(etag: nil); XCTFail() }
        catch {
            XCTAssertEqual(error as? VaultError, .network(URLError.notConnectedToInternet.rawValue))
            XCTAssertTrue(error.localizedDescription.contains("已缓存内容仍可阅读"))
        }
    }

}
