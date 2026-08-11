import Foundation

/// Splits a locally-imported plain-text novel into chapters -- the equivalent of a book source's
/// TOC rule, but for a file that has no structured markup at all, only chapter-heading lines like
/// "第一章 开始" scattered through the raw text. This is a from-scratch heuristic tuned against
/// common Chinese novel formatting conventions, not a port of Legado's own TXT分章 pattern.
public enum TxtChapterSplitter {
    public struct Chapter: Equatable {
        public var title: String
        public var text: String

        public init(title: String, text: String) {
            self.title = title
            self.text = text
        }
    }

    /// Matches a chapter-heading line at the start of a line: "第<digits-or-CJK-numeral>章/节/回/卷/集部"
    /// optionally followed by a subtitle on the same line, e.g. "第12章 风起" or "第三卷 第一章".
    /// `.anchorsMatchLines` makes `^` match at the start of every line, not just the whole string.
    public static let defaultPattern =
        #"^第[0-9〇零一二三四五六七八九十百千万廿卅两]+[章节回卷集部].{0,40}$"#

    /// Splits `text` at every line matching `pattern`. Each matched line becomes a chapter title;
    /// its body runs until the next match (or end of text). Text before the first match, if any
    /// and non-blank, becomes a synthetic "前言" chapter -- real novel files often have a preface
    /// or table-of-contents block before the first real chapter heading, and silently discarding
    /// it would lose real content. If nothing matches at all, the whole text becomes one chapter
    /// titled `fallbackTitle` rather than failing -- not every imported file uses a heading
    /// convention this heuristic recognizes, and "one giant chapter" is still readable.
    public static func split(_ text: String, pattern: String = defaultPattern, fallbackTitle: String) -> [Chapter] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return [Chapter(title: fallbackTitle, text: text)]
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [Chapter(title: fallbackTitle, text: text)]
        }

        var chapters: [Chapter] = []

        if let firstRange = Range(matches[0].range, in: text), firstRange.lowerBound > text.startIndex {
            let preface = String(text[text.startIndex..<firstRange.lowerBound])
            if !preface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chapters.append(Chapter(title: "前言", text: preface))
            }
        }

        for (index, match) in matches.enumerated() {
            guard let titleRange = Range(match.range, in: text) else { continue }
            let title = text[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyStart = titleRange.upperBound
            let bodyEnd: String.Index
            if index + 1 < matches.count, let nextRange = Range(matches[index + 1].range, in: text) {
                bodyEnd = nextRange.lowerBound
            } else {
                bodyEnd = text.endIndex
            }
            let body = bodyStart < bodyEnd ? String(text[bodyStart..<bodyEnd]) : ""
            chapters.append(Chapter(title: title, text: body))
        }

        return chapters
    }

    /// Tries each pattern in order (the user's enabled `TxtSplitRule`s, in priority order) and
    /// returns the first result that actually splits the text into more than one chapter -- a
    /// pattern that doesn't match this file's heading convention just yields `split`'s own
    /// single-chapter fallback, which is the signal to move on to the next one. Falls back to
    /// `defaultPattern` if no rule was given, or none of them matched anything, so an empty rule
    /// library behaves exactly like before this rule system existed.
    public static func splitTryingRules(_ text: String, rules: [String], fallbackTitle: String) -> [Chapter] {
        for pattern in rules {
            let result = split(text, pattern: pattern, fallbackTitle: fallbackTitle)
            if result.count > 1 {
                return result
            }
        }
        return split(text, pattern: defaultPattern, fallbackTitle: fallbackTitle)
    }
}
