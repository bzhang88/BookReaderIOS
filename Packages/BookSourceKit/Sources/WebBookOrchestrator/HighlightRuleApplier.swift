import Foundation
import BookSourceModel

public enum HighlightRuleApplier {
    public struct Segment: Equatable {
        public var text: String
        /// The rule that owns this span's styling, or `nil` for an unhighlighted span. Carrying the
        /// whole rule (not just a `Bool`) is what lets the renderer apply each rule's own
        /// color/bold/underline instead of one hardcoded style for every match.
        public var rule: HighlightRule?

        public init(text: String, rule: HighlightRule? = nil) {
            self.text = text
            self.rule = rule
        }

        public var isHighlighted: Bool { rule != nil }
    }

    /// Splits `text` into alternating highlighted/plain segments based on every enabled rule's
    /// regex matches (merged and sorted by position) -- deliberately segment-based rather than
    /// using `AttributedString`'s `String`-index bridging APIs, which are less battle-tested here
    /// and can't be verified without a real device; plain `NSRegularExpression`/`String` range
    /// handling is the same well-tested approach `ReplaceRuleApplier` already uses successfully.
    ///
    /// `isTitle` filters by each rule's own `targetScope` (matching Legado's title/body split) --
    /// defaults to `false` since most callers style body paragraphs; a chapter-heading renderer
    /// passes `true` so title-only rules apply there and body-only rules don't leak into it.
    public static func segments(_ rules: [HighlightRule], in text: String, isTitle: Bool = false) -> [Segment] {
        var matches: [(range: Range<String.Index>, rule: HighlightRule)] = []
        for rule in rules where rule.enabled && rule.applies(toTitle: isTitle) {
            guard !rule.pattern.isEmpty, let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            let nsText = text as NSString
            let found = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in found {
                if let range = Range(match.range, in: text) {
                    matches.append((range, rule))
                }
            }
        }

        guard !matches.isEmpty else {
            return [Segment(text: text)]
        }

        // Stable sort by start position -- ties (and any later merge) keep whichever rule's match
        // was found first, so an overlap between two rules' matches consistently styles as
        // whichever rule comes first in the user's list, not whichever happened to be discovered
        // last while merging.
        let sortedMatches = matches.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var merged: [(range: Range<String.Index>, rule: HighlightRule)] = []
        for match in sortedMatches {
            if let last = merged.last, match.range.lowerBound <= last.range.upperBound {
                let newRange = last.range.lowerBound..<max(last.range.upperBound, match.range.upperBound)
                merged[merged.count - 1] = (newRange, last.rule)
            } else {
                merged.append(match)
            }
        }

        var segments: [Segment] = []
        var cursor = text.startIndex
        for match in merged {
            if cursor < match.range.lowerBound {
                segments.append(Segment(text: String(text[cursor..<match.range.lowerBound])))
            }
            segments.append(Segment(text: String(text[match.range]), rule: match.rule))
            cursor = match.range.upperBound
        }
        if cursor < text.endIndex {
            segments.append(Segment(text: String(text[cursor...])))
        }
        return segments
    }
}
