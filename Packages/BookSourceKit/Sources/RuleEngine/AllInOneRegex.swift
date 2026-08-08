import Foundation

/// The `:`-prefixed AllInOne regex mode (`bookList`/`chapterList`/`ruleBookInfo.init` only, per
/// real Legado usage): a single regex is matched against the current content's raw text, and
/// each match becomes one row `[wholeMatch, group1, group2, ...]` — which sibling field rules
/// (e.g. `chapterName: "$2"`) index into directly. Missing/non-participating capture groups
/// become empty strings, matching the real `Matcher.group(n) ?: ""` fallback.
///
/// Real sources chain multiple regexes with `&&` here (each earlier stage narrows/concatenates
/// matched text before the *last* stage produces rows) — that multi-stage form is rare enough in
/// practice (not seen in any real source encountered so far) that v1 only supports a single
/// pattern and throws `.notYetImplemented` for the chained form rather than guessing at it.
public enum AllInOneRegex {
    public static func extractRows(pattern: String, from text: String) throws -> [[String]] {
        if pattern.contains("&&") {
            throw RuleEngineError.notYetImplemented(
                "AllInOne multi-stage regex chaining ('&&' inside a ':'-prefixed rule) — not seen in practice, not implemented"
            )
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw RuleEngineError.invalidRule("Invalid AllInOne regex pattern: \(pattern)")
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.map { match in
            (0..<match.numberOfRanges).map { groupIndex in
                let range = match.range(at: groupIndex)
                guard range.location != NSNotFound else { return "" }
                return ns.substring(with: range)
            }
        }
    }
}
