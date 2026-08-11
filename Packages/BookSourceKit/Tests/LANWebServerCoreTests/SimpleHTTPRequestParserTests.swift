import XCTest
@testable import LANWebServerCore

final class SimpleHTTPRequestParserTests: XCTestCase {
    func testParsesMethodAndPlainPath() {
        let request = SimpleHTTPRequestParser.parse("GET / HTTP/1.1\r\nHost: 192.168.1.5:8080\r\n\r\n")
        XCTAssertEqual(request?.method, "GET")
        XCTAssertEqual(request?.path, "/")
        XCTAssertTrue(request?.query.isEmpty ?? false)
    }

    func testParsesQueryParameters() {
        let request = SimpleHTTPRequestParser.parse("GET /chapter?u=https://example.com/book&i=3 HTTP/1.1\r\n\r\n")
        XCTAssertEqual(request?.path, "/chapter")
        XCTAssertEqual(request?.query["u"], "https://example.com/book")
        XCTAssertEqual(request?.query["i"], "3")
    }

    func testDecodesPercentEncodedQueryValues() {
        let request = SimpleHTTPRequestParser.parse("GET /book?u=https%3A%2F%2Fexample.com%2Fa%20b HTTP/1.1\r\n\r\n")
        XCTAssertEqual(request?.query["u"], "https://example.com/a b")
    }

    func testMissingRequestLineReturnsNil() {
        XCTAssertNil(SimpleHTTPRequestParser.parse(""))
        XCTAssertNil(SimpleHTTPRequestParser.parse("garbage"))
    }

    func testQueryParameterWithoutValueDefaultsToEmptyString() {
        let request = SimpleHTTPRequestParser.parse("GET /book?u= HTTP/1.1\r\n\r\n")
        XCTAssertEqual(request?.query["u"], "")
    }
}
