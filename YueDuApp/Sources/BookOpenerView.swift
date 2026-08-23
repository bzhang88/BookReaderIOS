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
    /// Threaded through to `ReaderView` so its own 换源/章节换源 sheets can pass a real author to
    /// `ChangeSourceView` instead of always hardcoding `nil` -- see `ReaderView.bookAuthor`'s doc
    /// comment. `nil` (the default) keeps every existing call site that doesn't know the author
    /// (e.g. `BookmarkListView`, whose `Bookmark` model has no author field at all) compiling
    /// unchanged; that just means change-source falls back to name-only matching there, same as before.
    var bookAuthor: String? = nil
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
                currentIndex: currentIndex, bookTitle: bookTitle, bookAuthor: bookAuthor,
                resumeCharacterOffset: resumeCharacterOffset
            )
        }
    }
}
