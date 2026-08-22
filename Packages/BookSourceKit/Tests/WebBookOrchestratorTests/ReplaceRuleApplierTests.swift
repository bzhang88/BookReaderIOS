import XCTest
import BookSourceModel
@testable import WebBookOrchestrator

final class ReplaceRuleApplierTests: XCTestCase {
    func testGlobalRuleAppliesRegardlessOfSource() {
        let rule = ReplaceRule(name: "Strip ad", pattern: "广告文字", replacement: "")
        let result = ReplaceRuleApplier.apply([rule], to: "正文广告文字结尾", bookName: "任意书名", sourceUrl: "https://any.example.com")
        XCTAssertEqual(result, "正文结尾")
    }

    func testSourceScopedRuleOnlyAppliesToThatSource() {
        let rule = ReplaceRule(name: "Site-specific", pattern: "junk", replacement: "", scope: "https://a.example.com")
        let matching = ReplaceRuleApplier.apply([rule], to: "text junk here", bookName: "任意书名", sourceUrl: "https://a.example.com")
        let nonMatching = ReplaceRuleApplier.apply([rule], to: "text junk here", bookName: "任意书名", sourceUrl: "https://b.example.com")

        XCTAssertEqual(matching, "text  here")
        XCTAssertEqual(nonMatching, "text junk here", "a rule scoped to a different source must not apply")
    }

    /// Confirmed against Legado's real `ReplaceRuleDao` query: `scope` is matched by plain substring
    /// containment against the book name too, not just the source URL.
    func testScopeAlsoMatchesByBookNameContainment() {
        let rule = ReplaceRule(name: "Book-specific", pattern: "junk", replacement: "", scope: "斗破苍穹")
        let matching = ReplaceRuleApplier.apply([rule], to: "text junk here", bookName: "斗破苍穹", sourceUrl: "https://any.example.com")
        let nonMatching = ReplaceRuleApplier.apply([rule], to: "text junk here", bookName: "完全不同的书", sourceUrl: "https://any.example.com")

        XCTAssertEqual(matching, "text  here")
        XCTAssertEqual(nonMatching, "text junk here")
    }

    /// The whole `scope` string just needs to *contain* the book name/source URL as a substring --
    /// a comma-separated list of several scopes works without any splitting/tokenizing, since the
    /// book name being a substring of the whole joined string is exactly what Legado's own `LIKE
    /// '%name%'` query checks.
    func testCommaSeparatedScopeMatchesAnyListedBookOrSource() {
        let rule = ReplaceRule(name: "Multi-scope", pattern: "junk", replacement: "", scope: "书名A,书名B,https://c.example.com")
        XCTAssertEqual(
            ReplaceRuleApplier.apply([rule], to: "junk", bookName: "书名A", sourceUrl: "https://any.example.com"), ""
        )
        XCTAssertEqual(
            ReplaceRuleApplier.apply([rule], to: "junk", bookName: "书名B", sourceUrl: "https://any.example.com"), ""
        )
        XCTAssertEqual(
            ReplaceRuleApplier.apply([rule], to: "junk", bookName: "不相关书名", sourceUrl: "https://c.example.com"), ""
        )
        XCTAssertEqual(
            ReplaceRuleApplier.apply([rule], to: "junk", bookName: "不相关书名", sourceUrl: "https://d.example.com"), "junk",
            "neither the book name nor the source URL appears anywhere in scope"
        )
    }

    func testExcludeScopeVetoesEvenAnUnscopedRule() {
        let rule = ReplaceRule(name: "Excluded", pattern: "junk", replacement: "", excludeScope: "斗破苍穹")
        let excluded = ReplaceRuleApplier.apply([rule], to: "junk", bookName: "斗破苍穹", sourceUrl: "https://any.example.com")
        let notExcluded = ReplaceRuleApplier.apply([rule], to: "junk", bookName: "其他书", sourceUrl: "https://any.example.com")

        XCTAssertEqual(excluded, "junk", "excludeScope should veto this book even though scope itself is empty (applies everywhere)")
        XCTAssertEqual(notExcluded, "")
    }

    /// An empty `bookName`/`sourceUrl` (e.g. `LocalReaderView`'s `sourceUrl: ""`) must never count
    /// as "contained" in a scope string, even though `"x".contains("")` is trivially true in Swift
    /// -- otherwise a rule scoped to a specific book/source would wrongly fire for a caller that
    /// doesn't know its own book name.
    func testEmptyBookNameOrSourceUrlNeverMatchesANonEmptyScope() {
        let rule = ReplaceRule(name: "Scoped", pattern: "junk", replacement: "", scope: "某本书")
        let result = ReplaceRuleApplier.apply([rule], to: "junk", bookName: "", sourceUrl: "")
        XCTAssertEqual(result, "junk")
    }

    func testDisabledRuleDoesNotApply() {
        let rule = ReplaceRule(name: "Off", pattern: "x", replacement: "y", enabled: false)
        let result = ReplaceRuleApplier.apply([rule], to: "xxx", bookName: "任意书名", sourceUrl: "https://any.example.com")
        XCTAssertEqual(result, "xxx")
    }

    /// `scopeContent` defaults `true` (every existing call site only ever purifies content), but an
    /// explicit `scopeContent: false` must still gate `.content` calls off.
    func testScopeContentFalseSkipsContentPurification() {
        let rule = ReplaceRule(name: "Title only", pattern: "x", replacement: "y", scopeTitle: true, scopeContent: false)
        let result = ReplaceRuleApplier.apply([rule], to: "xxx", bookName: "任意书名", sourceUrl: "https://any.example.com", textKind: .content)
        XCTAssertEqual(result, "xxx")
    }

    func testScopeTitleTrueAppliesToTitleTextKind() {
        let rule = ReplaceRule(name: "Title only", pattern: "x", replacement: "y", scopeTitle: true, scopeContent: false)
        let result = ReplaceRuleApplier.apply([rule], to: "xxx", bookName: "任意书名", sourceUrl: "https://any.example.com", textKind: .title)
        XCTAssertEqual(result, "yyy")
    }

    func testPlainTextModeDoesNotTreatPatternAsRegex() {
        let rule = ReplaceRule(name: "Literal", pattern: "a.b", replacement: "Z", isRegex: false)
        // If this were treated as regex, "." would match any character and also hit "axb".
        let result = ReplaceRuleApplier.apply([rule], to: "a.b axb", bookName: "任意书名", sourceUrl: "https://any.example.com")
        XCTAssertEqual(result, "Z axb")
    }

    func testRegexModeSupportsCaptureGroupsInReplacement() {
        let rule = ReplaceRule(name: "Reorder", pattern: #"(\d+)-(\d+)"#, replacement: "$2-$1")
        let result = ReplaceRuleApplier.apply([rule], to: "chapter 3-5", bookName: "任意书名", sourceUrl: "https://any.example.com")
        XCTAssertEqual(result, "chapter 5-3")
    }

    func testMalformedRegexIsSkippedRatherThanThrowing() {
        let rule = ReplaceRule(name: "Broken", pattern: "(unclosed", replacement: "x")
        let result = ReplaceRuleApplier.apply([rule], to: "unchanged", bookName: "任意书名", sourceUrl: "https://any.example.com")
        XCTAssertEqual(result, "unchanged")
    }

    func testMultipleRulesApplyInOrderEachFeedingTheNext() {
        let rules = [
            ReplaceRule(name: "First", pattern: "a", replacement: "b"),
            ReplaceRule(name: "Second", pattern: "b", replacement: "c")
        ]
        let result = ReplaceRuleApplier.apply(rules, to: "a", bookName: "任意书名", sourceUrl: "https://any.example.com")
        XCTAssertEqual(result, "c")
    }

    /// `order` (not list order) decides the actual apply sequence -- listed here deliberately
    /// out of the order they need to run in, to prove `order` (not array position) wins.
    func testRulesApplyByOrderFieldNotArrayPosition() {
        let rules = [
            ReplaceRule(name: "Second", pattern: "b", replacement: "c", order: 2),
            ReplaceRule(name: "First", pattern: "a", replacement: "b", order: 1)
        ]
        let result = ReplaceRuleApplier.apply(rules, to: "a", bookName: "任意书名", sourceUrl: "https://any.example.com")
        XCTAssertEqual(result, "c", "order:1 (a->b) must run before order:2 (b->c) regardless of array position")
    }

    func testApplyReportingMatchesOnlyListsRulesThatActuallyHit() {
        let hit = ReplaceRule(name: "Strip ad", pattern: "广告", replacement: "")
        let miss = ReplaceRule(name: "No hit", pattern: "不存在的文字", replacement: "")
        let outcome = ReplaceRuleApplier.applyReportingMatches(
            [hit, miss], to: "正文广告结尾", bookName: "任意书名", sourceUrl: "https://any.example.com"
        )
        XCTAssertEqual(outcome.result, "正文结尾")
        XCTAssertEqual(outcome.matchedRules.map(\.name), ["Strip ad"])
    }

    func testApplyReportingMatchesSkipsDisabledAndOutOfScopeRules() {
        let disabled = ReplaceRule(name: "Off", pattern: "x", replacement: "y", enabled: false)
        let wrongScope = ReplaceRule(name: "Other source", pattern: "x", replacement: "y", scope: "https://b.example.com")
        let outcome = ReplaceRuleApplier.applyReportingMatches(
            [disabled, wrongScope], to: "xxx", bookName: "任意书名", sourceUrl: "https://a.example.com"
        )
        XCTAssertEqual(outcome.result, "xxx")
        XCTAssertTrue(outcome.matchedRules.isEmpty)
    }

    func testApplyReportingMatchesEvaluatesEachRuleAgainstPriorRulesOutput() {
        let rules = [
            ReplaceRule(name: "First", pattern: "a", replacement: "b"),
            ReplaceRule(name: "Second", pattern: "b", replacement: "c")
        ]
        let outcome = ReplaceRuleApplier.applyReportingMatches(rules, to: "a", bookName: "任意书名", sourceUrl: "https://any.example.com")
        XCTAssertEqual(outcome.result, "c")
        XCTAssertEqual(outcome.matchedRules.map(\.name), ["First", "Second"], "Second's own pattern 'b' only appears after First already ran")
    }
}
