import Foundation

/// Combines a book's chapters back into a single plain-text file for sharing -- the inverse of
/// `TxtChapterSplitter`, used both for a locally-imported book (already fully in memory) and for a
/// network book that's been fully downloaded via `ChapterCacheStore` (there's no server-side
/// "export" endpoint to call; re-assembling from what's already been fetched is the only option).
public enum TxtExporter {
    public static func combine(bookTitle: String, chapters: [(title: String, text: String)]) -> String {
        var result = bookTitle + "\n\n"
        for chapter in chapters {
            result += chapter.title + "\n\n" + chapter.text + "\n\n"
        }
        return result
    }

    /// Strips characters that are invalid (or awkward) in a filename on iOS's filesystem -- book
    /// titles are free text and can contain "/" or other separators a source's HTML happened to
    /// include. Falls back to a generic name rather than producing an empty filename.
    public static func sanitizedFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: invalidCharacters).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "导出" : cleaned
    }
}
