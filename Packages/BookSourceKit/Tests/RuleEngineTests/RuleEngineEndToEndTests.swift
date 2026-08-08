import XCTest
import SwiftSoup
@testable import RuleEngine

final class RuleEngineEndToEndTests: XCTestCase {
    private func root(_ html: String) throws -> RuleContent {
        let document = try SwiftSoup.parse(html)
        let elements = Elements()
        elements.add(document)
        return .html(elements)
    }

    private func htmlElements(_ content: RuleContent) -> Elements {
        guard case .html(let elements) = content else {
            XCTFail("expected .html content")
            return Elements()
        }
        return elements
    }

    // MARK: - Default dot-chain mode (Legado's own canonical example)

    func testDefaultChainClassTagIndexAndKeyword() throws {
        let html = """
        <table>
        <tr class="odd"><td><a href="/x1">First</a><a href="/x2">Second</a></td></tr>
        <tr class="even"><td><a href="/y1">Ignored</a></td></tr>
        <tr class="odd"><td><a href="/x3">Third</a></td></tr>
        </table>
        """
        let rootElements = htmlElements(try root(html))
        // "elements with class=odd, index 0, then their <a> children, index 0, then .text()"
        let result = try CSSChainEvaluator.extractStrings(chain: "class.odd.0@tag.a.0@text", root: rootElements)
        XCTAssertEqual(result, ["First"])
    }

    // MARK: - @css: single-selector mode, mirroring a real ruleSearch block

    // jsoup's `:eq(n)` matches on an element's index among ALL its siblings (not "nth match of
    // the tag selector"), so the intended <p> is placed at overall sibling index 2 here
    // (after the .name div at 0 and the img at 1) for `p:eq(2)` to land on it.
    private let searchResultsHTML = """
    <html><body>
    <div id="results">
      <li class="clearfix">
        <div class="name"><a href="/book/1">Book One</a></div>
        <img src="/covers/1.jpg"/>
        <p><a href="/author/1">Author One</a></p>
        <p>Latest: Chapter 5</p>
      </li>
      <li class="clearfix">
        <div class="name"><a href="/book/2">Book Two</a></div>
        <img src="/covers/2.jpg"/>
        <p><a href="/author/2">Author Two</a></p>
        <p>Latest: Chapter 9</p>
      </li>
    </div>
    </body></html>
    """

    func testBookListElementExtraction() throws {
        let items = try RuleEngine.extractItems("@css:li.clearfix", from: root(searchResultsHTML))
        XCTAssertEqual(items.count, 2)
    }

    func testPerItemFieldExtractionMatchesRealSourceRules() throws {
        let items = try RuleEngine.extractItems("@css:li.clearfix", from: root(searchResultsHTML))
        XCTAssertEqual(items.count, 2)

        XCTAssertEqual(try RuleEngine.extractString("@css:.name@text", from: items[0]), "Book One")
        XCTAssertEqual(try RuleEngine.extractString("@css:.name>a@href", from: items[0]), "/book/1")
        XCTAssertEqual(try RuleEngine.extractString("@css:img@src", from: items[0]), "/covers/1.jpg")
        // p:eq(2) matches the <p> whose overall sibling index is 2 (after .name div, img).
        XCTAssertEqual(try RuleEngine.extractString("@css:p:eq(2)>a@text", from: items[0]), "Author One")

        XCTAssertEqual(try RuleEngine.extractString("@css:.name@text", from: items[1]), "Book Two")
        XCTAssertEqual(try RuleEngine.extractString("@css:p:eq(2)>a@text", from: items[1]), "Author Two")
    }

    // MARK: - textNodes + regex purify suffix, mirroring a real ruleContent.content rule

    func testContentTextNodesWithRegexPurify() throws {
        let html = """
        <div class="chapter-content">
        <p>This is the first line of the chapter.[AD]</p>
        <p>This is the second line.[AD]</p>
        </div>
        """
        let result = try RuleEngine.extractStringList(
            "@css:.chapter-content p@textNodes##\\[AD\\]##", from: root(html)
        )
        XCTAssertEqual(result, [
            "This is the first line of the chapter.",
            "This is the second line."
        ])
    }

    // MARK: - Combinators end-to-end

    func testFirstNonEmptyCombinatorFallsThroughToSecondBranch() throws {
        let html = "<div><p class=\"b\">fallback text</p></div>"
        let result = try RuleEngine.extractStringList("class.a@text||class.b@text", from: root(html))
        XCTAssertEqual(result, ["fallback text"])
    }

    func testConcatCombinatorJoinsBothBranches() throws {
        let html = "<div><p class=\"a\">alpha</p><p class=\"b\">beta</p></div>"
        let result = try RuleEngine.extractStringList("class.a@text&&class.b@text", from: root(html))
        XCTAssertEqual(result, ["alpha", "beta"])
    }

    // MARK: - Attribute extraction (default keyword fallback)

    func testAttributeKeywordExtraction() throws {
        let html = "<div><a class=\"link\" href=\"/target\">go</a></div>"
        let result = try RuleEngine.extractString("class.link@href", from: root(html))
        XCTAssertEqual(result, "/target")
    }
}
