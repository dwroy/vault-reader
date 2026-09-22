import XCTest
@testable import VaultCore

private final class GitLabProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.httpMethod == "GET", request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "synthetic-read-only",
              request.value(forHTTPHeaderField: "Authorization") == nil,
              request.url!.absoluteString.contains("/gitlab/api/v4/projects/team%2Fsub%2Fnotes/repository/") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let url = request.url!, query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
        var headers = ["ETag": "gitlab-etag", "X-Next-Page": ""], status = 200, body = ""
        if request.value(forHTTPHeaderField: "If-None-Match") == "gitlab-etag" { status = 304 }
        else if url.path.contains("/branches/") {
            guard url.absoluteString.contains("branches/feature%2Fread") else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
            body = #"{"commit":{"id":"immutable-head"}}"#
        } else if url.lastPathComponent == "tree" {
            guard query.contains(URLQueryItem(name: "ref", value: "immutable-head")), query.contains(URLQueryItem(name: "recursive", value: "true")) else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
            if query.contains(URLQueryItem(name: "page", value: "1")) {
                headers["X-Next-Page"] = "2"; body = #"[{"id":"a","path":"README.md","type":"blob"}]"#
            } else { body = #"[{"id":"b","path":"notes/child.md","type":"blob"}]"# }
        } else if url.lastPathComponent == "commits" {
            guard query.contains(URLQueryItem(name: "ref_name", value: "feature/read")) else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
            body = #"[{"id":"abc","message":"更新\n完整消息","author_name":"Demo","committed_date":"2026-09-22T00:00:00.123Z"}]"#
        } else if url.lastPathComponent == "diff" {
            body = #"[{"old_path":"old.md","new_path":"new.md","new_file":false,"renamed_file":true,"deleted_file":false},{"old_path":"gone.md","new_path":"gone.md","new_file":false,"renamed_file":false,"deleted_file":true,"too_large":true}]"#
        } else { status = 404 }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class GitLabClientTests: XCTestCase {
    func testNestedNamespaceImmutableTreePaginationAndCommitMapping() async throws {
        var config = RepositoryConfig(); config.provider = .gitlab; config.server = "https://git.example.com/gitlab/"
        config.owner = "team/sub"; config.repo = "notes"; config.branch = "feature/read"
        let settings = URLSessionConfiguration.ephemeral; settings.protocolClasses = [GitLabProtocol.self]
        let client = GitLabClient(config: config, token: "synthetic-read-only", session: URLSession(configuration: settings))
        let head = try await client.branch(etag: nil), unchanged = try await client.branch(etag: "gitlab-etag")
        XCTAssertEqual(head?.tree, "immutable-head"); XCTAssertNil(unchanged)
        let tree = try await client.tree(sha: head!.tree)
        XCTAssertEqual(tree.tree.map(\.path), ["README.md", "notes/child.md"]); XCTAssertFalse(tree.truncated)
        let recent = try await client.recent(etag: nil)
        XCTAssertEqual(recent?.commits.first?.title, "更新"); XCTAssertNotNil(recent?.commits.first?.date)
        let files = try await client.commitFiles(sha: "abc")
        XCTAssertEqual(files.files[0].previous_filename, "old.md"); XCTAssertEqual(files.files[1].status, "removed")
        XCTAssertTrue(files.truncated); XCTAssertEqual(files.limitsMayApply, true)
    }
    func testLegacyConfigMigrationProviderHostIsolationAndHTTPSValidation() throws {
        let legacy = try JSONDecoder().decode(RepositoryConfig.self, from: Data(#"{"owner":"Example","repo":"Notes","branch":"main","home":"README.md","cacheLimitMB":500}"#.utf8))
        XCTAssertEqual(legacy.provider, .github); XCTAssertEqual(legacy.identity, "example/notes")
        var gitlab = legacy; gitlab.provider = .gitlab; gitlab.owner = "group/sub"
        XCTAssertTrue(gitlab.isValid); XCTAssertNotEqual(gitlab.identity, legacy.identity)
        let defaultIdentity = gitlab.identity
        gitlab.server = "https://git.example.com/gitlab/"; XCTAssertTrue(gitlab.isValid); XCTAssertNotEqual(defaultIdentity, gitlab.identity)
        XCTAssertTrue(gitlab.fileURL(path: "a.md").absoluteString.contains("/gitlab/group/sub/Notes/-/blob/main/a.md"))
        for invalid in ["http://git.example.com", "https://user:password@git.example.com", "https://git.example.com?token=secret", "https://git.example.com#fragment"] {
            gitlab.server = invalid; XCTAssertFalse(gitlab.isValid)
        }
    }
}
