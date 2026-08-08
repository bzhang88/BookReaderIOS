import Foundation

/// Finds delimiter occurrences in a rule string while respecting bracket/quote nesting, so a
/// delimiter that legally appears inside a selector predicate (e.g. `[attr="a&&b"]`) or a quoted
/// string isn't mistaken for a real split point. This is the shared primitive behind combinator
/// splitting (`&&`/`||`/`%%`) and the `@`-separated jsoup dot-chain splitting.
enum BalancedScanner {
    /// Returns the start indices (UTF-16 offsets) of every top-level (depth-0, not-in-quotes)
    /// occurrence of `delimiter` in `text`.
    static func topLevelRanges(of delimiter: String, in text: String) -> [Range<String.Index>] {
        guard !delimiter.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var depth = 0
        var quote: Character? = nil
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]

            if let q = quote {
                if c == q { quote = nil }
                i = text.index(after: i)
                continue
            }

            switch c {
            case "'", "\"":
                quote = c
            case "[", "(", "{":
                depth += 1
            case "]", ")", "}":
                depth = max(0, depth - 1)
            default:
                break
            }

            if depth == 0 && quote == nil {
                if let end = text.index(i, offsetBy: delimiter.count, limitedBy: text.endIndex),
                   text[i..<end] == delimiter {
                    ranges.append(i..<end)
                    i = end
                    continue
                }
            }

            i = text.index(after: i)
        }

        return ranges
    }

    /// Splits `text` on every top-level occurrence of `delimiter`.
    static func split(_ text: String, by delimiter: String) -> [String] {
        let ranges = topLevelRanges(of: delimiter, in: text)
        guard !ranges.isEmpty else { return [text] }

        var parts: [String] = []
        var cursor = text.startIndex
        for range in ranges {
            parts.append(String(text[cursor..<range.lowerBound]))
            cursor = range.upperBound
        }
        parts.append(String(text[cursor...]))
        return parts
    }

    /// The UTF-16 offset of the first top-level occurrence of `delimiter`, if any — used to
    /// decide which of several candidate delimiters appears earliest.
    static func firstTopLevelOffset(of delimiter: String, in text: String) -> Int? {
        topLevelRanges(of: delimiter, in: text).first.map { text.distance(from: text.startIndex, to: $0.lowerBound) }
    }
}
