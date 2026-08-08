import XCTest
import BookSourceModel
@testable import WebBookOrchestrator

final class BookInfoServiceTests: XCTestCase {
    func testExtractsAllFieldsAndResolvesRelativeURLs() async throws {
        let html = """
        <html><body>
        <h1 class="title">My Great Novel</h1>
        <span class="author">Jane Doe</span>
        <div class="intro">A story about testing.</div>
        <span class="kind">Fantasy</span>
        <span class="last">Chapter 12</span>
        <img class="cover" src="/covers/42.jpg"/>
        <a class="toc-link" href="/book/42/toc">Table of Contents</a>
        </body></html>
        """
        var rule = BookInfoRule()
        rule.name = "@css:.title@text"
        rule.author = "@css:.author@text"
        rule.intro = "@css:.intro@text"
        rule.kind = "@css:.kind@text"
        rule.lastChapter = "@css:.last@text"
        rule.coverUrl = "@css:.cover@src"
        rule.tocUrl = "@css:.toc-link@href"

        let source = BookSource(bookSourceUrl: "https://example.com", bookSourceName: "Test", ruleBookInfo: rule)
        let client = StubHTTPClient(responses: ["https://example.com/book/42": html])

        let info = try await BookInfoService.fetchBookInfo(
            source: source, bookURL: "https://example.com/book/42", httpClient: client
        )

        XCTAssertEqual(info.name, "My Great Novel")
        XCTAssertEqual(info.author, "Jane Doe")
        XCTAssertEqual(info.intro, "A story about testing.")
        XCTAssertEqual(info.kind, "Fantasy")
        XCTAssertEqual(info.lastChapter, "Chapter 12")
        XCTAssertEqual(info.coverUrl, "https://example.com/covers/42.jpg")
        XCTAssertEqual(info.tocUrl, "https://example.com/book/42/toc")
    }

    func testMissingTocUrlRuleFallsBackToDetailPageURL() async throws {
        let html = "<html><body><h1 class=\"title\">Solo Page</h1></body></html>"
        var rule = BookInfoRule()
        rule.name = "@css:.title@text"
        let source = BookSource(bookSourceUrl: "https://example.com", bookSourceName: "Test", ruleBookInfo: rule)
        let client = StubHTTPClient(responses: ["https://example.com/book/1": html])

        let info = try await BookInfoService.fetchBookInfo(
            source: source, bookURL: "https://example.com/book/1", httpClient: client
        )
        XCTAssertEqual(info.tocUrl, "https://example.com/book/1")
    }

    func testInitRuleNarrowsExtractionRootBeforeFieldsRun() async throws {
        // The page has an unrelated "other" block before the real result card; without the
        // `init` narrowing, `.title` would ambiguously match across both.
        let html = """
        <div class="other"><h1 class="title">Wrong Book</h1></div>
        <div class="result"><h1 class="title">Right Book</h1></div>
        """
        var rule = BookInfoRule()
        rule.initRule = "@css:.result"
        rule.name = "@css:.title@text"
        let source = BookSource(bookSourceUrl: "https://example.com", bookSourceName: "Test", ruleBookInfo: rule)
        let client = StubHTTPClient(responses: ["https://example.com/book/1": html])

        let info = try await BookInfoService.fetchBookInfo(
            source: source, bookURL: "https://example.com/book/1", httpClient: client
        )
        XCTAssertEqual(info.name, "Right Book")
    }
}
