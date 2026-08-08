import XCTest
@testable import RuleEngine

final class JSONPathEvaluatorTests: XCTestCase {
    func testSimpleDotPath() throws {
        let root = try JSONValue.parse(#"{"author": "Jane Doe"}"#)
        XCTAssertEqual(JSONPathEvaluator.extractStrings("$.author", from: root), ["Jane Doe"])
    }

    func testNestedDotPath() throws {
        let root = try JSONValue.parse(#"{"chapter": {"body": "Once upon a time"}}"#)
        XCTAssertEqual(JSONPathEvaluator.extractStrings("$.chapter.body", from: root), ["Once upon a time"])
    }

    func testArrayIndex() throws {
        let root = try JSONValue.parse(#"{"list": ["a", "b", "c"]}"#)
        XCTAssertEqual(JSONPathEvaluator.extractStrings("$.list[1]", from: root), ["b"])
    }

    func testNegativeArrayIndex() throws {
        let root = try JSONValue.parse(#"{"list": ["a", "b", "c"]}"#)
        XCTAssertEqual(JSONPathEvaluator.extractStrings("$.list[-1]", from: root), ["c"])
    }

    func testWildcardOverArrayOfObjects() throws {
        let root = try JSONValue.parse(#"{"books": [{"title": "A"}, {"title": "B"}]}"#)
        let values = JSONPathEvaluator.extractValues("$.books[*]", from: root)
        XCTAssertEqual(values.compactMap { $0["title"]?.stringValue }, ["A", "B"])
    }

    func testTrailingDotBeforeBracketIsTolerated() throws {
        // Real-world rule from Legado's docs: "$.chapterInfo.chapters.[*]"
        let root = try JSONValue.parse(#"{"chapterInfo": {"chapters": [{"title": "Ch1"}, {"title": "Ch2"}]}}"#)
        let values = JSONPathEvaluator.extractValues("$.chapterInfo.chapters.[*]", from: root)
        XCTAssertEqual(values.compactMap { $0["title"]?.stringValue }, ["Ch1", "Ch2"])
    }

    func testRecursiveDescentThenWildcard() throws {
        // Real-world rule from Legado's docs: "$..books[*]"
        let root = try JSONValue.parse(#"{"data": {"books": [{"title": "X"}, {"title": "Y"}]}}"#)
        let values = JSONPathEvaluator.extractValues("$..books[*]", from: root)
        XCTAssertEqual(values.compactMap { $0["title"]?.stringValue }, ["X", "Y"])
    }

    func testBareRootReturnsWholeValue() throws {
        let root = try JSONValue.parse(#"{"a": 1}"#)
        XCTAssertEqual(JSONPathEvaluator.extractValues("$", from: root), [root])
    }

    func testMissingKeyReturnsEmpty() throws {
        let root = try JSONValue.parse(#"{"a": 1}"#)
        XCTAssertEqual(JSONPathEvaluator.extractStrings("$.missing", from: root), [])
    }

    func testNumberCoercesToIntegerLikeString() throws {
        let root = try JSONValue.parse(#"{"id": 12345}"#)
        XCTAssertEqual(JSONPathEvaluator.extractStrings("$.id", from: root), ["12345"])
    }

    func testBooleanDistinguishedFromNumber() throws {
        let root = try JSONValue.parse(#"{"flag": true, "count": 1}"#)
        XCTAssertEqual(root["flag"], .bool(true))
        XCTAssertEqual(root["count"], .number(1))
    }
}
