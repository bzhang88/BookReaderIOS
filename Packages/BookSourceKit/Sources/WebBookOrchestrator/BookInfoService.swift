import Foundation
import BookSourceModel
import RuleEngine
import NetworkClient

/// Fetches and extracts a book's detail page, mirroring Legado's `BookInfo.analyzeBookInfo` flow.
public enum BookInfoService {
    public static func fetchBookInfo(
        source: BookSource,
        bookURL: String,
        httpClient: HTTPClient
    ) async throws -> BookInfo {
        let rule = source.ruleBookInfo ?? BookInfoRule()
        let response = try await httpClient.fetch(HTTPRequest(url: bookURL, headers: source.parsedHeaders()))
        var content = try RuleContent.parse(body: response.body, baseURL: response.finalURL)

        // A non-blank `init` rule narrows the extraction root before the rest of the fields run
        // (e.g. isolating a single result card out of a page that also has unrelated content).
        if let initRule = rule.initRule, !initRule.isEmpty {
            let items = try RuleEngine.extractItems(initRule, from: content)
            if let first = items.first { content = first }
        }

        func extract(_ ruleString: String?) throws -> String? {
            guard let ruleString, !ruleString.isEmpty else { return nil }
            let value = try RuleEngine.extractString(ruleString, from: content)
            return (value?.isEmpty ?? true) ? nil : value
        }

        let coverUrl = try extract(rule.coverUrl).map { URLResolver.resolve($0, against: response.finalURL) }
        let rawTocUrl = try extract(rule.tocUrl)
        let tocUrl = rawTocUrl.map { URLResolver.resolve($0, against: response.finalURL) } ?? response.finalURL

        return BookInfo(
            name: try extract(rule.name),
            author: try extract(rule.author),
            intro: try extract(rule.intro),
            kind: try extract(rule.kind),
            lastChapter: try extract(rule.lastChapter),
            updateTime: try extract(rule.updateTime),
            coverUrl: coverUrl,
            tocUrl: tocUrl,
            wordCount: try extract(rule.wordCount)
        )
    }
}
