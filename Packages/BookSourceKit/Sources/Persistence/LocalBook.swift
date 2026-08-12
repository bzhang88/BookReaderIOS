import Foundation

/// One chapter of a locally-imported plain-text novel. Unlike `ShelfBook` (which points at a
/// network book source and fetches chapter text on demand), a local book's chapter text is fully
/// known at import time -- there is no source to re-fetch from -- so it's stored directly rather
/// than as a URL/rule pair.
public struct LocalChapter: Codable, Equatable, Sendable {
    public var title: String
    public var text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

/// A novel imported from a local .txt file, split into chapters at import time by
/// `TxtChapterSplitter`. Kept as its own list rather than merged into `ShelfBook` -- `ShelfBook`'s
/// schema assumes a network book source (non-optional `bookSourceUrl`/`bookUrl`/`tocUrl`), and
/// retrofitting it to also represent local-only books would mean making those required fields
/// optional and updating every existing consumer (change-source, resume-reading, etc.) just to
/// accommodate a case that doesn't apply to them.
public struct LocalBook: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var addedAt: Date
    public var chapters: [LocalChapter]
    public var lastReadChapterIndex: Int?
    public var lastReadAt: Date?
    /// Character offset into `lastReadChapterIndex`'s text -- optional (not defaulted to 0) so a
    /// `local_books.json` saved before this field existed still decodes fine (Swift's synthesized
    /// `Decodable` requires a key to be present unless the property type itself is Optional; a
    /// non-optional field with only a memberwise-init default would fail to decode old files
    /// missing this key entirely).
    public var lastReadCharacterOffset: Int?

    public init(
        id: String = UUID().uuidString, title: String, addedAt: Date = Date(), chapters: [LocalChapter],
        lastReadChapterIndex: Int? = nil, lastReadAt: Date? = nil, lastReadCharacterOffset: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.addedAt = addedAt
        self.chapters = chapters
        self.lastReadChapterIndex = lastReadChapterIndex
        self.lastReadAt = lastReadAt
        self.lastReadCharacterOffset = lastReadCharacterOffset
    }
}
