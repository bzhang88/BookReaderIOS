import Foundation

/// A saved reading position, chapter-level (this app doesn't track a finer scroll offset anywhere
/// yet, so a bookmark is "this chapter of this book", not an exact paragraph). Works for both
/// network books and local .txt books, which is why it carries enough fields to resolve either
/// kind directly rather than assuming a `ShelfBook` -- a bookmarked book doesn't have to still be
/// on the shelf for the bookmark to remain useful.
public struct Bookmark: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var isLocal: Bool
    /// nil for local books (which have no source).
    public var bookSourceUrl: String?
    /// The network book's `bookUrl`, or the local book's `id`, depending on `isLocal`.
    public var bookIdentifier: String
    /// nil for local books (which have no separate TOC fetch -- chapters are already in memory).
    public var tocUrl: String?
    public var bookTitle: String
    public var chapterIndex: Int
    public var chapterTitle: String
    public var note: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString, isLocal: Bool, bookSourceUrl: String? = nil, bookIdentifier: String,
        tocUrl: String? = nil, bookTitle: String, chapterIndex: Int, chapterTitle: String, note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.isLocal = isLocal
        self.bookSourceUrl = bookSourceUrl
        self.bookIdentifier = bookIdentifier
        self.tocUrl = tocUrl
        self.bookTitle = bookTitle
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.note = note
        self.createdAt = createdAt
    }
}
