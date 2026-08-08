import Foundation
import BookSourceModel

public enum HighlightRuleApplier {
    public struct Segment: Equatable {
        public var text: String
        public var isHighlighted: Bool

        public init(text: String, isHighlighted: Bool) {
            self.text = text
            self.isHighlighted = isHighlighted
        }
    }

    /// Splits `text` into alternating highlighted/plain segments based on every enabled rule's
    /// regex matches (merged and sorted by position) -- deliberately segment-based rather than
    /// using `AttributedString`'s `String`-index bridging APIs, which are less battle-tested here
    /// and can't be verified without a real device; plain `NSRegularExpression`/`String` range
    /// handling is the same well-tested approach `ReplaceRuleApplier` already uses successfully.
    public static func segments(_ rules: [HighlightRule], in text: String) -> [Segment] {
        var ranges: [Range<String.Index>] = []
        for rule in rules where rule.enabled {
            guard !rule.pattern.isEmpty, let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    ranges.append(range)
                }
            }
        }

        guard !ranges.isEmpty else {
            return [Segment(text: text, isHighlighted: false)]
        }

        // Merge overlapping/adjacent ranges so matches from multiple rules covering the same text
        // don't produce duplicate or zero-length segments.
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }

        var segments: [Segment] = []
        var cursor = text.startIndex
        for range in merged {
            if cursor < range.lowerBound {
                segments.append(Segment(text: String(text[cursor..<range.lowerBound]), isHighlighted: false))
            }
            segments.append(Segment(text: String(text[range]), isHighlighted: true))
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            segments.append(Segment(text: String(text[cursor...]), isHighlighted: false))
        }
        return segments
    }
}
