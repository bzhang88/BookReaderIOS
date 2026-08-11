import XCTest
@testable import RuleEngine

final class RegexTesterTests: XCTestCase {
    func testFindsMultipleMatchesWithCaptureGroups() {
        let result = RegexTester.test(pattern: #"(\d+)-(\d+)"#, text: "a 1-2 b 30-40")
        guard case .success(let matches) = result else { return XCTFail("expected success") }
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].matchedText, "1-2")
        XCTAssertEqual(matches[0].groups, ["1", "2"])
        XCTAssertEqual(matches[1].matchedText, "30-40")
        XCTAssertEqual(matches[1].groups, ["30", "40"])
    }

    func testNoMatchesReturnsEmptyArrayNotError() {
        let result = RegexTester.test(pattern: "xyz", text: "abc")
        XCTAssertEqual(result, .success([]))
    }

    func testInvalidPatternReturnsFailure() {
        let result = RegexTester.test(pattern: "(unclosed", text: "abc")
        XCTAssertEqual(result, .failure(.invalidPattern))
    }

    func testEmptyPatternReturnsFailure() {
        let result = RegexTester.test(pattern: "", text: "abc")
        XCTAssertEqual(result, .failure(.invalidPattern))
    }

    func testCaseInsensitiveOptionMatchesDifferentCasing() {
        let result = RegexTester.test(pattern: "abc", text: "ABC", caseInsensitive: true)
        guard case .success(let matches) = result else { return XCTFail("expected success") }
        XCTAssertEqual(matches.map(\.matchedText), ["ABC"])
    }

    func testDotMatchesNewlinesOptionSpansLines() {
        let withoutOption = RegexTester.test(pattern: "a.b", text: "a\nb")
        XCTAssertEqual(withoutOption, .success([]))

        let withOption = RegexTester.test(pattern: "a.b", text: "a\nb", dotMatchesNewlines: true)
        guard case .success(let matches) = withOption else { return XCTFail("expected success") }
        XCTAssertEqual(matches.map(\.matchedText), ["a\nb"])
    }

    func testGroupThatDidNotParticipateIsNil() {
        let result = RegexTester.test(pattern: "(a)|(b)", text: "b")
        guard case .success(let matches) = result else { return XCTFail("expected success") }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].groups, [nil, "b"])
    }
}
