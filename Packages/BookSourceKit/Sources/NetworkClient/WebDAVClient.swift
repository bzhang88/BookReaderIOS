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

    /// Lists a directory's immediate children (`Depth: 1`) -- used for browsing a WebDAV folder to
    /// pick a book file to import, distinct from `download`/`upload` which already know the exact
    /// path they want. Filters out the queried directory's own entry: PROPFIND(Depth: 1) returns
    /// the collection itself as the first `<response>` alongside its children, and a browse UI only
    /// wants the children.
    public func listDirectory(path: String) async throws -> [WebDAVItem] {
        let url = try resolvedURL(path)
        var headers = authHeaders()
        headers["Depth"] = "1"
        headers["Content-Type"] = "application/xml; charset=utf-8"
        let propfindBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:"><D:prop><D:displayname/><D:resourcetype/></D:prop></D:propfind>
        """
        let response = try await httpClient.fetch(HTTPRequest(
            url: url, method: "PROPFIND", headers: headers, body: Data(propfindBody.utf8)
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw WebDAVClientError.unexpectedStatus(response.statusCode)
        }
        let allItems = try WebDAVPropfindParser.parse(Data(response.body.utf8))
        let requestedName = path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "/").last
            .map(String.init)
        return allItems.filter { item in
            guard item.isDirectory, let requestedName else { return true }
            let itemTrailingSegment = item.href
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .split(separator: "/").last
                .map { ($0.removingPercentEncoding ?? String($0)) }
            return itemTrailingSegment != requestedName
        }
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

    /// Real bug found comparing against Legado: `path` used to be appended to `base` with zero
    /// percent-encoding. For a Chinese novel reader, WebDAV folder/file names routinely contain
    /// Chinese characters or spaces (a real book title, or `WebDAVPropfindParser`'s raw, unencoded
    /// `displayname`) -- `URL(string:)` on the caller side (`URLSessionHTTPClient.fetch`) returns
    /// `nil` for a string containing a literal space or non-ASCII character, so "browse/import from
    /// WebDAV" would fail outright for almost any real book file. `.urlPathAllowed` already treats
    /// `/` as allowed, so this encodes the whole path in one pass without splitting on path
    /// separators first.
    private func resolvedURL(_ path: String) throws -> String {
        guard !config.baseURL.isEmpty else { throw WebDAVClientError.invalidBaseURL(config.baseURL) }
        let base = config.baseURL.hasSuffix("/") ? config.baseURL : config.baseURL + "/"
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return base + encodedPath
    }
}
