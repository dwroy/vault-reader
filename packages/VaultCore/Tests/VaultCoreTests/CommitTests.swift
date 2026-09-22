import XCTest
@testable import VaultCore

private final class CommitProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!, query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
        var status = 200, headers = ["ETag": "commits-etag"], body = ""
        if request.value(forHTTPHeaderField: "If-None-Match") == "commits-etag" { status = 304 }
        else if url.lastPathComponent == "commits" {
            guard query.contains(URLQueryItem(name: "sha", value: "feature/read")), query.contains(URLQueryItem(name: "per_page", value: "30")) else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
            body = #"[{"sha":"abc","commit":{"message":"首行\n详情","committer":{"date":"2026-09-22T00:00:00Z"}}}]"#
        } else if query.contains(URLQueryItem(name: "page", value: "1")) {
            headers["Link"] = "<https://api.github.com/ignored>; rel=\"next\""
            body = #"{"files":[{"filename":"新.md","previous_filename":"旧.md","status":"renamed"}]}"#
        } else { body = #"{"files":[{"filename":"删除.md","status":"removed"}]}"# }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class CommitTests: XCTestCase {
    func testBranchScopedRecentETagAndPagedRenameDeletion() async throws {
        var config = RepositoryConfig(); config.branch = "feature/read"
        let session = URLSessionConfiguration.ephemeral; session.protocolClasses = [CommitProtocol.self]
        let client = GitHubClient(config: config, token: "synthetic", session: URLSession(configuration: session))
        let first = try await client.recent(etag: nil), second = try await client.recent(etag: first?.etag)
        XCTAssertEqual(first?.commits.first?.title, "首行"); XCTAssertNotNil(first?.commits.first?.date); XCTAssertNil(second)
        let detail = try await client.commitFiles(sha: "abc")
        XCTAssertEqual(detail.files.count, 2); XCTAssertEqual(detail.files[0].previous_filename, "旧.md"); XCTAssertEqual(detail.files[1].status, "removed"); XCTAssertFalse(detail.truncated)
    }
}
