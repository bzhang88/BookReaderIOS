import Foundation

/// Converts an HTML fragment (as returned by a content rule using the `html` keyword, e.g.
/// `@css:#content@html`) into readable plain text with paragraph breaks preserved.
///
/// Deliberately does NOT use SwiftSoup's `Element.text()` for the final step — jsoup-family
/// `.text()` normalizes whitespace (collapsing newlines into spaces), which would destroy the
/// paragraph breaks this formatter exists to preserve. Block-boundary tags are converted to `\n`
/// markers *before* stripping tags, so they survive.
public enum HTMLTextFormatter {
    public static func plainText(from html: String) -> String {
        var normalized = html
        for pattern in blockBreakPatterns {
            normalized = replace(pattern, in: normalized, with: "\n")
        }
        normalized = replace(#"<[^>]*>"#, in: normalized, with: "")
        normalized = unescapeEntities(normalized)

        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return lines.joined(separator: "\n")
    }

    private static let blockBreakPatterns = [
        #"<br\s*/?>"#, #"</p>"#, #"</div>"#, #"</li>"#, #"</h[1-6]>"#
    ]

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let ns = text as NSString
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }

    private static let namedEntities: [String: String] = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
        "&nbsp;": " "
    ]

    private static func unescapeEntities(_ text: String) -> String {
        var result = text
        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Numeric entities: &#123; and &#x7B;
        result = replace(#"&#x([0-9A-Fa-f]+);"#, in: result) { hex in
            UInt32(hex, radix: 16).flatMap { Unicode.Scalar($0) }.map { String($0) } ?? ""
        }
        result = replace(#"&#([0-9]+);"#, in: result) { dec in
            UInt32(dec).flatMap { Unicode.Scalar($0) }.map { String($0) } ?? ""
        }
        return result
    }

    private static func replace(_ pattern: String, in text: String, transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var lastEnd = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let captured = ns.substring(with: match.range(at: 1))
            result += transform(captured)
            lastEnd = match.range.location + match.range.length
        }
        result += ns.substring(from: lastEnd)
        return result
    }
}
