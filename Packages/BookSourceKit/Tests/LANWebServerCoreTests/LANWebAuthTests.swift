import XCTest
@testable import LANWebServerCore

final class LANWebAuthTests: XCTestCase {
    func testNilTokenMeansAuthIsOff() {
        let request = SimpleHTTPRequest(method: "GET", path: "/", query: [:])
        XCTAssertTrue(LANWebAuth.isAuthorized(request: request, requiredToken: nil))
    }

    func testEmptyTokenMeansAuthIsOff() {
        let request = SimpleHTTPRequest(method: "GET", path: "/", query: [:])
        XCTAssertTrue(LANWebAuth.isAuthorized(request: request, requiredToken: ""))
    }

    func testMatchingTokenIsAuthorized() {
        let request = SimpleHTTPRequest(method: "GET", path: "/", query: ["token": "secret123"])
        XCTAssertTrue(LANWebAuth.isAuthorized(request: request, requiredToken: "secret123"))
    }

    func testMissingTokenIsRejected() {
        let request = SimpleHTTPRequest(method: "GET", path: "/", query: [:])
        XCTAssertFalse(LANWebAuth.isAuthorized(request: request, requiredToken: "secret123"))
    }

    func testWrongTokenIsRejected() {
        let request = SimpleHTTPRequest(method: "GET", path: "/", query: ["token": "wrong"])
        XCTAssertFalse(LANWebAuth.isAuthorized(request: request, requiredToken: "secret123"))
    }
}
