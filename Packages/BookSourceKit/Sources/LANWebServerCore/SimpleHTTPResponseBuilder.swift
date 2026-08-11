import Foundation

/// Builds a minimal-but-valid HTTP/1.1 response. Always sends `Connection: close` and the server
/// always closes right after writing -- with no keep-alive to manage, a browser's one-page-per-
/// request/response cycle needs no more than this to work correctly.
public enum SimpleHTTPResponseBuilder {
    public static func build(statusCode: Int, contentType: String, body: Data) -> Data {
        let headerText = "HTTP/1.1 \(statusCode) \(statusText(for: statusCode))\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        var response = Data(headerText.utf8)
        response.append(body)
        return response
    }

    public static func buildHTML(statusCode: Int = 200, html: String) -> Data {
        build(statusCode: statusCode, contentType: "text/html; charset=utf-8", body: Data(html.utf8))
    }

    static func statusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        default: return "Error"
        }
    }
}
