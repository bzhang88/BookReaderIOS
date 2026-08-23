import XCTest
import BookSourceModel
@testable import WebBookOrchestrator

final class DictLookupServiceTests: XCTestCase {
    /// Uses a fixed (non-`{{key}}`-templated) URL so this exercises `DictLookupService`'s own
    /// fetch+extract logic without touching `{{ }}` substitution, which needs JavaScriptCore --
    /// unavailable on this Windows dev machine (see the JS-gated test below for that half).
    func testLooksUpWordAndExtractsDefinition() async throws {
        let html = """
        <html><body>
        <div class="definition">名词，指代书中虚构的概念。</div>
        </body></html>
        """
        let rule = DictRule(name: "测试词典", urlRule: "https://dict.example.com/search?w=fixed", showRule: "@css:.definition@text")
        let client = StubHTTPClient(responses: ["https://dict.example.com/search?w=fixed": html])

        let result = try await DictLookupService.lookup(rule: rule, word: "书", httpClient: client)
        XCTAssertEqual(result, "名词，指代书中虚构的概念。")
    }

    func testEmptyExtractionThrowsEmptyResult() async throws {
        let html = "<html><body><div class=\"other\">nothing relevant</div></body></html>"
        let rule = DictRule(name: "测试词典", urlRule: "https://dict.example.com/search?w=fixed", showRule: "@css:.definition@text")
        let client = StubHTTPClient(responses: ["https://dict.example.com/search?w=fixed": html])

        do {
            _ = try await DictLookupService.lookup(rule: rule, word: "word", httpClient: client)
            XCTFail("expected an error")
        } catch DictLookupError.emptyResult {
            // expected
        }
    }

    /// Real bug found comparing against Legado: `DictRule.search()` explicitly treats a blank
    /// `showRule` as "return the raw response body" -- this used to hand `""` straight to the rule
    /// engine instead, which had no matching fallback.
    func testBlankShowRuleReturnsRawResponseBody() async throws {
        let body = "纯文本释义，没有 HTML 结构"
        let rule = DictRule(name: "测试词典", urlRule: "https://dict.example.com/search?w=fixed", showRule: "")
        let client = StubHTTPClient(responses: ["https://dict.example.com/search?w=fixed": body])

        let result = try await DictLookupService.lookup(rule: rule, word: "书", httpClient: client)
        XCTAssertEqual(result, body)
    }

    func testWhitespaceOnlyShowRuleAlsoReturnsRawResponseBody() async throws {
        let body = "释义内容"
        let rule = DictRule(name: "测试词典", urlRule: "https://dict.example.com/search?w=fixed", showRule: "   ")
        let client = StubHTTPClient(responses: ["https://dict.example.com/search?w=fixed": body])

        let result = try await DictLookupService.lookup(rule: rule, word: "书", httpClient: client)
        XCTAssertEqual(result, body)
    }

    func testBlankShowRuleWithBlankResponseBodyThrowsEmptyResult() async throws {
        let rule = DictRule(name: "测试词典", urlRule: "https://dict.example.com/search?w=fixed", showRule: "")
        let client = StubHTTPClient(responses: ["https://dict.example.com/search?w=fixed": "   "])

        do {
            _ = try await DictLookupService.lookup(rule: rule, word: "书", httpClient: client)
            XCTFail("expected an error")
        } catch DictLookupError.emptyResult {
            // expected
        }
    }

    #if canImport(JavaScriptCore)
    func testKeyPlaceholderIsSubstitutedWithTheLookedUpWordOnApplePlatforms() async throws {
        let html = "<div class=\"definition\">a mythical bird</div>"
        let rule = DictRule(name: "测试词典", urlRule: "https://dict.example.com/search?w={{key}}", showRule: "@css:.definition@text")
        let client = StubHTTPClient(responses: ["https://dict.example.com/search?w=凤凰": html])

        let result = try await DictLookupService.lookup(rule: rule, word: "凤凰", httpClient: client)
        XCTAssertEqual(result, "a mythical bird")
    }
    #endif
}
