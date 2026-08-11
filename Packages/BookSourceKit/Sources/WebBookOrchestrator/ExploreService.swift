import Foundation
import BookSourceModel
import RuleEngine
import NetworkClient

/// Fetches and extracts one "发现"/discover category page -- same rule-extraction pipeline as
/// `SearchService`, just driven by `ExploreRule`/an explore-category URL instead of a search
/// keyword. Reuses `SearchURLBuilder` for `{{page}}` template substitution: explore URLs use the
/// exact same `{{...}}`-plus-optional-POST-JSON-suffix convention search URLs do, just without a
/// real `{{key}}` value (passed as an empty string, which is harmless for URLs that don't
/// reference it and matches how real explore URLs are written).
public enum ExploreService {
    public static func fetchExploreList(
        source: BookSource, exploreURL: String, page: Int = 1, httpClient: HTTPClient
    ) async throws -> [SearchResult] {
        let rule = source.ruleExplore ?? ExploreRule()
        let (bookListRule, reversed) = ListRulePrefix.strip(rule.bookList ?? "")
        guard !bookListRule.isEmpty else { return [] }

        let built = try SearchURLBuilder.build(
            searchUrl: exploreURL, keyword: "", page: page, baseHeaders: source.parsedHeaders(),
            resolveAgainst: source.bookSourceUrl
        )
        let response = try await httpClient.fetch(HTTPRequest(
            url: built.url, method: built.method, headers: built.headers,
            body: built.body?.data(using: .utf8)
        ))
        let content = try RuleContent.parse(body: response.body, baseURL: response.finalURL)
        let items = try RuleEngine.extractItems(bookListRule, from: content)

        func extract(_ ruleString: String?, from item: RuleContent) throws -> String? {
            guard let ruleString, !ruleString.isEmpty else { return nil }
            let value = try RuleEngine.extractString(ruleString, from: item)
            return (value?.isEmpty ?? true) ? nil : value
        }

        var results: [SearchResult] = []
        for item in items {
            guard let rawBookUrl = try extract(rule.bookUrl, from: item) else { continue }
            let bookUrl = URLResolver.resolve(rawBookUrl, against: response.finalURL)
            let coverUrl = try extract(rule.coverUrl, from: item).map {
                URLResolver.resolve($0, against: response.finalURL)
            }
            results.append(SearchResult(
                bookSourceUrl: source.bookSourceUrl,
                bookSourceName: source.bookSourceName,
                name: try extract(rule.name, from: item) ?? "",
                author: try extract(rule.author, from: item),
                intro: try extract(rule.intro, from: item),
                kind: try extract(rule.kind, from: item),
                lastChapter: try extract(rule.lastChapter, from: item),
                updateTime: try extract(rule.updateTime, from: item),
                bookUrl: bookUrl,
                coverUrl: coverUrl,
                wordCount: try extract(rule.wordCount, from: item)
            ))
        }
        if reversed { results.reverse() }
        return results
    }
}
