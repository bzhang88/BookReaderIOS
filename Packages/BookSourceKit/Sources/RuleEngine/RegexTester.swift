import Foundation

/// Small standalone regex-testing tool for the developer toolbox -- lets a book-source author try
/// a pattern (e.g. one they're about to put in a `replaceRegex`/`##pattern##replacement##` field)
/// against sample text before committing it to a real rule. Not tied to the engine's own regex
/// consumers (`RegexSuffixParser`, `AllInOneRegex`) -- this is a generic `NSRegularExpression`
/// wrapper for ad hoc experimentation, kept in `RuleEngine` because that's where every other
/// regex-shaped concern in this codebase already lives.
public enum RegexTester {
    public struct Match: Equatable {
        public let matchedText: String
        /// Capture groups in order; `nil` for a group that didn't participate in this particular
        /// match (e.g. one side of an alternation).
        public let groups: [String?]

        public init(matchedText: String, groups: [String?]) {
            self.matchedText = matchedText
            self.groups = groups
        }
    }

    public enum TestError: Error, Equatable {
        case invalidPattern
    }

    public static func test(
        pattern: String, text: String,
        caseInsensitive: Bool = false, dotMatchesNewlines: Bool = false
    ) -> Result<[Match], TestError> {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        if dotMatchesNewlines { options.insert(.dotMatchesLineSeparators) }

        guard !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return .failure(.invalidPattern)
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let results = regex.matches(in: text, range: fullRange).map { result -> Match in
            var groups: [String?] = []
            if result.numberOfRanges > 1 {
                for i in 1..<result.numberOfRanges {
                    let r = result.range(at: i)
                    groups.append(r.location == NSNotFound ? nil : nsText.substring(with: r))
                }
            }
            return Match(matchedText: nsText.substring(with: result.range), groups: groups)
        }
        return .success(results)
    }
}
