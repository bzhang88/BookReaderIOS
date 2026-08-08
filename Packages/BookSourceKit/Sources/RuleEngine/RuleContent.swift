import Foundation
import SwiftSoup

/// The "current node" a rule evaluates against — HTML or JSON — carried through per-item
/// traversal (search results, TOC rows, ...) instead of collapsing back to a plain `String` and
/// re-sniffing at every step. This is what lets the page-level JSON auto-detection (see
/// `JSONContentSniffer`) stay correct across an entire extraction, not just the first field.
public enum RuleContent {
    case html(Elements)
    case json(JSONValue)
    /// One AllInOne regex match: index 0 is the whole match, index N is capture group N (empty
    /// string for a group that didn't participate in the match) — mirrors the real
    /// `List<String>` row shape a sibling `"$1"`/`"$2"` rule indexes into.
    case regexRow([String])

    var isJSON: Bool {
        if case .json = self { return true }
        return false
    }

    var isRegexRow: Bool {
        if case .regexRow = self { return true }
        return false
    }

    public static func html(rootElement: Element) -> RuleContent {
        let elements = Elements()
        elements.add(rootElement)
        return .html(elements)
    }

    /// A textual view of this content for the AllInOne regex extractor to scan. For HTML this is
    /// the parsed DOM re-serialized back to markup (`outerHtml()`) rather than the original raw
    /// response bytes — this engine doesn't carry the pre-parse source string through per-item
    /// narrowing, so regex patterns that depend on exact original whitespace/attribute-ordering
    /// quirks (rather than just tag/attribute structure) may not match identically to the real
    /// app. Real-world AllInOne patterns match structural tag boundaries, not raw-byte quirks, so
    /// this is a reasonable v1 trade-off, not a silent-wrong-answer risk.
    func rawText() throws -> String {
        switch self {
        case .html(let elements):
            return try elements.outerHtml()
        case .json(let value):
            return value.stringValue ?? ""
        case .regexRow(let row):
            return row.first ?? ""
        }
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
