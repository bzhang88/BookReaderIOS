import XCTest
import BookSourceModel
@testable import WebBookOrchestrator

final class RssFeedServiceTests: XCTestCase {
    private let feedXML = """
    <rss><channel><item><title>Article One</title><link>https://a.com/article/1</link></item></channel></rss>
    """

    func testFetchesFromSourceURLByDefault() async throws {
        let source = RssSource(sourceUrl: "https://a.com/feed", sourceName: "A")
        let client = StubHTTPClient(responses: ["https://a.com/feed": feedXML])
        let articles = try await RssFeedService.fetchArticles(source: source, httpClient: client)
        XCTAssertEqual(articles.map(\.title), ["Article One"])
    }

    /// Real gap this fixes: a source with multiple category feeds (`sortUrl`, parsed the same way
    /// `BookSource.exploreUrl` is) needs a way to fetch a *different* URL than the source's own
    /// default `sourceUrl` -- this is what lets `RssArticleListView`'s category chip row actually
    /// switch feeds.
    func testFetchesFromExplicitURLWhenProvided() async throws {
        let source = RssSource(sourceUrl: "https://a.com/feed", sourceName: "A", sortUrl: "科技::https://a.com/tech")
        let client = StubHTTPClient(responses: [
            "https://a.com/feed": feedXML,
            "https://a.com/tech": """
            <rss><channel><item><title>Tech Article</title><link>https://a.com/article/2</link></item></channel></rss>
            """
        ])
        let articles = try await RssFeedService.fetchArticles(source: source, url: "https://a.com/tech", httpClient: client)
        XCTAssertEqual(articles.map(\.title), ["Tech Article"])
    }
}
