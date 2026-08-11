import Foundation

/// A user-editable web search engine for the reader's "划词搜索" panel -- confirmed against
/// Legado_Max's real `ReadWebSearchPanel.kt` that this is Bing/Baidu built in plus user-added
/// custom engines, not a book-source-style rule DSL. `urlTemplate` is a plain string with a
/// `{{query}}` placeholder, substituted with a percent-encoded query -- no JS evaluation needed
/// (unlike book sources' `{{ }}`), since this is just a URL, not a scraping rule.
public struct WebSearchEngine: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var urlTemplate: String

    public init(id: String = UUID().uuidString, name: String, urlTemplate: String) {
        self.id = id
        self.name = name
        self.urlTemplate = urlTemplate
    }

    public static let defaults: [WebSearchEngine] = [
        WebSearchEngine(id: "builtin.bing", name: "必应", urlTemplate: "https://www.bing.com/search?q={{query}}"),
        WebSearchEngine(id: "builtin.baidu", name: "百度", urlTemplate: "https://www.baidu.com/s?wd={{query}}")
    ]

    public func url(forQuery query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let urlString = urlTemplate.replacingOccurrences(of: "{{query}}", with: encoded)
        return URL(string: urlString)
    }
}
