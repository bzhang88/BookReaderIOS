import Foundation

/// A subscribed RSS/Atom feed. Much simpler than `BookSource` -- no scraping rules, since a real
/// feed URL is self-describing XML that `RssFeedParser` parses directly.
public struct RssSource: Codable, Equatable, Identifiable, Sendable {
    public var sourceUrl: String
    public var sourceName: String
    public var sourceGroup: String?
    public var enabled: Bool

    public var id: String { sourceUrl }

    public init(sourceUrl: String, sourceName: String, sourceGroup: String? = nil, enabled: Bool = true) {
        self.sourceUrl = sourceUrl
        self.sourceName = sourceName
        self.sourceGroup = sourceGroup
        self.enabled = enabled
    }
}
