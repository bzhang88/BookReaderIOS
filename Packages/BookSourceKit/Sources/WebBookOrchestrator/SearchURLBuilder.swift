import Foundation
import RuleEngine

/// Resolves a `BookSource.searchUrl` template into an actual request. Real book sources use two
/// shapes: a plain URL with `{{key}}`/`{{page}}` placeholders, or `url,{"method":"POST",...}`
/// (a JSON options blob appended after the URL with a comma) for sources that search via POST.
public enum SearchURLBuilder {
    public struct BuiltRequest: Equatable {
        public var url: String
        public var method: String
        public var body: String?
        public var headers: [String: String]
    }

    private struct RequestOptions: Codable {
        var method: String?
        var body: String?
        var headers: [String: String]?
    }

    public static func build(
        searchUrl: String, keyword: String, page: Int, baseHeaders: [String: String], resolveAgainst baseURL: String
    ) throws -> BuiltRequest {
        let bindings = ["key": keyword, "page": String(page)]

        guard let optionsRange = searchUrl.range(of: ",{") else {
            let url = URLResolver.resolve(try substitute(searchUrl, bindings: bindings), against: baseURL)
            return BuiltRequest(url: url, method: "GET", body: nil, headers: baseHeaders)
        }

        let urlPart = String(searchUrl[..<optionsRange.lowerBound])
        let optionsPart = String(searchUrl[searchUrl.index(after: optionsRange.lowerBound)...])
        let url = URLResolver.resolve(try substitute(urlPart, bindings: bindings), against: baseURL)
        let resolvedOptionsJSON = try substitute(optionsPart, bindings: bindings)

        guard let data = resolvedOptionsJSON.data(using: .utf8),
              let options = try? JSONDecoder().decode(RequestOptions.self, from: data) else {
            return BuiltRequest(url: url, method: "GET", body: nil, headers: baseHeaders)
        }

        var headers = baseHeaders
        options.headers?.forEach { headers[$0.key] = $0.value }
        return BuiltRequest(url: url, method: options.method ?? "GET", body: options.body, headers: headers)
    }

    /// Replaces every `{{ expression }}` segment with the JS-evaluated result of `expression`
    /// (`key`/`page` bound) — per the DSL, `{{ }}` inside a URL string is always JS, never a
    /// nested rule reference (unlike `{{ }}` inside a *rule* string, which is context-dependent).
    /// Templates with no `{{ }}` at all never touch JSRuntime, so plain literal search URLs work
    /// identically on every platform, not just where JavaScriptCore is available.
    private static func substitute(_ template: String, bindings: [String: String]) throws -> String {
        var result = ""
        var remainder = Substring(template)
        while let openRange = remainder.range(of: "{{") {
            result += remainder[remainder.startIndex..<openRange.lowerBound]
            let afterOpen = remainder[openRange.upperBound...]
            guard let closeRange = afterOpen.range(of: "}}") else {
                result += remainder[openRange.lowerBound...]
                remainder = Substring("")
                break
            }
            let expression = String(afterOpen[afterOpen.startIndex..<closeRange.lowerBound])
            result += try JSRuntime.evaluate(expression, bindings: bindings)
            remainder = afterOpen[closeRange.upperBound...]
        }
        result += remainder
        return result
    }
}
