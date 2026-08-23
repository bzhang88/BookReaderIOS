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
    /// Display groups this book belongs to -- real gap found comparing against Legado: its own
    /// `Book.group` is a bitmask (`Long`) so a book can carry several groups' bits at once, while
    /// this field used to be a single optional `String`, so a book could only ever be filed into one
    /// group. Kept as a plain `[String]` of names (not a numeric bitmask) to match this app's own
    /// established string-name convention (`ShelfGroupStore` already only knows names, no numeric
    /// IDs) rather than inventing a bit-allocation scheme just to mirror Legado's storage detail.
    /// The custom `Codable` below decodes the old single-string `group` JSON shape transparently
    /// into a one-element array, so `shelf.json` written before this change keeps working.
    public var groups: [String]

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
        addedAt: Date = Date(), groups: [String] = [], lastReadChapterIndex: Int? = nil,
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
        self.groups = groups
        self.lastReadChapterIndex = lastReadChapterIndex
        self.lastReadChapterTitle = lastReadChapterTitle
        self.lastReadCharacterOffset = lastReadCharacterOffset
        self.lastReadAt = lastReadAt
        self.totalChapterCount = totalChapterCount
        self.canUpdate = canUpdate
    }

    private enum CodingKeys: String, CodingKey {
        case bookSourceUrl, bookUrl, name, author, coverUrl, intro, tocUrl, lastChapterTitle, addedAt
        // Still the on-disk key name "group" (singular) -- only the Swift-side type/shape changed,
        // not the JSON key, so a re-saved file doesn't leave a stale duplicate key behind.
        case groups = "group"
        case lastReadChapterIndex, lastReadChapterTitle, lastReadCharacterOffset, lastReadAt
        case totalChapterCount, canUpdate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bookSourceUrl = try container.decode(String.self, forKey: .bookSourceUrl)
        bookUrl = try container.decode(String.self, forKey: .bookUrl)
        name = try container.decode(String.self, forKey: .name)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
        intro = try container.decodeIfPresent(String.self, forKey: .intro)
        tocUrl = try container.decode(String.self, forKey: .tocUrl)
        lastChapterTitle = try container.decodeIfPresent(String.self, forKey: .lastChapterTitle)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        // A pre-existing file's "group" key is a single `String` (or absent/null); a file saved by
        // this version is a `[String]`. Try the new shape first, and only fall back to the old one
        // if that fails -- a plain `decodeIfPresent` would throw (not return nil) on a type mismatch,
        // which is exactly what happens when reading an old file's single-string value.
        if let multi = try? container.decode([String].self, forKey: .groups) {
            groups = multi
        } else if let single = try container.decodeIfPresent(String.self, forKey: .groups), !single.isEmpty {
            groups = [single]
        } else {
            groups = []
        }
        lastReadChapterIndex = try container.decodeIfPresent(Int.self, forKey: .lastReadChapterIndex)
        lastReadChapterTitle = try container.decodeIfPresent(String.self, forKey: .lastReadChapterTitle)
        lastReadCharacterOffset = try container.decode(Int.self, forKey: .lastReadCharacterOffset)
        lastReadAt = try container.decodeIfPresent(Date.self, forKey: .lastReadAt)
        totalChapterCount = try container.decodeIfPresent(Int.self, forKey: .totalChapterCount)
        canUpdate = try container.decodeIfPresent(Bool.self, forKey: .canUpdate)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bookSourceUrl, forKey: .bookSourceUrl)
        try container.encode(bookUrl, forKey: .bookUrl)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try container.encodeIfPresent(intro, forKey: .intro)
        try container.encode(tocUrl, forKey: .tocUrl)
        try container.encodeIfPresent(lastChapterTitle, forKey: .lastChapterTitle)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encode(groups, forKey: .groups)
        try container.encodeIfPresent(lastReadChapterIndex, forKey: .lastReadChapterIndex)
        try container.encodeIfPresent(lastReadChapterTitle, forKey: .lastReadChapterTitle)
        try container.encode(lastReadCharacterOffset, forKey: .lastReadCharacterOffset)
        try container.encodeIfPresent(lastReadAt, forKey: .lastReadAt)
        try container.encodeIfPresent(totalChapterCount, forKey: .totalChapterCount)
        try container.encodeIfPresent(canUpdate, forKey: .canUpdate)
    }
}
