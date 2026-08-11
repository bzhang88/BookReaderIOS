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
    /// Searches each chapter's text for `keyword` (case-insensitive), returning at most one match
    /// per chapter in the order the chapters were given. Callers decide which chapters are eligible
    /// to search (e.g. only ones already downloaded for a network book) -- this function just does
    /// the string matching over whatever it's handed.
    public static func search(chapters: [(index: Int, title: String, text: String)], keyword: String) -> [ChapterSearchMatch] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
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

    private static func snippet(in text: String, around range: Range<String.Index>, radius: Int = 15) -> String {
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var result = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
        if start != text.startIndex { result = "…" + result }
        if end != text.endIndex { result += "…" }
        return result
    }
}
