import Foundation
import BookSourceModel
import RuleEngine
import NetworkClient

public enum DictLookupError: Error, Equatable {
    case emptyResult
}

/// Looks a word up against one `DictRule` -- shares `SearchURLBuilder`'s `{{key}}`-templated-URL
/// construction (a dict rule's `urlRule` uses the exact same templating convention as a book
/// source's `searchUrl`) and `RuleEngine`'s extraction (`showRule` is the same DSL as any other
/// rule field), rather than building a second URL-templating/extraction implementation for what's
/// structurally the same problem.
public enum DictLookupService {
    public static func lookup(rule: DictRule, word: String, httpClient: any HTTPClient) async throws -> String {
        let built = try SearchURLBuilder.build(
            searchUrl: rule.urlRule, keyword: word, page: 1, baseHeaders: [:], resolveAgainst: rule.urlRule
        )
        let response = try await httpClient.fetch(HTTPRequest(
            url: built.url, method: built.method, headers: built.headers,
            body: built.body?.data(using: .utf8)
        ))
        // Real bug found comparing against Legado: a blank `showRule` is a real, documented shape --
        // Legado's own `DictRule.search()` explicitly treats it as "use the raw response body"
        // (`if (showRule.isBlank()) return body!!`) -- but this used to unconditionally hand `""` to
        // `RuleEngine.extractString`, which had no matching fallback branch.
        let trimmedShowRule = rule.showRule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedShowRule.isEmpty else {
            let trimmedBody = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBody.isEmpty else { throw DictLookupError.emptyResult }
            return trimmedBody
        }
        let content = try RuleContent.parse(body: response.body, baseURL: response.finalURL)
        guard let result = try RuleEngine.extractString(rule.showRule, from: content),
              !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DictLookupError.emptyResult
        }
        return result
    }
}
