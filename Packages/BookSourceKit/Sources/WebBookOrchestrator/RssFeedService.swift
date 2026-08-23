import Foundation
import BookSourceModel
import NetworkClient

public enum RssFeedService {
    /// `url` defaults to `source.sourceUrl` -- pass a specific category URL (from
    /// `ExploreKindParser.parse(source.sortUrl ?? "")`) to fetch that category's feed instead of the
    /// source's own single default feed.
    public static func fetchArticles(source: RssSource, url: String? = nil, httpClient: HTTPClient) async throws -> [RssArticle] {
        let response = try await httpClient.fetch(HTTPRequest(url: url ?? source.sourceUrl))
        return try RssFeedParser.parse(Data(response.body.utf8))
    }
}
