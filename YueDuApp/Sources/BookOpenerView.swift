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
                currentIndex: currentIndex, bookTitle: bookTitle
            )
        }
    }
}
