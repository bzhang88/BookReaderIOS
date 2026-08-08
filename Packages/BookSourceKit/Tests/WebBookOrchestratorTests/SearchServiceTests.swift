import XCTest
import BookSourceModel
@testable import WebBookOrchestrator

final class SearchServiceTests: XCTestCase {
    func testExtractsResultsAndResolvesRelativeURLs() async throws {
        let html = """
        <html><body>
        <ul class="results">
          <li class="item">
            <a class="name" href="/book/1">Novel One</a>
            <span class="author">Author A</span>
            <img class="cover" src="/covers/1.jpg"/>
          </li>
          <li class="item">
            <a class="name" href="/book/2">Novel Two</a>
            <span class="author">Author B</span>
            <img class="cover" src="/covers/2.jpg"/>
          </li>
        </ul>
        </body></html>
        """
        var rule = SearchRule()
        rule.bookList = "@css:.item"
        rule.name = "@css:.name@text"
        rule.author = "@css:.author@text"
        rule.bookUrl = "@css:.name@href"
        rule.coverUrl = "@css:.cover@src"

        let source = BookSource(
            bookSourceUrl: "https://example.com", bookSourceName: "Test Source",
            searchUrl: "https://example.com/search?wd=fixed", ruleSearch: rule
        )
        let client = StubHTTPClient(responses: ["https://example.com/search?wd=fixed": html])

        let results = try await SearchService.search(source: source, keyword: "novel", httpClient: client)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].name, "Novel One")
        XCTAssertEqual(results[0].author, "Author A")
        XCTAssertEqual(results[0].bookUrl, "https://example.com/book/1")
        XCTAssertEqual(results[0].coverUrl, "https://example.com/covers/1.jpg")
        XCTAssertEqual(results[0].bookSourceName, "Test Source")
        XCTAssertEqual(results[1].name, "Novel Two")
    }

    func testMissingBookUrlSkipsThatResultRatherThanFailingWholeSearch() async throws {
        let html = """
        <ul class="results">
          <li class="item"><a class="name" href="/book/1">Has URL</a></li>
          <li class="item"><span class="name">No URL Here</span></li>
        </ul>
        """
        var rule = SearchRule()
        rule.bookList = "@css:.item"
        rule.name = "@css:.name@text"
        rule.bookUrl = "@css:.name@href"

        let source = BookSource(
            bookSourceUrl: "https://example.com", bookSourceName: "Test",
            searchUrl: "https://example.com/search?wd=fixed", ruleSearch: rule
        )
        let client = StubHTTPClient(responses: ["https://example.com/search?wd=fixed": html])

        let results = try await SearchService.search(source: source, keyword: "novel", httpClient: client)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Has URL")
    }

    func testEmptyBookListRuleReturnsNoResultsWithoutFetching() async throws {
        let source = BookSource(
            bookSourceUrl: "https://example.com", bookSourceName: "Test",
            searchUrl: "https://example.com/search?wd=fixed", ruleSearch: SearchRule()
        )
        let client = StubHTTPClient(responses: [:])
        let results = try await SearchService.search(source: source, keyword: "novel", httpClient: client)
        XCTAssertTrue(results.isEmpty)
    }

    func testMissingSearchUrlReturnsNoResultsWithoutFetching() async throws {
        let source = BookSource(bookSourceUrl: "https://example.com", bookSourceName: "Test")
        let client = StubHTTPClient(responses: [:])
        let results = try await SearchService.search(source: source, keyword: "novel", httpClient: client)
        XCTAssertTrue(results.isEmpty)
    }
}
