import XCTest
@testable import VaultCore

private final class BoundedDownloadProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data(repeating: 65, count: 128 * 1024)
        let headers = request.url!.path.contains("unknown") ? [:] : ["Content-Length": String(data.count)]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class BoundedDownloadTests: XCTestCase {
    func testBothProvidersRejectKnownOversizedFilesBeforeRequesting() async throws {
        let settings = URLSessionConfiguration.ephemeral; settings.protocolClasses = [BoundedDownloadProtocol.self]
        let session = URLSession(configuration: settings)
        var gitlab = RepositoryConfig(); gitlab.provider = .gitlab
        let clients: [any RepositorySource] = [GitHubClient(config: RepositoryConfig(), token: "synthetic", session: session), GitLabClient(config: gitlab, token: "synthetic", session: session)]
        let entry = TreeEntry(path: "large.md", sha: "a", size: 4096)
        for source in clients {
            do { _ = try await source.blob(entry, maximumBytes: 1024, progress: nil); XCTFail("File admitted") }
            catch { XCTAssertEqual(error as? VaultError, .tooLarge) }
        }
    }
    func testRawDownloadLimitWithKnownAndUnknownContentLength() async throws {
        let settings = URLSessionConfiguration.ephemeral; settings.protocolClasses = [BoundedDownloadProtocol.self]
        let http = RepositoryHTTP(session: URLSession(configuration: settings))
        for path in ["known", "unknown"] {
            do {
                _ = try await http.get(URL(string: "https://synthetic.invalid/\(path)")!, headers: [:], raw: true, maximumBytes: 1024)
                XCTFail("Raw download exceeded index budget")
            } catch { XCTAssertEqual(error as? VaultError, .tooLarge, "\(path): \(error)") }
        }
    }
}
