import XCTest
@testable import RuleEngine

final class TextSimilarityTests: XCTestCase {
    func testIdenticalStringsAreFullyEqual() {
        XCTAssertEqual(TextSimilarity.ratio("大明王", "大明王"), 1.0)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(TextSimilarity.ratio("ABC", "abc"), 1.0)
    }

    func testBothEmptyIsFullyEqual() {
        XCTAssertEqual(TextSimilarity.ratio("", ""), 1.0)
    }

    func testCompletelyDifferentSingleCharactersIsZero() {
        XCTAssertEqual(TextSimilarity.ratio("a", "b"), 0.0)
    }

    func testOneExtraCharacterOutOfFourIsSeventyFivePercent() {
        // "大明王" (3) vs "大明王朝" (4): 1 insertion, edit distance 1, max length 4 -> 1 - 1/4 = 0.75
        XCTAssertEqual(TextSimilarity.ratio("大明王", "大明王朝"), 0.75, accuracy: 0.0001)
    }

    func testPartialOverlapIsBetweenZeroAndOne() {
        let ratio = TextSimilarity.ratio("大明王", "大明官")
        XCTAssertGreaterThan(ratio, 0)
        XCTAssertLessThan(ratio, 1)
    }

    func testSymmetric() {
        let a = "从斗破开始的系统代理人"
        let b = "斗罗之诸天降临"
        XCTAssertEqual(TextSimilarity.ratio(a, b), TextSimilarity.ratio(b, a), accuracy: 0.0001)
    }
}
