import XCTest
@testable import LANWebServerCore

final class SimpleHTTPResponseBuilderTests: XCTestCase {
    func testBuildHTMLProducesWellFormedResponse() {
        let data = SimpleHTTPResponseBuilder.buildHTML(html: "<p>hi</p>")
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(text.contains("Content-Type: text/html; charset=utf-8\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 9\r\n"))
        XCTAssertTrue(text.contains("Connection: close\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n<p>hi</p>"))
    }

    func testContentLengthMatchesUTF8ByteCountNotCharacterCount() {
        // "书" is one Character but three UTF-8 bytes -- Content-Length must be byte count.
        let data = SimpleHTTPResponseBuilder.buildHTML(html: "书")
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("Content-Length: 3\r\n"))
    }

    func testCustomStatusCode() {
        let data = SimpleHTTPResponseBuilder.buildHTML(statusCode: 404, html: "not found")
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
    }
}
