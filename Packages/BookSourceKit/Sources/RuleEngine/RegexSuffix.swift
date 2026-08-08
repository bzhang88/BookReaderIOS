import Foundation

/// A trailing `##pattern##replacement` (global purify) or `##pattern##replacement##` (OnlyOne)
/// suffix on a rule string.
public struct RegexSuffix: Equatable {
    public var pattern: String
    public var replacement: String
    /// OnlyOne semantics: find the *first* match of `pattern` anywhere in the input, then
    /// `replaceFirst` scoped to *just that matched substring* — not "replace the first
    /// occurrence within the whole string" (a natural but wrong first guess).
    public var onlyOne: Bool

    public init(pattern: String, replacement: String, onlyOne: Bool) {
        self.pattern = pattern
        self.replacement = replacement
        self.onlyOne = onlyOne
    }
}

public enum RegexSuffixParser {
    /// Splits a trailing regex suffix off `rule`. Mirrors Legado's approach exactly:
    /// `rule.split("##")` — part 0 is the real selector rule, part 1 the pattern, part 2 the
    /// (optional, default-empty) replacement; a 4th part (even if empty) marks OnlyOne mode.
    public static func extract(from rule: String) -> (remainder: String, suffix: RegexSuffix?) {
        let parts = rule.components(separatedBy: "##")
        guard parts.count >= 2 else { return (rule, nil) }

        let selectorPart = parts[0]
        let pattern = parts[1]

        if parts.count >= 4 {
            return (selectorPart, RegexSuffix(pattern: pattern, replacement: parts[2], onlyOne: true))
        }
        if parts.count == 3 {
            return (selectorPart, RegexSuffix(pattern: pattern, replacement: parts[2], onlyOne: false))
        }
        return (selectorPart, RegexSuffix(pattern: pattern, replacement: "", onlyOne: false))
    }

    /// Applies a parsed suffix to `input`. Invalid regex patterns fail soft (return `input`
    /// unchanged) rather than throwing — a malformed pattern in one field of an otherwise-working
    /// book source shouldn't take down the whole extraction.
    public static func apply(_ suffix: RegexSuffix, to input: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: suffix.pattern) else { return input }
        let nsInput = input as NSString
        let fullRange = NSRange(location: 0, length: nsInput.length)

        if !suffix.onlyOne {
            return regex.stringByReplacingMatches(in: input, range: fullRange, withTemplate: suffix.replacement)
        }

        guard let match = regex.firstMatch(in: input, range: fullRange) else {
            return ""
        }
        let matched = nsInput.substring(with: match.range)
        let nsMatched = matched as NSString
        guard let innerMatch = regex.firstMatch(in: matched, range: NSRange(location: 0, length: nsMatched.length)) else {
            return matched
        }
        let mutable = NSMutableString(string: matched)
        let replacement = regex.replacementString(for: innerMatch, in: matched, offset: 0, template: suffix.replacement)
        mutable.replaceCharacters(in: innerMatch.range, with: replacement)
        return mutable as String
    }
}
