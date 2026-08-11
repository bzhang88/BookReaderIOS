import Foundation

public struct SimpleHTTPRequest: Equatable {
    public var method: String
    public var path: String
    public var query: [String: String]

    public init(method: String, path: String, query: [String: String] = [:]) {
        self.method = method
        self.path = path
        self.query = query
    }
}

/// Parses just the request line (`GET /path?x=1 HTTP/1.1`) out of a raw HTTP request -- headers and
/// body are irrelevant to this server, since every page it serves is fully self-contained (inline
/// HTML, no external CSS/JS/image requests), so nothing downstream ever needs to look at them.
public enum SimpleHTTPRequestParser {
    public static func parse(_ raw: String) -> SimpleHTTPRequest? {
        guard let firstLine = raw.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return nil
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let target = String(parts[1])
        let (path, query) = splitPathAndQuery(target)
        return SimpleHTTPRequest(method: method, path: path, query: query)
    }

    static func splitPathAndQuery(_ target: String) -> (path: String, query: [String: String]) {
        let components = target.split(separator: "?", maxSplits: 1)
        let rawPath = String(components.first ?? "")
        let path = rawPath.removingPercentEncoding ?? rawPath

        var query: [String: String] = [:]
        if components.count > 1 {
            for pair in components[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                guard let rawKey = kv.first else { continue }
                let key = String(rawKey).removingPercentEncoding ?? String(rawKey)
                let rawValue = kv.count > 1 ? String(kv[1]) : ""
                let value = rawValue.removingPercentEncoding ?? rawValue
                query[key] = value
            }
        }
        return (path, query)
    }
}
