import Foundation

/// A leading `-`/`+` on a whole `bookList`/`chapterList` field, stripped before the rest of the
/// rule is parsed: `-` means "reverse the final assembled list," `+` is a no-op kept for source
/// compatibility.
public enum ListRulePrefix {
    public static func strip(_ rule: String) -> (rule: String, reversed: Bool) {
        if rule.hasPrefix("-") {
            return (String(rule.dropFirst()), true)
        }
        if rule.hasPrefix("+") {
            return (String(rule.dropFirst()), false)
        }
        return (rule, false)
    }
}
