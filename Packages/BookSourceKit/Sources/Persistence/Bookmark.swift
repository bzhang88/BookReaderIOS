import Foundation

/// A saved reading position -- chapter-level at minimum, plus an exact `characterOffset` within
/// that chapter's extracted text when the reader that created it could capture one (confirmed
/// against Legado_Max's own `Bookmark.chapterPos`, a character offset into the chapter, that real
/// bookmarks are meant to resolve to a precise spot, not just "somewhere in this chapter"). `nil`
/// for bookmarks created before this field existed (decodes fine from old `bookmarks.json` files --
/// `Optional` properties are decoded leniently by Swift's synthesized `Codable` conformance, no
/// migration needed) or from a reader that has no way to know its own exact position yet (`.scroll`
/// mode tracks real per-page character offsets, matching `saveReadingProgress`'s own computation;
/// the 4 paginated `PagedChapterReaderView` styles and local `.txt` books don't expose an
/// equivalent back to their bookmark-creation call sites currently, so their bookmarks stay
/// chapter-level only, same as before this field existed). Works for both network books and local
/// .txt books, which is why it carries enough fields to resolve either kind directly rather than
/// assuming a `ShelfBook` -- a bookmarked book doesn't have to still be on the shelf for the
/// bookmark to remain useful.
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
    public var characterOffset: Int?
    public var note: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString, isLocal: Bool, bookSourceUrl: String? = nil, bookIdentifier: String,
        tocUrl: String? = nil, bookTitle: String, chapterIndex: Int, chapterTitle: String,
        characterOffset: Int? = nil, note: String? = nil, createdAt: Date = Date()
    ) {
        self.id = id
        self.isLocal = isLocal
        self.bookSourceUrl = bookSourceUrl
        self.bookIdentifier = bookIdentifier
        self.tocUrl = tocUrl
        self.bookTitle = bookTitle
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.characterOffset = characterOffset
        self.note = note
        self.createdAt = createdAt
    }
}
