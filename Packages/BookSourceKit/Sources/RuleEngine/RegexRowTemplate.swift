import Foundation

/// Substitutes bare `$1`/`$2`-style references in a rule string with the corresponding element
/// of an AllInOne regex match row (index 0 = whole match, index N = capture group N). Mirrors
/// the real `\$\d{1,2}` scan-and-substitute in `AnalyzeRule.SourceRule.makeUpRule` — an
/// out-of-range or non-participating index degrades to an empty string rather than throwing,
/// matching the real fallback behavior.
public enum RegexRowTemplate {
    private static let pattern = try! NSRegularExpression(pattern: #"\$\d{1,2}"#)

    public static func substitute(_ template: String, row: [String]) -> String {
        let ns = template as NSString
        let matches = pattern.matches(in: template, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return template }

        var result = ""
        var lastEnd = 0
        for match in matches {
            result += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let token = ns.substring(with: match.range) // e.g. "$2"
            if let index = Int(token.dropFirst()), index >= 0, index < row.count {
                result += row[index]
            }
            lastEnd = match.range.location + match.range.length
        }
        result += ns.substring(from: lastEnd)
        return result
    }
}
