import XCTest
@testable import BookSourceModel

final class BookSourceDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> BookSource {
        try JSONDecoder().decode(BookSource.self, from: Data(json.utf8))
    }

    func testDecodesRealisticSourceShapeWithObjectRules() throws {
        let json = """
        {
            "bookSourceUrl": "https://www.example.com",
            "bookSourceName": "示例源",
            "bookSourceGroup": "CSS; 正则",
            "bookSourceType": 0,
            "searchUrl": "/search?q={{key}}&page={{page}}",
            "ruleSearch": {
                "bookList": "@css:li.clearfix",
                "name": "@css:.name@text",
                "bookUrl": "@css:.name>a@href"
            },
            "ruleToc": {
                "chapterList": "-:<li><a[^\\"]+\\"([^\\"]*)\\">([^<]*)",
                "chapterName": "$2",
                "chapterUrl": "$1"
            }
        }
        """
        let source = try decode(json)
        XCTAssertEqual(source.bookSourceUrl, "https://www.example.com")
        XCTAssertEqual(source.bookSourceName, "示例源")
        XCTAssertTrue(source.isTextSource)
        XCTAssertEqual(source.ruleSearch?.bookList, "@css:li.clearfix")
        XCTAssertEqual(source.ruleSearch?.name, "@css:.name@text")
        XCTAssertEqual(source.ruleToc?.chapterName, "$2")
    }

    func testMissingOptionalFieldsDefaultSensibly() throws {
        let json = #"{"bookSourceUrl": "https://x.com", "bookSourceName": "X"}"#
        let source = try decode(json)
        XCTAssertEqual(source.bookSourceType, 0)
        XCTAssertTrue(source.enabled)
        XCTAssertTrue(source.enabledExplore)
        XCTAssertNil(source.ruleSearch)
    }

    // MARK: - Three-layer leniency on rule sub-objects

    func testSearchRuleDecodesAsPlainObject() throws {
        let json = #"{"bookList": "@css:li", "name": "@css:.n@text"}"#
        let rule = try JSONDecoder().decode(SearchRule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.bookList, "@css:li")
        XCTAssertEqual(rule.name, "@css:.n@text")
    }

    func testSearchRuleDecodesFromDoublyEncodedJSONString() throws {
        // Some real-world exporters wrap the sub-object as an escaped JSON string.
        let inner = #"{"bookList": "@css:li", "name": "@css:.n@text"}"#
        let json = try JSONEncoder().encode(inner) // produces a bare JSON string literal
        let rule = try JSONDecoder().decode(SearchRule.self, from: json)
        XCTAssertEqual(rule.bookList, "@css:li")
        XCTAssertEqual(rule.name, "@css:.n@text")
    }

    func testSearchRuleDecodesFromBareStringFallsBackToPrimaryField() throws {
        let json = #""@css:li.book""#
        let rule = try JSONDecoder().decode(SearchRule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.bookList, "@css:li.book")
        XCTAssertNil(rule.name)
    }

    func testTocRuleBareStringFallsBackToChapterList() throws {
        let json = #""@css:li.chapter""#
        let rule = try JSONDecoder().decode(TocRule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.chapterList, "@css:li.chapter")
    }

    func testContentRuleBareStringFallsBackToContent() throws {
        let json = #""@css:.content""#
        let rule = try JSONDecoder().decode(ContentRule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.content, "@css:.content")
    }

    func testBookInfoRuleUsesInitJSONKeyNotBookInfoInit() throws {
        let json = #"{"init": "@css:#wrapper", "name": "@css:.title@text"}"#
        let rule = try JSONDecoder().decode(BookInfoRule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.initRule, "@css:#wrapper")
        XCTAssertEqual(rule.name, "@css:.title@text")
    }

    // MARK: - Header parsing

    func testParsedHeadersFromValidJSON() throws {
        let json = #"{"bookSourceUrl": "https://x.com", "bookSourceName": "X", "header": "{\"User-Agent\": \"Mozilla/5.0\"}"}"#
        let source = try decode(json)
        XCTAssertEqual(source.parsedHeaders(), ["User-Agent": "Mozilla/5.0"])
    }

    func testParsedHeadersDegradeToJustDefaultOnMalformedJSON() throws {
        let json = #"{"bookSourceUrl": "https://x.com", "bookSourceName": "X", "header": "not json"}"#
        let source = try decode(json)
        XCTAssertEqual(source.parsedHeaders(), ["User-Agent": BookSource.defaultUserAgent])
    }

    func testParsedHeadersDefaultsToJustUserAgentWhenMissing() throws {
        let json = #"{"bookSourceUrl": "https://x.com", "bookSourceName": "X"}"#
        let source = try decode(json)
        XCTAssertEqual(source.parsedHeaders(), ["User-Agent": BookSource.defaultUserAgent])
    }

    func testParsedHeadersDefaultUserAgentOverridableBySource() throws {
        let json = #"{"bookSourceUrl": "https://x.com", "bookSourceName": "X", "header": "{\"User-Agent\": \"CustomBot/1.0\"}"}"#
        let source = try decode(json)
        XCTAssertEqual(source.parsedHeaders(), ["User-Agent": "CustomBot/1.0"])
    }

    func testBookInfoRuleBareStringFallsBackToName() throws {
        // Matches Legado's real (slightly odd) fallback for this one rule type.
        let json = #""@css:.title@text""#
        let rule = try JSONDecoder().decode(BookInfoRule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.name, "@css:.title@text")
        XCTAssertNil(rule.initRule)
    }
}
