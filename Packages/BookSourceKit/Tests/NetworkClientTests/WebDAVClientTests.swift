import XCTest
@testable import NetworkClient

/// Records every request it receives (method/url/headers/body) and returns a scripted response
/// per exact URL -- lets tests assert on what WebDAVClient actually sent, not just what it
/// returned, which matters here since Basic Auth headers and HTTP verbs are the whole point.
private actor RecordingStubHTTPClient: HTTPClient {
    struct Recorded {
        var method: String
        var url: String
        var headers: [String: String]
        var body: String?
    }

    private var responses: [String: HTTPResponse]
    private(set) var recorded: [Recorded] = []

    init(responses: [String: HTTPResponse]) {
        self.responses = responses
    }

    func fetch(_ request: HTTPRequest) async throws -> HTTPResponse {
        recorded.append(Recorded(
            method: request.method, url: request.url, headers: request.headers,
            body: request.body.flatMap { String(data: $0, encoding: .utf8) }
        ))
        guard let response = responses[request.url] else {
            throw HTTPClientError.invalidURL(request.url)
        }
        return response
    }
}

final class WebDAVClientTests: XCTestCase {
    private let config = WebDAVConfig(baseURL: "https://dav.example.com/YueDu", username: "alice", password: "secret")

    func testUploadSendsPUTWithBasicAuthAndBody() async throws {
        let client = RecordingStubHTTPClient(responses: [
            "https://dav.example.com/YueDu/book_sources.json": HTTPResponse(finalURL: "x", statusCode: 201, body: "")
        ])
        let webdav = WebDAVClient(httpClient: client, config: config)

        try await webdav.upload(path: "book_sources.json", content: #"[{"name":"A"}]"#)

        let recorded = await client.recorded
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded[0].method, "PUT")
        XCTAssertEqual(recorded[0].url, "https://dav.example.com/YueDu/book_sources.json")
        XCTAssertEqual(recorded[0].body, #"[{"name":"A"}]"#)
        let expectedAuth = "Basic " + Data("alice:secret".utf8).base64EncodedString()
        XCTAssertEqual(recorded[0].headers["Authorization"], expectedAuth)
    }

    func testUploadThrowsOnNonSuccessStatus() async throws {
        let client = RecordingStubHTTPClient(responses: [
            "https://dav.example.com/YueDu/book_sources.json": HTTPResponse(finalURL: "x", statusCode: 401, body: "unauthorized")
        ])
        let webdav = WebDAVClient(httpClient: client, config: config)

        do {
            try await webdav.upload(path: "book_sources.json", content: "{}")
            XCTFail("expected unexpectedStatus to be thrown")
        } catch WebDAVClientError.unexpectedStatus(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func testDownloadReturnsBodyOnSuccess() async throws {
        let client = RecordingStubHTTPClient(responses: [
            "https://dav.example.com/YueDu/shelf.json": HTTPResponse(finalURL: "x", statusCode: 200, body: #"[{"name":"B"}]"#)
        ])
        let webdav = WebDAVClient(httpClient: client, config: config)

        let content = try await webdav.download(path: "shelf.json")
        XCTAssertEqual(content, #"[{"name":"B"}]"#)

        let recorded = await client.recorded
        XCTAssertEqual(recorded[0].method, "GET")
    }

    func testMakeDirectoryTreats405AsAlreadyExistsNotAnError() async throws {
        let client = RecordingStubHTTPClient(responses: [
            "https://dav.example.com/YueDu/": HTTPResponse(finalURL: "x", statusCode: 405, body: "")
        ])
        let webdav = WebDAVClient(httpClient: client, config: config)

        try await webdav.makeDirectoryIfNeeded(path: "")

        let recorded = await client.recorded
        XCTAssertEqual(recorded[0].method, "MKCOL")
    }

    func testMakeDirectorySucceedsOn201Created() async throws {
        let client = RecordingStubHTTPClient(responses: [
            "https://dav.example.com/YueDu/": HTTPResponse(finalURL: "x", statusCode: 201, body: "")
        ])
        let webdav = WebDAVClient(httpClient: client, config: config)
        try await webdav.makeDirectoryIfNeeded(path: "")
    }

    func testBaseURLWithoutTrailingSlashIsNormalized() async throws {
        let noSlashConfig = WebDAVConfig(baseURL: "https://dav.example.com/YueDu", username: "a", password: "b")
        let client = RecordingStubHTTPClient(responses: [
            "https://dav.example.com/YueDu/x.json": HTTPResponse(finalURL: "x", statusCode: 200, body: "ok")
        ])
        let webdav = WebDAVClient(httpClient: client, config: noSlashConfig)
        _ = try await webdav.download(path: "x.json")
    }

    func testEmptyBaseURLThrowsInvalidBaseURL() async throws {
        let emptyConfig = WebDAVConfig(baseURL: "", username: "a", password: "b")
        let client = RecordingStubHTTPClient(responses: [:])
        let webdav = WebDAVClient(httpClient: client, config: emptyConfig)

        do {
            _ = try await webdav.download(path: "x.json")
            XCTFail("expected invalidBaseURL to be thrown")
        } catch WebDAVClientError.invalidBaseURL {
            // expected
        }
    }

    func testListDirectorySendsPROPFINDWithDepthOneAndFiltersOutTheFolderItself() async throws {
        let xml = """
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/YueDu/Books/</D:href>
            <D:propstat><D:prop><D:displayname>Books</D:displayname>
              <D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
          </D:response>
          <D:response>
            <D:href>/YueDu/Books/novel.txt</D:href>
            <D:propstat><D:prop><D:displayname>novel.txt</D:displayname>
              <D:resourcetype/></D:prop></D:propstat>
          </D:response>
        </D:multistatus>
        """
        let client = RecordingStubHTTPClient(responses: [
            "https://dav.example.com/YueDu/Books": HTTPResponse(finalURL: "x", statusCode: 207, body: xml)
        ])
        let webdav = WebDAVClient(httpClient: client, config: config)

        let items = try await webdav.listDirectory(path: "Books")

        XCTAssertEqual(items.map(\.name), ["novel.txt"])
        let recorded = await client.recorded
        XCTAssertEqual(recorded[0].method, "PROPFIND")
        XCTAssertEqual(recorded[0].headers["Depth"], "1")
    }

    func testListDirectoryThrowsOnNonSuccessStatus() async throws {
        let client = RecordingStubHTTPClient(responses: [
            "https://dav.example.com/YueDu/Books": HTTPResponse(finalURL: "x", statusCode: 404, body: "")
        ])
        let webdav = WebDAVClient(httpClient: client, config: config)

        do {
            _ = try await webdav.listDirectory(path: "Books")
            XCTFail("expected unexpectedStatus to be thrown")
        } catch WebDAVClientError.unexpectedStatus(let code) {
            XCTAssertEqual(code, 404)
        }
    }
}
