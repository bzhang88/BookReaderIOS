import Foundation
import BookSourceModel

public enum ReplaceRuleApplier {
    /// Applies every enabled rule whose scope matches `sourceUrl` -- global rules (`scopeSourceUrl
    /// == nil`) always apply; source-scoped rules only apply to chapters from that exact source --
    /// in list order, each rule's output feeding the next. A malformed regex pattern is skipped
    /// rather than thrown, since one bad user-authored rule shouldn't break reading entirely.
    public static func apply(_ rules: [ReplaceRule], to text: String, sourceUrl: String) -> String {
        applyReportingMatches(rules, to: text, sourceUrl: sourceUrl).result
    }

    /// Same transformation as `apply`, but also reports which rules actually hit something --
    /// lets the reader show "these are the purification rules that fired on this chapter" instead
    /// of just silently transforming the text. A rule counts as "matched" if it found something to
    /// replace in the text *as of that rule's turn* (i.e. against the output of prior rules in the
    /// chain, same as `apply` itself feeds each rule's output to the next).
    public static func applyReportingMatches(
        _ rules: [ReplaceRule], to text: String, sourceUrl: String
    ) -> (result: String, matchedRules: [ReplaceRule]) {
        var result = text
        var matched: [ReplaceRule] = []
        for rule in rules where rule.enabled && (rule.scopeSourceUrl == nil || rule.scopeSourceUrl == sourceUrl) {
            guard !rule.pattern.isEmpty else { continue }
            if rule.isRegex {
                guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
                let range = NSRange(result.startIndex..., in: result)
                if regex.firstMatch(in: result, range: range) != nil {
                    matched.append(rule)
                }
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: rule.replacement)
            } else {
                if result.contains(rule.pattern) {
                    matched.append(rule)
                }
                result = result.replacingOccurrences(of: rule.pattern, with: rule.replacement)
            }
        }
        return (result, matched)
    }
}
