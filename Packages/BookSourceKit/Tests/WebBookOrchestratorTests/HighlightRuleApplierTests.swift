import XCTest
import BookSourceModel
@testable import WebBookOrchestrator

final class HighlightRuleApplierTests: XCTestCase {
    private typealias Segment = HighlightRuleApplier.Segment

    func testNoRulesReturnsOneUnhighlightedSegment() {
        let segments = HighlightRuleApplier.segments([], in: "plain text")
        XCTAssertEqual(segments, [Segment(text: "plain text")])
    }

    func testSingleMatchInMiddleProducesThreeSegments() {
        let rule = HighlightRule(name: "Name", pattern: "张三")
        let segments = HighlightRuleApplier.segments([rule], in: "他对张三说了什么")
        XCTAssertEqual(segments, [
            Segment(text: "他对"),
            Segment(text: "张三", rule: rule),
            Segment(text: "说了什么")
        ])
    }

    func testMultipleNonOverlappingMatches() {
        let rule = HighlightRule(name: "Name", pattern: "张三|李四")
        let segments = HighlightRuleApplier.segments([rule], in: "张三和李四是朋友")
        XCTAssertEqual(segments, [
            Segment(text: "张三", rule: rule),
            Segment(text: "和"),
            Segment(text: "李四", rule: rule),
            Segment(text: "是朋友")
        ])
    }

    func testDisabledRuleProducesNoHighlight() {
        let rule = HighlightRule(name: "Off", pattern: "张三", enabled: false)
        let segments = HighlightRuleApplier.segments([rule], in: "张三来了")
        XCTAssertEqual(segments, [Segment(text: "张三来了")])
    }

    func testOverlappingMatchesFromDifferentRulesAreMerged() {
        let rules = [
            HighlightRule(name: "A", pattern: "abcd"),
            HighlightRule(name: "B", pattern: "cdef")
        ]
        // "abcd" matches [0,4), "cdef" matches [2,6) -- overlapping, should merge into one [0,6)
        // span styled with the earlier-starting match's rule (A).
        let segments = HighlightRuleApplier.segments(rules, in: "abcdefg")
        XCTAssertEqual(segments, [
            Segment(text: "abcdef", rule: rules[0]),
            Segment(text: "g")
        ])
    }

    func testMatchAtVeryStartAndEndHasNoEmptySegments() {
        let rule = HighlightRule(name: "Edge", pattern: "^x|x$")
        let segments = HighlightRuleApplier.segments([rule], in: "xmiddlex")
        XCTAssertEqual(segments, [
            Segment(text: "x", rule: rule),
            Segment(text: "middle"),
            Segment(text: "x", rule: rule)
        ])
    }

    func testMalformedRegexIsSkipped() {
        let rule = HighlightRule(name: "Broken", pattern: "(unclosed")
        let segments = HighlightRuleApplier.segments([rule], in: "unchanged text")
        XCTAssertEqual(segments, [Segment(text: "unchanged text")])
    }

    func testTitleOnlyRuleAppliesWhenRenderingATitleButNotBody() {
        let rule = HighlightRule(name: "TitleOnly", pattern: "张三", targetScope: .title)
        let titleSegments = HighlightRuleApplier.segments([rule], in: "张三来了", isTitle: true)
        XCTAssertEqual(titleSegments, [Segment(text: "张三", rule: rule), Segment(text: "来了")])

        let bodySegments = HighlightRuleApplier.segments([rule], in: "张三来了", isTitle: false)
        XCTAssertEqual(bodySegments, [Segment(text: "张三来了")])
    }

    func testBodyOnlyRuleAppliesWhenRenderingBodyButNotATitle() {
        let rule = HighlightRule(name: "BodyOnly", pattern: "张三", targetScope: .body)
        let bodySegments = HighlightRuleApplier.segments([rule], in: "张三来了", isTitle: false)
        XCTAssertEqual(bodySegments, [Segment(text: "张三", rule: rule), Segment(text: "来了")])

        let titleSegments = HighlightRuleApplier.segments([rule], in: "张三来了", isTitle: true)
        XCTAssertEqual(titleSegments, [Segment(text: "张三来了")])
    }

    func testAllScopeRuleAppliesToBothTitleAndBody() {
        let rule = HighlightRule(name: "All", pattern: "张三", targetScope: .all)
        XCTAssertEqual(
            HighlightRuleApplier.segments([rule], in: "张三来了", isTitle: true),
            HighlightRuleApplier.segments([rule], in: "张三来了", isTitle: false)
        )
    }
}
