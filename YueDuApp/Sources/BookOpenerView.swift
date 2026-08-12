import SwiftUI
import BookSourceModel
import WebBookOrchestrator

/// Routes to the right reader/player for a source's content type -- a drop-in replacement for
/// constructing `ReaderView` directly at any of this app's "start reading" entry points (shelf
/// resume, table of contents, bookmarks), so none of them need their own `bookSourceType` branch.
struct BookOpenerView: View {
    let source: BookSource
    let bookUrl: String
    let tocUrl: String
    let chapters: [BookChapter]
    let currentIndex: Int
    let bookTitle: String
    /// Only meaningful for the text-reader (`default`) case -- audio/manga sources have no notion of
    /// a character offset into chapter text. Defaults to 0 (no saved position) so every existing
    /// call site that doesn't know/care about this keeps compiling unchanged.
    var resumeCharacterOffset: Int = 0

    var body: some View {
        switch source.bookSourceType {
        case 1:
            AudiobookPlayerView(
                source: source, bookUrl: bookUrl, tocUrl: tocUrl, chapters: chapters,
                currentIndex: currentIndex, bookTitle: bookTitle
            )
        case 2:
            MangaReaderView(
                source: source, bookUrl: bookUrl, tocUrl: tocUrl, chapters: chapters,
                currentIndex: currentIndex, bookTitle: bookTitle
            )
        default:
            ReaderView(
                source: source, bookUrl: bookUrl, tocUrl: tocUrl, chapters: chapters,
                currentIndex: currentIndex, bookTitle: bookTitle, resumeCharacterOffset: resumeCharacterOffset
            )
        }
    }
}
