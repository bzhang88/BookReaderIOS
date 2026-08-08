import Foundation
import SwiftSoup

/// The "current node" a rule evaluates against — HTML or JSON — carried through per-item
/// traversal (search results, TOC rows, ...) instead of collapsing back to a plain `String` and
/// re-sniffing at every step. This is what lets the page-level JSON auto-detection (see
/// `JSONContentSniffer`) stay correct across an entire extraction, not just the first field.
public enum RuleContent {
    case html(Elements)
    case json(JSONValue)

    var isJSON: Bool {
        if case .json = self { return true }
        return false
    }

    public static func html(rootElement: Element) -> RuleContent {
        let elements = Elements()
        elements.add(rootElement)
        return .html(elements)
    }
}

/// Legado's own "is this response body JSON" check is intentionally a cheap prefix/suffix
/// heuristic, not a real parse — real-world sources are authored against this exact (slightly
/// naive) behavior, so replacing it with a "smarter" real JSON parse would disagree with them.
public enum JSONContentSniffer {
    public static func isJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }
}
