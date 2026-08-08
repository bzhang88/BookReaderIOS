import XCTest
@testable import RuleEngine

final class IndexSelectorTests: XCTestCase {
    func testLegacySelectList() {
        let (remainder, selector) = IndexSelector.extract(from: "tag.div.-1:10:2")
        XCTAssertEqual(remainder, "tag.div")
        XCTAssertEqual(selector?.exclude, false)
        XCTAssertEqual(selector?.specs, [.single(-1), .single(10), .single(2)])
        // 12-element list: index -1 -> 11, 10 -> 10, 2 -> 2 (10 is in range, kept)
        XCTAssertEqual(selector?.apply(count: 12), [11, 10, 2])
    }

    func testLegacyExcludeList() {
        let (remainder, selector) = IndexSelector.extract(from: "tag.div!0:3")
        XCTAssertEqual(remainder, "tag.div")
        XCTAssertEqual(selector?.exclude, true)
        // 5-element list, excluding 0 and 3 -> [1, 2, 4]
        XCTAssertEqual(selector?.apply(count: 5), [1, 2, 4])
    }

    func testNoIndexSuffix() {
        let (remainder, selector) = IndexSelector.extract(from: "tag.div")
        XCTAssertEqual(remainder, "tag.div")
        XCTAssertNil(selector)
    }

    func testBracketMixedSingleAndRange() {
        let (remainder, selector) = IndexSelector.extract(from: "tag.div[1, 3:5]")
        XCTAssertEqual(remainder, "tag.div")
        XCTAssertEqual(selector?.exclude, false)
        // 10-element list: single 1, then range 3...5
        XCTAssertEqual(selector?.apply(count: 10), [1, 3, 4, 5])
    }

    func testBracketExclude() {
        let (remainder, selector) = IndexSelector.extract(from: "tag.div[!0:2]")
        XCTAssertEqual(remainder, "tag.div")
        XCTAssertEqual(selector?.exclude, true)
        // 5-element list, excluding 0,1,2 -> remaining ascending [3, 4]
        XCTAssertEqual(selector?.apply(count: 5), [3, 4])
    }

    func testBracketReversedRangeReversesWholeList() {
        let (remainder, selector) = IndexSelector.extract(from: "tag.div[-1:0]")
        XCTAssertEqual(remainder, "tag.div")
        // 4-element list: -1 -> 3, 0 -> 0, since end(0) < start(3) this walks downTo => 3,2,1,0
        XCTAssertEqual(selector?.apply(count: 4), [3, 2, 1, 0])
    }

    func testBracketDoesNotConsumeAttributeSelector() {
        // A raw CSS attribute selector step should NOT be mistaken for an index suffix.
        let (remainder, selector) = IndexSelector.extract(from: "[property=og:image]")
        XCTAssertEqual(remainder, "[property=og:image]")
        XCTAssertNil(selector)
    }

    func testNegativeIndexOutOfRangeIsDropped() {
        let (_, selector) = IndexSelector.extract(from: "tag.div.-99")
        XCTAssertEqual(selector?.apply(count: 5), [])
    }
}
