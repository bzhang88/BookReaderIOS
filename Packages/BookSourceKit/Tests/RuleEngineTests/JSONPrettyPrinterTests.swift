import XCTest
@testable import RuleEngine

final class JSONPrettyPrinterTests: XCTestCase {
    func testFormatsCompactObjectWithIndentation() {
        let result = JSONPrettyPrinter.format(#"{"b":1,"a":2}"#)
        guard case .success(let formatted) = result else { return XCTFail("expected success") }
        XCTAssertTrue(formatted.contains("\n"))
        // .sortedKeys keeps output deterministic regardless of the input's key order.
        XCTAssertTrue(formatted.range(of: "\"a\"")!.lowerBound < formatted.range(of: "\"b\"")!.lowerBound)
    }

    func testFormatsArray() {
        let result = JSONPrettyPrinter.format("[1,2,3]")
        guard case .success(let formatted) = result else { return XCTFail("expected success") }
        XCTAssertTrue(formatted.contains("1"))
        XCTAssertTrue(formatted.contains("3"))
    }

    func testInvalidJSONReturnsFailure() {
        let result = JSONPrettyPrinter.format("{not json")
        XCTAssertEqual(result, .failure(.invalidJSON))
    }

    func testEmptyStringReturnsFailure() {
        let result = JSONPrettyPrinter.format("")
        XCTAssertEqual(result, .failure(.invalidJSON))
    }
}
