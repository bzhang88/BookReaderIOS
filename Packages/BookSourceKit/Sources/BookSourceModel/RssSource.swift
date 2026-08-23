import Foundation

/// A subscribed RSS/Atom feed. Much simpler than `BookSource` -- no scraping rules, since a real
/// feed URL is self-describing XML that `RssFeedParser` parses directly. Real gap found comparing
/// against Legado's own `RssSource`: that model also carries a scraping rule set
/// (`ruleArticles`/`ruleTitle`/...) this app deliberately doesn't implement (see this project's own
/// scope notes -- a real XML parser handles standard RSS/Atom without needing per-source scraping
/// rules at all, and building a second HTML-scraping rule engine just for RSS is out of scope), but
/// `sortUrl`/`loginUrl` are pure data-model gaps with no rule-engine dependency, so those are added.
public struct RssSource: Codable, Equatable, Identifiable, Sendable {
    public var sourceUrl: String
    public var sourceName: String
    public var sourceGroup: String?
    public var enabled: Bool
    /// Multi-line `分类名::URL` list (or bare URLs, one per line) -- same convention and same
    /// `ExploreKindParser` `BookSource.exploreUrl` already uses. Lets one subscription offer more
    /// than one feed (e.g. a site's separate "科技"/"财经" channels) as switchable category tabs
    /// instead of always only ever fetching `sourceUrl` itself. `nil`/blank means "just one feed."
    public var sortUrl: String?
    /// A plain `http(s)` login page URL -- reuses `SourceLoginView`'s existing WebView+cookie-capture
    /// flow (built for `BookSource`) via a throwaway `BookSource` wrapper carrying only this URL,
    /// rather than duplicating that whole mechanism for RSS sources. `nil` means no login gate.
    public var loginUrl: String?

    public var id: String { sourceUrl }

    public init(
        sourceUrl: String, sourceName: String, sourceGroup: String? = nil, enabled: Bool = true,
        sortUrl: String? = nil, loginUrl: String? = nil
    ) {
        self.sourceUrl = sourceUrl
        self.sourceName = sourceName
        self.sourceGroup = sourceGroup
        self.enabled = enabled
        self.sortUrl = sortUrl
        self.loginUrl = loginUrl
    }
}
