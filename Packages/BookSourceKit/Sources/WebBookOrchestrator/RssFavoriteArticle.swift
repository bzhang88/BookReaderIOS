import Foundation

/// A saved-for-later RSS article -- carries its own display fields (not just a link) so the
/// favorites list can render without re-fetching the source feed, matching `Bookmark`'s own
/// "self-contained enough to display standalone" shape.
public struct RssFavoriteArticle: Codable, Equatable, Identifiable, Sendable {
    public var link: String
    public var title: String
    public var sourceUrl: String
    public var sourceName: String
    public var pubDate: String?
    public var summary: String?
    public var savedAt: Date

    public var id: String { link }

    public init(
        link: String, title: String, sourceUrl: String, sourceName: String,
        pubDate: String? = nil, summary: String? = nil, savedAt: Date = Date()
    ) {
        self.link = link
        self.title = title
        self.sourceUrl = sourceUrl
        self.sourceName = sourceName
        self.pubDate = pubDate
        self.summary = summary
        self.savedAt = savedAt
    }
}
