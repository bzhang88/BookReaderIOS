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
    /// A short, single-line preview of the actual passage this bookmark points at -- confirmed
    /// against Legado_Max's own `Bookmark.bookText`, which exists for exactly this: so the bookmark
    /// list reads as *which* passage was bookmarked without re-opening the book. `Optional`, not
    /// defaulted to an empty string, so this decodes safely from any `bookmarks.json` written before
    /// this field existed (see `characterOffset`'s own doc comment for why this project treats new
    /// fields this way).
    public var excerpt: String?
    public var note: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString, isLocal: Bool, bookSourceUrl: String? = nil, bookIdentifier: String,
        tocUrl: String? = nil, bookTitle: String, chapterIndex: Int, chapterTitle: String,
        characterOffset: Int? = nil, excerpt: String? = nil, note: String? = nil, createdAt: Date = Date()
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
        self.excerpt = excerpt
        self.note = note
        self.createdAt = createdAt
    }

    /// Collapses a passage of prose into a single-line, length-capped preview for the bookmark list.
    /// `nil` for an all-whitespace passage -- an empty preview line is worse than no preview at all.
    public static func makeExcerpt(from text: String, maxLength: Int = 60) -> String? {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength)) + "…"
    }
}
