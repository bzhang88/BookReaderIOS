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

    public var id: String { bookUrl }

    public init(
        bookSourceUrl: String, bookUrl: String, name: String, author: String? = nil,
        coverUrl: String? = nil, intro: String? = nil, tocUrl: String, lastChapterTitle: String? = nil,
        addedAt: Date = Date(), group: String? = nil, lastReadChapterIndex: Int? = nil,
        lastReadChapterTitle: String? = nil, lastReadCharacterOffset: Int = 0, lastReadAt: Date? = nil
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
    }
}
