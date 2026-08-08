import XCTest
@testable import RuleEngine

final class CombinatorSplitterTests: XCTestCase {
    func testNoCombinator() {
        let (combinator, parts) = CombinatorSplitter.split("class.name@text")
        XCTAssertNil(combinator)
        XCTAssertEqual(parts, ["class.name@text"])
    }

    func testConcat() {
        let (combinator, parts) = CombinatorSplitter.split("class.a@text&&class.b@text")
        XCTAssertEqual(combinator, .concat)
        XCTAssertEqual(parts, ["class.a@text", "class.b@text"])
    }

    func testFirstNonEmpty() {
        let (combinator, parts) = CombinatorSplitter.split("class.a@text||class.b@text||class.c@text")
        XCTAssertEqual(combinator, .firstNonEmpty)
        XCTAssertEqual(parts, ["class.a@text", "class.b@text", "class.c@text"])
    }

    func testZip() {
        let (combinator, parts) = CombinatorSplitter.split("class.a@text%%class.b@text")
        XCTAssertEqual(combinator, .zip)
        XCTAssertEqual(parts, ["class.a@text", "class.b@text"])
    }

    func testEarliestDelimiterWins() {
        // "||" appears before "&&" here, so the whole string must split on "||" only.
        let (combinator, parts) = CombinatorSplitter.split("a||b&&c")
        XCTAssertEqual(combinator, .firstNonEmpty)
        XCTAssertEqual(parts, ["a", "b&&c"])
    }

    func testDelimiterInsideBracketsIsNotASplitPoint() {
        // A literal "&&" inside a CSS attribute-value predicate must not be treated as a combinator.
        let rule = "[attr=\"a&&b\"]@text"
        let (combinator, parts) = CombinatorSplitter.split(rule)
        XCTAssertNil(combinator)
        XCTAssertEqual(parts, [rule])
    }

    func testDelimiterInsideParenthesesIsNotASplitPoint() {
        let rule = "p:contains(a&&b)@text"
        let (combinator, parts) = CombinatorSplitter.split(rule)
        XCTAssertNil(combinator)
        XCTAssertEqual(parts, [rule])
    }
}
