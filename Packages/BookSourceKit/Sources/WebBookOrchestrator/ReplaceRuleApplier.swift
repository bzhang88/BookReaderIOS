import Foundation
import BookSourceModel

public enum ReplaceRuleApplier {
    /// Applies every enabled rule whose scope matches `sourceUrl` -- global rules (`scopeSourceUrl
    /// == nil`) always apply; source-scoped rules only apply to chapters from that exact source --
    /// in list order, each rule's output feeding the next. A malformed regex pattern is skipped
    /// rather than thrown, since one bad user-authored rule shouldn't break reading entirely.
    public static func apply(_ rules: [ReplaceRule], to text: String, sourceUrl: String) -> String {
        var result = text
        for rule in rules where rule.enabled && (rule.scopeSourceUrl == nil || rule.scopeSourceUrl == sourceUrl) {
            guard !rule.pattern.isEmpty else { continue }
            if rule.isRegex {
                guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: rule.replacement)
            } else {
                result = result.replacingOccurrences(of: rule.pattern, with: rule.replacement)
            }
        }
        return result
    }
}
