import Foundation

/// A book the user has added to their shelf, with enough of its own copy of the book-info fields
/// to render a shelf row without re-fetching, plus where they last left off reading.
public struct ShelfBook: Codable, Equatable, Identifiable, Sendable {
    public var bookSourceUrl: String
    public var bookUrl: String
    public var name: String
    public var author: String?
    public var coverUrl: String?
    public var intro: String?
    public var tocUrl: String
    public var lastChapterTitle: String?
    public var addedAt: Date
    /// Display group assigned by a `TagGroupRule` match (or manually, in a future increment) --
    /// optional and defaulted so it decodes fine from shelf.json files saved before this field
    /// existed.
    public var group: String?

    /// Exact resume position: which chapter, and a character offset within that chapter's
    /// extracted text — coarser than a scroll-position (which needs the actual rendered layout,
    /// a reader-UI concern) but enough to jump back to almost exactly where they left off.
    public var lastReadChapterIndex: Int?
    public var lastReadChapterTitle: String?
    public var lastReadCharacterOffset: Int
    public var lastReadAt: Date?

    /// How many chapters this book's TOC had, as of the last time it was actually fetched (resuming
    /// into the reader, changing source, etc.) -- not kept perfectly live (a source could add
    /// chapters between visits), just refreshed opportunistically whenever the real chapter list is
    /// already being fetched anyway. Powers the shelf's unread-count badge: `totalChapterCount -
    /// (lastReadChapterIndex + 1)`, matching Legado's own badge. `nil` for books never opened since
    /// this field was added, or before the TOC has ever been fetched once.
    public var totalChapterCount: Int?
    /// Whether the shelf-wide "检查更新" sweep (`ShelfView`'s own action, not an automatic
    /// background one) should re-check this book's TOC at all -- matching Legado's real `Book.
    /// canUpdate`. `nil`/`true` both mean "yes, check it" -- only an explicit `false` excludes a
    /// book (typically a finished/dropped one a user doesn't expect new chapters on, where checking
    /// is just wasted network traffic every sweep). `Optional`, not a plain `Bool` defaulting to
    /// `true`, so this decodes safely from every `shelf.json` written before this field existed:
    /// `JSONFileStore.load()` uses `try decoder.decode()` (throws, not nil-on-failure), and a
    /// non-optional field with only an `init` default would throw on any pre-existing shelf file
    /// missing this key -- since most callers wrap that load in `try?`, that throw would silently
    /// present as an *empty shelf*, not an error. This project already hit exactly this shape of bug
    /// once before (`Bookmark.characterOffset`) and settled on Optional as the safe fix.
    public var canUpdate: Bool?

    public var id: String { bookUrl }

    public init(
        bookSourceUrl: String, bookUrl: String, name: String, author: String? = nil,
        coverUrl: String? = nil, intro: String? = nil, tocUrl: String, lastChapterTitle: String? = nil,
        addedAt: Date = Date(), group: String? = nil, lastReadChapterIndex: Int? = nil,
        lastReadChapterTitle: String? = nil, lastReadCharacterOffset: Int = 0, lastReadAt: Date? = nil,
        totalChapterCount: Int? = nil, canUpdate: Bool? = nil
    ) {
        self.bookSourceUrl = bookSourceUrl
        self.bookUrl = bookUrl
        self.name = name
        self.author = author
        self.coverUrl = coverUrl
        self.intro = intro
        self.tocUrl = tocUrl
        self.lastChapterTitle = lastChapterTitle
        self.addedAt = addedAt
        self.group = group
        self.lastReadChapterIndex = lastReadChapterIndex
        self.lastReadChapterTitle = lastReadChapterTitle
        self.lastReadCharacterOffset = lastReadCharacterOffset
        self.lastReadAt = lastReadAt
        self.totalChapterCount = totalChapterCount
        self.canUpdate = canUpdate
    }
}
