import Foundation

/// How multiple same-mode sub-rules combine. A rule string commits to exactly one of these —
/// mixing `&&` and `||` in one rule string is not a thing the format supports.
public enum Combinator: Equatable {
    /// `&&` — evaluate every sub-rule, concatenate all non-empty results.
    case concat
    /// `||` — evaluate sub-rules left-to-right, use the first non-empty result.
    case firstNonEmpty
    /// `%%` — zip sub-rule result lists index-by-index.
    case zip
}

/// Splits a rule string into same-mode sub-rules on `&&`/`||`/`%%`, respecting bracket/quote
/// nesting (see `BalancedScanner`) so a delimiter occurring inside a selector predicate isn't
/// mistaken for a real split point. Whichever of the three delimiters appears first (at the top
/// level) wins for the whole string.
public enum CombinatorSplitter {
    public static func split(_ rule: String) -> (combinator: Combinator?, parts: [String]) {
        let candidates: [(delimiter: String, combinator: Combinator)] = [
            ("&&", .concat), ("||", .firstNonEmpty), ("%%", .zip)
        ]

        var winner: (offset: Int, delimiter: String, combinator: Combinator)?
        for candidate in candidates {
            guard let offset = BalancedScanner.firstTopLevelOffset(of: candidate.delimiter, in: rule) else {
                continue
            }
            if winner == nil || offset < winner!.offset {
                winner = (offset, candidate.delimiter, candidate.combinator)
            }
        }

        guard let winner else {
            return (nil, [rule])
        }
        return (winner.combinator, BalancedScanner.split(rule, by: winner.delimiter))
    }
}
