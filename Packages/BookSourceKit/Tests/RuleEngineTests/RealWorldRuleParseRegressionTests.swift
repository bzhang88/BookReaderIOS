import XCTest
@testable import RuleEngine

/// A curated sample of real rule strings pulled from a real ~190-source 书源仓库 collection
/// (not invented) via a one-off analysis pass, kept here as a permanent regression fixture.
/// The analysis found real sources using combinators with exclude-index selectors, mixed
/// single/double-quoted XPath predicates, `//text()`/`//@attr` with no preceding tag step, and
/// dense Chinese-text regex purify patterns -- none of which were exercised by the hand-written
/// tests elsewhere in this suite. This test only asserts "parses without an unexpected throw"
/// (matching the real app's behavior of clearly reporting unsupported features rather than
/// crashing); it does not assert specific extracted values since these rules were captured
/// without their originating HTML/JSON.
final class RealWorldRuleParseRegressionTests: XCTestCase {
    static let realRuleStrings: [String] = [
        // Combinators, incl. exclude-index selectors and Chinese purify text
        "$.CName&&$.BookStatus",
        "class.c_row||class.booksub",
        "class.c_subject@tag.a@text||id.content@tag.h1@text##全文阅读",
        "class.c_value.0@text||class.fl.1@tag.td.1@text",
        "id.searchList@tag.div!0||id.catalog@tag.div!0",
        "class.s1@tag.a@text||tag.h3@tag.a@text",

        // JSONPath: recursive descent + nested wildcards
        "$..data[*]",
        "$..list[*].list[*]",

        // XPath: following-sibling::, single vs double quoted predicates, bare text()/@attr
        "//*[@id=\"list\"]//dt[2]/following-sibling::dd/a",
        "//meta[@property=\"og:title\"]/@content",
        "//*[@property='og:novel:book_name']/@content",
        "//*[@id='list']//dd/a",
        "//text()",
        "//@href",

        // Regex purify: OnlyOne form and a dense real Chinese ad-text pattern
        "##作者.([^<]+)##$1###",
        "text##[【（](求(评|订阅|[全首][订定]|收藏|月票)|(推荐票|\\d+字)加更|第?[一二三四五六七八九十]{1,3}更).*?[）】]",

        // AllInOne regex, incl. a dense multi-group real-world pattern
        ":\"chapter\"[^\"]+\"([^\"]*)\"[^>]+>([^<]*)",
        ":\\{.{13}:(\\d+),\"C\":(\\d+).{29}([^\"]*)[^V]*V\":(\\d)[^\\}]*"
    ]

    func testAllRealRuleStringsParseWithoutUnexpectedThrow() {
        for rule in Self.realRuleStrings {
            do {
                _ = try RuleStringParser.parse(rule)
            } catch is RuleEngineError {
                // Expected/typed rejection (e.g. a rare unsupported feature) is fine -- the app
                // surfaces these as "unsupported," which is correct behavior, not a bug.
                continue
            } catch {
                XCTFail("unexpected non-RuleEngineError throw for rule '\(rule)': \(error)")
            }
        }
    }
}
