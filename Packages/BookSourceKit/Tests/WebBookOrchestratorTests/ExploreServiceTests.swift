import XCTest
import BookSourceModel
@testable import WebBookOrchestrator

final class ExploreServiceTests: XCTestCase {
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
        var rule = ExploreRule()
        rule.bookList = "@css:.item"
        rule.name = "@css:.name@text"
        rule.author = "@css:.author@text"
        rule.bookUrl = "@css:.name@href"
        rule.coverUrl = "@css:.cover@src"

        let source = BookSource(bookSourceUrl: "https://example.com", bookSourceName: "Test Source", ruleExplore: rule)
        let client = StubHTTPClient(responses: ["https://example.com/explore/fantasy": html])

        let results = try await ExploreService.fetchExploreList(
            source: source, exploreURL: "https://example.com/explore/fantasy", httpClient: client
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].name, "Novel One")
        XCTAssertEqual(results[0].author, "Author A")
        XCTAssertEqual(results[0].bookUrl, "https://example.com/book/1")
        XCTAssertEqual(results[0].coverUrl, "https://example.com/covers/1.jpg")
    }

    func testEmptyBookListRuleReturnsEmptyWithoutFetching() async throws {
        let source = BookSource(bookSourceUrl: "https://example.com", bookSourceName: "Test Source", ruleExplore: ExploreRule())
        let client = StubHTTPClient(responses: [:])
        let results = try await ExploreService.fetchExploreList(
            source: source, exploreURL: "https://example.com/explore", httpClient: client
        )
        XCTAssertTrue(results.isEmpty)
    }

    // {{page}} substitution always goes through JSRuntime (JavaScriptCore), unavailable on this
    // Windows dev machine -- same platform gate SearchURLBuilderTests uses for its own {{...}}
    // tests. A literal query string with no {{ }} (tested elsewhere in this file) never touches
    // JSRuntime, so plain explore URLs are still fully testable everywhere.
    #if canImport(JavaScriptCore)
    func testSupportsPageTemplateSubstitution() async throws {
        var rule = ExploreRule()
        rule.bookList = "@css:.item"
        rule.name = "@css:.name@text"
        rule.bookUrl = "@css:.name@href"
        let source = BookSource(bookSourceUrl: "https://example.com", bookSourceName: "Test Source", ruleExplore: rule)
        let html = """
        <ul><li class="item"><a class="name" href="/book/9">Page Two Book</a></li></ul>
        """
        let client = StubHTTPClient(responses: ["https://example.com/explore?page=2": html])

        let results = try await ExploreService.fetchExploreList(
            source: source, exploreURL: "https://example.com/explore?page={{page}}", page: 2, httpClient: client
        )
        XCTAssertEqual(results.map(\.name), ["Page Two Book"])
    }
    #endif

    func testReversedBookListPrefixReversesResultOrder() async throws {
        var rule = ExploreRule()
        rule.bookList = "-@css:.item"
        rule.name = "@css:.name@text"
        rule.bookUrl = "@css:.name@href"
        let source = BookSource(bookSourceUrl: "https://example.com", bookSourceName: "Test Source", ruleExplore: rule)
        let html = """
        <ul>
          <li class="item"><a class="name" href="/book/1">First</a></li>
          <li class="item"><a class="name" href="/book/2">Second</a></li>
        </ul>
        """
        let client = StubHTTPClient(responses: ["https://example.com/explore": html])

        let results = try await ExploreService.fetchExploreList(
            source: source, exploreURL: "https://example.com/explore", httpClient: client
        )
        XCTAssertEqual(results.map(\.name), ["Second", "First"])
    }
}
