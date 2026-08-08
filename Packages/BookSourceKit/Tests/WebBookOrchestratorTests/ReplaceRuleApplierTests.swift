import XCTest
import BookSourceModel
@testable import WebBookOrchestrator

final class ReplaceRuleApplierTests: XCTestCase {
    func testGlobalRuleAppliesRegardlessOfSource() {
        let rule = ReplaceRule(name: "Strip ad", pattern: "广告文字", replacement: "")
        let result = ReplaceRuleApplier.apply([rule], to: "正文广告文字结尾", sourceUrl: "https://any.example.com")
        XCTAssertEqual(result, "正文结尾")
    }

    func testSourceScopedRuleOnlyAppliesToThatSource() {
        let rule = ReplaceRule(name: "Site-specific", pattern: "junk", replacement: "", scopeSourceUrl: "https://a.example.com")
        let matching = ReplaceRuleApplier.apply([rule], to: "text junk here", sourceUrl: "https://a.example.com")
        let nonMatching = ReplaceRuleApplier.apply([rule], to: "text junk here", sourceUrl: "https://b.example.com")

        XCTAssertEqual(matching, "text  here")
        XCTAssertEqual(nonMatching, "text junk here", "a rule scoped to a different source must not apply")
    }

    func testDisabledRuleDoesNotApply() {
        let rule = ReplaceRule(name: "Off", pattern: "x", replacement: "y", enabled: false)
        let result = ReplaceRuleApplier.apply([rule], to: "xxx", sourceUrl: "https://any.example.com")
        XCTAssertEqual(result, "xxx")
    }

    func testPlainTextModeDoesNotTreatPatternAsRegex() {
        let rule = ReplaceRule(name: "Literal", pattern: "a.b", replacement: "Z", isRegex: false)
        // If this were treated as regex, "." would match any character and also hit "axb".
        let result = ReplaceRuleApplier.apply([rule], to: "a.b axb", sourceUrl: "https://any.example.com")
        XCTAssertEqual(result, "Z axb")
    }

    func testRegexModeSupportsCaptureGroupsInReplacement() {
        let rule = ReplaceRule(name: "Reorder", pattern: #"(\d+)-(\d+)"#, replacement: "$2-$1")
        let result = ReplaceRuleApplier.apply([rule], to: "chapter 3-5", sourceUrl: "https://any.example.com")
        XCTAssertEqual(result, "chapter 5-3")
    }

    func testMalformedRegexIsSkippedRatherThanThrowing() {
        let rule = ReplaceRule(name: "Broken", pattern: "(unclosed", replacement: "x")
        let result = ReplaceRuleApplier.apply([rule], to: "unchanged", sourceUrl: "https://any.example.com")
        XCTAssertEqual(result, "unchanged")
    }

    func testMultipleRulesApplyInOrderEachFeedingTheNext() {
        let rules = [
            ReplaceRule(name: "First", pattern: "a", replacement: "b"),
            ReplaceRule(name: "Second", pattern: "b", replacement: "c")
        ]
        let result = ReplaceRuleApplier.apply(rules, to: "a", sourceUrl: "https://any.example.com")
        XCTAssertEqual(result, "c")
    }
}
