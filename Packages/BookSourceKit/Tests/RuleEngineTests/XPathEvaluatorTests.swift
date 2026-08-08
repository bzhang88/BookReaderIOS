import XCTest
import SwiftSoup
@testable import RuleEngine

final class XPathEvaluatorTests: XCTestCase {
    private func root(_ html: String) throws -> Elements {
        let document = try SwiftSoup.parse(html)
        let elements = Elements()
        elements.add(document)
        return elements
    }

    // MARK: - Real-world patterns, verbatim from legado-with-MD3/docs/dev/examples.md (Example 2)

    func testMetaTagAttributeExtraction() throws {
        // "//*[@property=\"og:novel:author\"]/@content"
        let html = """
        <html><head>
        <meta property="og:novel:author" content="Author Name">
        <meta property="og:image" content="/cover.jpg">
        </head><body></body></html>
        """
        let result = try XPathEvaluator.extractStrings(
            "//*[@property=\"og:novel:author\"]/@content", root: root(html)
        )
        XCTAssertEqual(result, ["Author Name"])
    }

    func testDescendantThenIndexedChildThenTextChain() throws {
        // "//*[@id=\"latest-chapter\"]//li[1]/a/text()"
        let html = """
        <div id="latest-chapter">
          <ul>
            <li><a href="/c/99">Chapter 99</a></li>
            <li><a href="/c/98">Chapter 98</a></li>
          </ul>
        </div>
        """
        let result = try XPathEvaluator.extractStrings(
            "//*[@id=\"latest-chapter\"]//li[1]/a/text()", root: root(html)
        )
        XCTAssertEqual(result, ["Chapter 99"])
    }

    func testTextEqualsPredicateThenAttribute() throws {
        // "//a[text()=\"阅读\"]/@href"
        let html = """
        <body>
        <a href="/toc/123">阅读</a>
        <a href="/other">Other Link</a>
        </body>
        """
        let result = try XPathEvaluator.extractStrings("//a[text()=\"阅读\"]/@href", root: root(html))
        XCTAssertEqual(result, ["/toc/123"])
    }

    func testWildcardIdPredicateDefaultsToTextWhenNoTerminalKeyword() throws {
        // "//*[@id=\"content\"]" (ruleContent.content, no explicit @attr/text() suffix)
        let html = "<div id=\"content\"><p>Chapter text here.</p></div>"
        let result = try XPathEvaluator.extractStrings("//*[@id=\"content\"]", root: root(html))
        XCTAssertEqual(result, ["Chapter text here."])
    }

    func testIndexedPredicateThenText() throws {
        // "//dd[2]/text()"
        let html = "<dl><dt>Title</dt><dd>skip me</dd><dd>Author Name</dd></dl>"
        let result = try XPathEvaluator.extractStrings("//dd[2]/text()", root: root(html))
        XCTAssertEqual(result, ["Author Name"])
    }

    func testChildAxisDoesNotDescendPastImmediateChildren() throws {
        // "//*[@id=\"search-result\"]/dl" -- child axis, not descendant
        let html = """
        <div id="search-result">
          <dl><dt>Book 1</dt></dl>
          <dl><dt>Book 2</dt></dl>
          <div><dl><dt>Nested, should not match</dt></dl></div>
        </div>
        """
        let items = try XPathEvaluator.extractElements(
            "//*[@id=\"search-result\"]/dl", root: root(html)
        )
        XCTAssertEqual(items.array().count, 2)
    }

    func testDescendantTagThenChildTagThenAttribute() throws {
        // "//dt/a/@href"
        let html = "<dl><dt><a href=\"/book/1\">Book Title</a></dt></dl>"
        let result = try XPathEvaluator.extractStrings("//dt/a/@href", root: root(html))
        XCTAssertEqual(result, ["/book/1"])
    }

    func testSimpleDescendantTagAttribute() throws {
        // "//img/@src"
        let html = "<div><p>text</p><img src=\"/cover1.jpg\"/></div>"
        let result = try XPathEvaluator.extractStrings("//img/@src", root: root(html))
        XCTAssertEqual(result, ["/cover1.jpg"])
    }

    func testPositionGreaterThanPredicate() throws {
        // "//*[@id=\"chapter-list\"]/*[position()>1]/@value"
        let html = """
        <select id="chapter-list">
          <option value="0">Page 1 (self, skip)</option>
          <option value="1">Page 2</option>
          <option value="2">Page 3</option>
        </select>
        """
        let result = try XPathEvaluator.extractStrings(
            "//*[@id=\"chapter-list\"]/*[position()>1]/@value", root: root(html)
        )
        XCTAssertEqual(result, ["1", "2"])
    }

    // MARK: - Additional predicate coverage

    func testLastPredicate() throws {
        let html = "<ul><li>A</li><li>B</li><li>C</li></ul>"
        let result = try XPathEvaluator.extractStrings("//li[last()]/text()", root: root(html))
        XCTAssertEqual(result, ["C"])
    }

    func testPositionLessThanPredicate() throws {
        let html = "<ul><li>A</li><li>B</li><li>C</li></ul>"
        let result = try XPathEvaluator.extractStrings("//li[position()<3]/text()", root: root(html))
        XCTAssertEqual(result, ["A", "B"])
    }

    func testAttributeExistsPredicateWithoutValue() throws {
        let html = "<div><a href=\"/a\">A</a><a>B (no href)</a></div>"
        let result = try XPathEvaluator.extractStrings("//a[@href]/text()", root: root(html))
        XCTAssertEqual(result, ["A"])
    }

    func testWildcardChildSelectsAllChildren() throws {
        let html = "<div id=\"x\"><p>one</p><span>two</span></div>"
        let items = try XPathEvaluator.extractElements("//*[@id=\"x\"]/*", root: root(html))
        XCTAssertEqual(items.array().count, 2)
    }

    // MARK: - following-sibling:: axis (confirmed real usage: multiple real sources' chapterList
    // rules use "//*[@id=\"list\"]//dt[2]/following-sibling::dd/a" -- found via a smoke test over
    // 189 real downloaded book sources, not invented)

    func testFollowingSiblingAxisSelectsAllLaterSiblingsNotJustTheNext() throws {
        let html = """
        <div id="list">
          <dt>Header 1</dt>
          <dd><a href="/c/1">Ignored (before dt[2])</a></dd>
          <dt>Header 2</dt>
          <dd><a href="/c/2">Chapter A</a></dd>
          <dd><a href="/c/3">Chapter B</a></dd>
        </div>
        """
        let items = try XPathEvaluator.extractElements(
            "//*[@id=\"list\"]//dt[2]/following-sibling::dd/a", root: root(html)
        )
        XCTAssertEqual(items.array().count, 2)

        let hrefs = try XPathEvaluator.extractStrings(
            "//*[@id=\"list\"]//dt[2]/following-sibling::dd/a/@href", root: root(html)
        )
        XCTAssertEqual(hrefs, ["/c/2", "/c/3"])
    }

    func testFollowingSiblingAxisWithWildcardNodeTest() throws {
        let html = "<div><p>first</p><span>a</span><span>b</span></div>"
        let items = try XPathEvaluator.extractElements("//p/following-sibling::*", root: root(html))
        XCTAssertEqual(items.array().count, 2)
    }

    // MARK: - Unsupported syntax fails loudly rather than mis-selecting

    func testUnsupportedPredicateFunctionThrows() {
        XCTAssertThrowsError(
            try XPathEvaluator.extractStrings("//a[contains(@href,\"x\")]/text()", root: Elements())
        ) { error in
            guard case .notYetImplemented = error as? RuleEngineError else {
                return XCTFail("expected .notYetImplemented, got \(error)")
            }
        }
    }

    func testAttributeOrTextInMiddleOfPathThrows() {
        // @attr/text() must be the terminal step -- using it mid-path is not a thing we support.
        XCTAssertThrowsError(
            try XPathEvaluator.extractStrings("//a/@href/text()", root: Elements())
        ) { error in
            guard case .notYetImplemented = error as? RuleEngineError else {
                return XCTFail("expected .notYetImplemented, got \(error)")
            }
        }
    }

    // MARK: - Wired through the real RuleEngine facade (mode detection + evaluation together)

    func testEndToEndThroughRuleEngineFacade() throws {
        let html = "<html><body><div id=\"content\"><p>Real chapter text.</p></div></body></html>"
        let document = try SwiftSoup.parse(html)
        let elements = Elements()
        elements.add(document)

        let result = try RuleEngine.extractString("//*[@id=\"content\"]", from: .html(elements))
        XCTAssertEqual(result, "Real chapter text.")
    }

    func testLeadingSlashModeDetectionRoutesToXPath() throws {
        let html = "<div class=\"x\"><a href=\"/y\">link</a></div>"
        let result = try RuleEngine.extractString("//a/@href", from: .html(try root(html)))
        XCTAssertEqual(result, "/y")
    }
}
