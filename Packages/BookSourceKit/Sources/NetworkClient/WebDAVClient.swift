import Foundation

public struct WebDAVConfig: Equatable, Sendable {
    /// The backup directory's URL, e.g. `https://dav.example.com/remote.php/webdav/YueDu/` --
    /// trailing slash optional, normalized in `resolvedURL`.
    public var baseURL: String
    public var username: String
    public var password: String

    public init(baseURL: String, username: String, password: String) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }
}

public enum WebDAVClientError: Error, Equatable {
    case invalidBaseURL(String)
    case unexpectedStatus(Int)
}

/// A minimal WebDAV client (PUT/GET/MKCOL) built directly on the existing `HTTPClient`
/// abstraction -- WebDAV is just HTTP with a few extra verbs and Basic Auth, so this doesn't need
/// its own networking stack, only a thin layer over the one every other service already uses
/// (which is also why it's just as testable with `StubHTTPClient` as everything else).
public struct WebDAVClient {
    private let httpClient: HTTPClient
    private let config: WebDAVConfig

    public init(httpClient: HTTPClient, config: WebDAVConfig) {
        self.httpClient = httpClient
        self.config = config
    }

    public func upload(path: String, content: String) async throws {
        let url = try resolvedURL(path)
        let response = try await httpClient.fetch(HTTPRequest(
            url: url, method: "PUT", headers: authHeaders(), body: Data(content.utf8)
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw WebDAVClientError.unexpectedStatus(response.statusCode)
        }
    }

    public func download(path: String) async throws -> String {
        let url = try resolvedURL(path)
        let response = try await httpClient.fetch(HTTPRequest(url: url, method: "GET", headers: authHeaders()))
        guard (200..<300).contains(response.statusCode) else {
            throw WebDAVClientError.unexpectedStatus(response.statusCode)
        }
        return response.body
    }

    /// Idempotent -- a WebDAV server reports 405 (Method Not Allowed) for MKCOL on a directory
    /// that already exists, which is a success case here, not an error to propagate.
    public func makeDirectoryIfNeeded(path: String) async throws {
        let url = try resolvedURL(path)
        let response = try await httpClient.fetch(HTTPRequest(url: url, method: "MKCOL", headers: authHeaders()))
        guard response.statusCode == 201 || response.statusCode == 405 else {
            throw WebDAVClientError.unexpectedStatus(response.statusCode)
        }
    }

    private func authHeaders() -> [String: String] {
        let raw = "\(config.username):\(config.password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return ["Authorization": "Basic \(encoded)"]
    }

    private func resolvedURL(_ path: String) throws -> String {
        guard !config.baseURL.isEmpty else { throw WebDAVClientError.invalidBaseURL(config.baseURL) }
        let base = config.baseURL.hasSuffix("/") ? config.baseURL : config.baseURL + "/"
        return base + path
    }
}
