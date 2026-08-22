import Foundation
import BookSourceModel

public enum ReplaceRuleApplier {
    /// Which kind of text a call is purifying -- gates on `ReplaceRule.scopeTitle`/`scopeContent`.
    /// Every current call site in this app only ever purifies chapter body text, so `.content` is
    /// both the default and, so far, the only value anything actually passes -- see
    /// `ReplaceRule.scopeTitle`'s own doc comment for why title purification isn't wired up yet.
    public enum TextKind {
        case title, content
    }

    /// Applies every enabled, in-scope rule, ordered by `ReplaceRule.order` -- in that order, each
    /// rule's output feeds the next. A malformed regex pattern is skipped rather than thrown, since
    /// one bad user-authored rule shouldn't break reading entirely.
    public static func apply(
        _ rules: [ReplaceRule], to text: String, bookName: String, sourceUrl: String, textKind: TextKind = .content
    ) -> String {
        applyReportingMatches(rules, to: text, bookName: bookName, sourceUrl: sourceUrl, textKind: textKind).result
    }

    /// Same transformation as `apply`, but also reports which rules actually hit something --
    /// lets the reader show "these are the purification rules that fired on this chapter" instead
    /// of just silently transforming the text. A rule counts as "matched" if it found something to
    /// replace in the text *as of that rule's turn* (i.e. against the output of prior rules in the
    /// chain, same as `apply` itself feeds each rule's output to the next).
    public static func applyReportingMatches(
        _ rules: [ReplaceRule], to text: String, bookName: String, sourceUrl: String, textKind: TextKind = .content
    ) -> (result: String, matchedRules: [ReplaceRule]) {
        var result = text
        var matched: [ReplaceRule] = []
        let ordered = rules.sorted { $0.order < $1.order }
        for rule in ordered
        where rule.enabled && appliesTo(textKind, rule: rule) && isInScope(rule, bookName: bookName, sourceUrl: sourceUrl) {
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

    private static func appliesTo(_ textKind: TextKind, rule: ReplaceRule) -> Bool {
        switch textKind {
        case .title: return rule.scopeTitle
        case .content: return rule.scopeContent
        }
    }

    /// Confirmed against Legado's real `ReplaceRuleDao` query (`scope LIKE '%'||:name||'%' or scope
    /// LIKE '%'||:origin||'%'`) -- plain substring containment of the *whole* `scope`/`excludeScope`
    /// string, not a split-into-tokens-then-exact-match comparison (see `ReplaceRule.scope`'s own
    /// doc comment for why that's not actually needed for comma-separated scopes to work correctly).
    /// An empty `bookName`/`sourceUrl` never counts as contained in anything, even though `"x".
    /// contains("")` is trivially true in Swift -- otherwise a rule scoped to a specific book/source
    /// would wrongly fire for a caller that doesn't know its own book name (`LocalReaderView` passes
    /// `""` today).
    private static func isInScope(_ rule: ReplaceRule, bookName: String, sourceUrl: String) -> Bool {
        func matches(_ scopeText: String) -> Bool {
            (!bookName.isEmpty && scopeText.contains(bookName)) || (!sourceUrl.isEmpty && scopeText.contains(sourceUrl))
        }
        if let excludeScope = rule.excludeScope, !excludeScope.isEmpty, matches(excludeScope) {
            return false
        }
        guard let scope = rule.scope, !scope.isEmpty else { return true }
        return matches(scope)
    }
}
