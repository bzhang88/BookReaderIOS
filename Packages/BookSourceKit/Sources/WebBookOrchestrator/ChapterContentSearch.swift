import Foundation

/// One chapter's hit for a whole-book content search -- carries a short snippet around the first
/// match rather than every occurrence within the chapter, since there's no in-chapter
/// scroll-to-highlight yet for the reader to jump to a specific occurrence.
public struct ChapterSearchMatch: Equatable, Sendable, Identifiable {
    public var id: Int { chapterIndex }
    public let chapterIndex: Int
    public let chapterTitle: String
    public let snippet: String

    public init(chapterIndex: Int, chapterTitle: String, snippet: String) {
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.snippet = snippet
    }
}

public enum ChapterContentSearch {
    /// Searches each chapter's text for `keyword` (case-insensitive, or as a regex pattern when
    /// `isRegex` is set), returning at most one match per chapter in the order the chapters were
    /// given. Callers decide which chapters are eligible to search (e.g. only ones already
    /// downloaded for a network book) -- this function just does the matching over whatever it's
    /// handed. An invalid regex pattern returns no results rather than throwing -- callers should
    /// check `isValidPattern` separately to tell "malformed pattern" apart from "no matches" in the UI.
    public static func search(
        chapters: [(index: Int, title: String, text: String)], keyword: String, isRegex: Bool = false
    ) -> [ChapterSearchMatch] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if isRegex {
            return searchRegex(chapters: chapters, pattern: trimmed)
        }
        var results: [ChapterSearchMatch] = []
        for chapter in chapters {
            guard let range = chapter.text.range(of: trimmed, options: .caseInsensitive) else { continue }
            results.append(ChapterSearchMatch(
                chapterIndex: chapter.index, chapterTitle: chapter.title,
                snippet: snippet(in: chapter.text, around: range)
            ))
        }
        return results
    }

    /// Whether `pattern` compiles as a regular expression -- lets the UI distinguish "this pattern
    /// is malformed" from "this pattern matched nothing" instead of both silently showing zero
    /// results.
    public static func isValidPattern(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }

    private static func searchRegex(chapters: [(index: Int, title: String, text: String)], pattern: String) -> [ChapterSearchMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        var results: [ChapterSearchMatch] = []
        for chapter in chapters {
            let nsText = chapter.text as NSString
            guard let match = regex.firstMatch(in: chapter.text, range: NSRange(location: 0, length: nsText.length)),
                  let range = Range(match.range, in: chapter.text) else { continue }
            results.append(ChapterSearchMatch(
                chapterIndex: chapter.index, chapterTitle: chapter.title,
                snippet: snippet(in: chapter.text, around: range)
            ))
        }
        return results
    }

    private static func snippet(in text: String, around range: Range<String.Index>, radius: Int = 15) -> String {
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var result = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
        if start != text.startIndex { result = "…" + result }
        if end != text.endIndex { result += "…" }
        return result
    }
}
