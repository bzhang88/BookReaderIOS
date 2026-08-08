import Foundation
import SwiftSoup

extension RuleContent {
    /// Builds a `RuleContent` from a raw fetched response body, auto-detecting HTML vs JSON the
    /// same (deliberately cheap) way the rule engine's mode-fallback does — see
    /// `JSONContentSniffer`. `baseURL` becomes the document's base for resolving relative links.
    public static func parse(body: String, baseURL: String) throws -> RuleContent {
        if JSONContentSniffer.isJSON(body) {
            return .json(try JSONValue.parse(body))
        }
        let document = try SwiftSoup.parse(body, baseURL)
        return .html(rootElement: document)
    }
}
