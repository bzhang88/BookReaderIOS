import XCTest
@testable import RuleEngine

final class RuleStringParserTests: XCTestCase {
    func testDefaultChainNoPrefix() throws {
        let parsed = try RuleStringParser.parse("class.name@text")
        XCTAssertEqual(parsed.mode, .defaultChain)
        XCTAssertEqual(parsed.selector, "class.name@text")
        XCTAssertNil(parsed.regexSuffix)
    }

    func testCssSinglePrefix() throws {
        let parsed = try RuleStringParser.parse("@css:.name@text")
        XCTAssertEqual(parsed.mode, .cssSingle)
        XCTAssertEqual(parsed.selector, ".name@text")
    }

    func testExplicitDefaultEscape() throws {
        let parsed = try RuleStringParser.parse("@@class.name@text")
        XCTAssertEqual(parsed.mode, .defaultChain)
        XCTAssertEqual(parsed.selector, "class.name@text")
    }

    func testXPathPrefix() throws {
        let parsed = try RuleStringParser.parse("@XPath://div[@id='x']")
        XCTAssertEqual(parsed.mode, .xpath)
    }

    func testLeadingSlashIsXPath() throws {
        let parsed = try RuleStringParser.parse("//*[@id=\"content\"]")
        XCTAssertEqual(parsed.mode, .xpath)
    }

    func testJsonDollarPrefix() throws {
        let parsed = try RuleStringParser.parse("$.data.list")
        XCTAssertEqual(parsed.mode, .json)
    }

    func testJsonPrefix() throws {
        let parsed = try RuleStringParser.parse("@Json:$.data")
        XCTAssertEqual(parsed.mode, .json)
        XCTAssertEqual(parsed.selector, "$.data")
    }

    func testRegexSuffixStrippedBeforeModeDetection() throws {
        let parsed = try RuleStringParser.parse("@css:.content@textNodes##ad.*##")
        XCTAssertEqual(parsed.mode, .cssSingle)
        XCTAssertEqual(parsed.selector, ".content@textNodes")
        XCTAssertEqual(parsed.regexSuffix?.pattern, "ad.*")
    }

    func testAllInOneColonPrefixDetected() throws {
        let parsed = try RuleStringParser.parse(":<li>(.*?)</li>")
        XCTAssertEqual(parsed.mode, .allInOneRegex)
        XCTAssertEqual(parsed.selector, "<li>(.*?)</li>")
    }

    func testBareRegexRowReferenceDetected() throws {
        let parsed = try RuleStringParser.parse("$2")
        XCTAssertEqual(parsed.mode, .regexTemplate)
        XCTAssertEqual(parsed.selector, "$2")
    }

    func testEmbeddedRegexRowReferenceInTemplateTextDetected() throws {
        let parsed = try RuleStringParser.parse("prefix-$1-suffix")
        XCTAssertEqual(parsed.mode, .regexTemplate)
    }

    func testWebJsThrowsUnsupported() {
        XCTAssertThrowsError(try RuleStringParser.parse("@webjs:document.title")) { error in
            XCTAssertEqual(error as? RuleEngineError, .unsupportedFeature(.webJs))
        }
    }

    func testEmbeddedJsThrowsNotYetImplemented() {
        XCTAssertThrowsError(try RuleStringParser.parse("class.name@text{{result.trim()}}")) { error in
            guard case .notYetImplemented = error as? RuleEngineError else {
                return XCTFail("expected .notYetImplemented, got \(error)")
            }
        }
    }

    func testEmbeddedJSONPathSubstitutionThrowsNotYetImplemented() {
        // Real-world rule from Legado's docs: ruleSearch.bookUrl = "/book/detail?id={$._id}"
        XCTAssertThrowsError(try RuleStringParser.parse("/book/detail?id={$._id}")) { error in
            guard case .notYetImplemented = error as? RuleEngineError else {
                return XCTFail("expected .notYetImplemented, got \(error)")
            }
        }
    }

    func testJsPipelineThrowsNotYetImplemented() {
        XCTAssertThrowsError(try RuleStringParser.parse("$.id@js:java.put('id', result);result")) { error in
            guard case .notYetImplemented = error as? RuleEngineError else {
                return XCTFail("expected .notYetImplemented, got \(error)")
            }
        }
    }
}
