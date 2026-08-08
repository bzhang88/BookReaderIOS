import Foundation

public struct HTTPRequest {
    public var url: String
    public var method: String
    public var headers: [String: String]
    public var body: Data?
    /// Real book sources are frequently slow or dead; a generous-but-finite default keeps a
    /// single bad source from hanging a whole search/TOC fetch indefinitely.
    public var timeout: TimeInterval

    public init(
        url: String, method: String = "GET", headers: [String: String] = [:], body: Data? = nil,
        timeout: TimeInterval = 15
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct HTTPResponse {
    /// The final URL after any redirects — chapter/TOC/content rules resolve relative URLs
    /// against this, not the originally-requested URL.
    public var finalURL: String
    public var statusCode: Int
    public var body: String

    public init(finalURL: String, statusCode: Int, body: String) {
        self.finalURL = finalURL
        self.statusCode = statusCode
        self.body = body
    }
}

public enum HTTPClientError: Error, Equatable {
    case invalidURL(String)
    case nonTextResponse
}

public protocol HTTPClient: Sendable {
    func fetch(_ request: HTTPRequest) async throws -> HTTPResponse
}
