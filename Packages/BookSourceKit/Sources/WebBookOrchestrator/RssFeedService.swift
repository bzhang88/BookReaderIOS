import Foundation
import BookSourceModel
import NetworkClient

public enum RssFeedService {
    public static func fetchArticles(source: RssSource, httpClient: HTTPClient) async throws -> [RssArticle] {
        let response = try await httpClient.fetch(HTTPRequest(url: source.sourceUrl))
        return try RssFeedParser.parse(Data(response.body.utf8))
    }
}
