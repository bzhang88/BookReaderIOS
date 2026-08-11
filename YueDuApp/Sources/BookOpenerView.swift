import SwiftUI
import BookSourceModel
import WebBookOrchestrator

/// Routes to the right reader for a source's content type -- a drop-in replacement for constructing
/// `ReaderView` directly at any of this app's "start reading" entry points (shelf resume, table of
/// contents, bookmarks), so none of them need their own `bookSourceType` branch. Only image sources
/// (manga) get a different reader for now; audio sources get their own player elsewhere (see
/// `AudiobookPlayerView`), reached through a separate entry point since a shelf book's "resume
/// reading" affordance means something different for a player (start playback) than for a reader
/// (jump to a chapter view).
struct BookOpenerView: View {
    let source: BookSource
    let bookUrl: String
    let tocUrl: String
    let chapters: [BookChapter]
    let currentIndex: Int
    let bookTitle: String

    var body: some View {
        if source.bookSourceType == 2 {
            MangaReaderView(
                source: source, bookUrl: bookUrl, tocUrl: tocUrl, chapters: chapters,
                currentIndex: currentIndex, bookTitle: bookTitle
            )
        } else {
            ReaderView(
                source: source, bookUrl: bookUrl, tocUrl: tocUrl, chapters: chapters,
                currentIndex: currentIndex, bookTitle: bookTitle
            )
        }
    }
}
