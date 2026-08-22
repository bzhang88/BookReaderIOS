import Foundation

/// A single "书源" (book source) — the rules for scraping one novel website.
/// Mirrors Legado's `BookSource` JSON shape closely enough to import real-world source files;
/// fields Legado has that this v1 doesn't use (login, sync, cover-decode JS, ...) are simply
/// dropped by `Decodable` rather than modeled.
public struct BookSource: Codable, Equatable, Identifiable {
    public var bookSourceUrl: String
    public var bookSourceName: String
    public var bookSourceGroup: String?
    /// 0 = text, 1 = audio, 2 = image, 3 = file, 4 = video. Only text (0) is supported in v1.
    public var bookSourceType: Int
    public var header: String?
    public var enabled: Bool
    public var enabledExplore: Bool
    public var searchUrl: String?
    public var exploreUrl: String?
    public var weight: Int
    /// Where to send the user to log in -- either a plain absolute URL (loaded in a WebView so the
    /// user logs in through the site's own real page, same as Legado's WebView login fallback) or a
    /// `@js:`/`<js>` script (a login flow driven entirely by JS, which this app doesn't execute --
    /// see `hasWebLoginURL`).
    public var loginUrl: String?
    /// A JSON-array-shaped string describing a login form's fields (Legado's `RowUi` list) --
    /// decoded and kept for round-trip fidelity with real book source files, but this app doesn't
    /// yet render a form from it (see `hasWebLoginURL`'s doc comment: WebView login covers the same
    /// need without needing to model Legado's JS-driven dynamic form UI).
    public var loginUi: String?

    public var ruleSearch: SearchRule?
    public var ruleExplore: ExploreRule?
    public var ruleBookInfo: BookInfoRule?
    public var ruleToc: TocRule?
    public var ruleContent: ContentRule?

    /// A short, user-visible annotation about this source -- round-trips real book source files
    /// that already have one, and is also where `SourceCheckView`'s own check results get appended
    /// (matching Legado's real `CheckSourceService`, which writes an `// Error: ...` block into this
    /// same field so a failing source stays visibly annotated in the list rather than the check
    /// result only existing for as long as the check screen is open).
    public var bookSourceComment: String?
    /// Milliseconds the most recent successful check took to get a response -- matching Legado's own
    /// `BookSource.respondTime`, written by `SourceCheckView` and used to sort the source list by
    /// real-world speed instead of only by name/weight.
    public var respondTime: Int?
    /// Epoch milliseconds this source was last imported or edited -- matching Legado's
    /// `BookSource.lastUpdateTime` convention (milliseconds, not seconds, for direct round-trip
    /// compatibility with real book source files).
    public var lastUpdateTime: Int64?
    /// Manual drag-reorder position within the source list -- matching Legado's own `customOrder`.
    /// Lower sorts first; `0` (the default for every source that predates this field, and for any
    /// newly-added one until the user actually reorders) means "wherever the list's other sort mode
    /// would naturally put it," not literally "always first."
    public var customOrder: Int

    public var id: String { bookSourceUrl }

    public var isTextSource: Bool { bookSourceType == 0 }

    public init(
        bookSourceUrl: String,
        bookSourceName: String,
        bookSourceGroup: String? = nil,
        bookSourceType: Int = 0,
        header: String? = nil,
        enabled: Bool = true,
        enabledExplore: Bool = true,
        searchUrl: String? = nil,
        exploreUrl: String? = nil,
        weight: Int = 0,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        ruleSearch: SearchRule? = nil,
        ruleExplore: ExploreRule? = nil,
        ruleBookInfo: BookInfoRule? = nil,
        ruleToc: TocRule? = nil,
        ruleContent: ContentRule? = nil,
        bookSourceComment: String? = nil,
        respondTime: Int? = nil,
        lastUpdateTime: Int64? = nil,
        customOrder: Int = 0
    ) {
        self.bookSourceUrl = bookSourceUrl
        self.bookSourceName = bookSourceName
        self.bookSourceGroup = bookSourceGroup
        self.bookSourceType = bookSourceType
        self.header = header
        self.enabled = enabled
        self.enabledExplore = enabledExplore
        self.searchUrl = searchUrl
        self.exploreUrl = exploreUrl
        self.weight = weight
        self.loginUrl = loginUrl
        self.loginUi = loginUi
        self.ruleSearch = ruleSearch
        self.ruleExplore = ruleExplore
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
        self.bookSourceComment = bookSourceComment
        self.respondTime = respondTime
        self.lastUpdateTime = lastUpdateTime
        self.customOrder = customOrder
    }

    enum CodingKeys: String, CodingKey {
        case bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType, header
        case enabled, enabledExplore, searchUrl, exploreUrl, weight
        case loginUrl, loginUi
        case ruleSearch, ruleExplore, ruleBookInfo, ruleToc, ruleContent
        case bookSourceComment, respondTime, lastUpdateTime, customOrder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bookSourceUrl = try container.decode(String.self, forKey: .bookSourceUrl)
        bookSourceName = try container.decodeIfPresent(String.self, forKey: .bookSourceName) ?? ""
        bookSourceGroup = try container.decodeIfPresent(String.self, forKey: .bookSourceGroup)
        bookSourceType = try container.decodeIfPresent(Int.self, forKey: .bookSourceType) ?? 0
        header = try container.decodeIfPresent(String.self, forKey: .header)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        enabledExplore = try container.decodeIfPresent(Bool.self, forKey: .enabledExplore) ?? true
        searchUrl = try container.decodeIfPresent(String.self, forKey: .searchUrl)
        exploreUrl = try container.decodeIfPresent(String.self, forKey: .exploreUrl)
        weight = try container.decodeIfPresent(Int.self, forKey: .weight) ?? 0
        loginUrl = try container.decodeIfPresent(String.self, forKey: .loginUrl)
        loginUi = try container.decodeIfPresent(String.self, forKey: .loginUi)
        ruleSearch = try container.decodeIfPresent(SearchRule.self, forKey: .ruleSearch)
        ruleExplore = try container.decodeIfPresent(ExploreRule.self, forKey: .ruleExplore)
        ruleBookInfo = try container.decodeIfPresent(BookInfoRule.self, forKey: .ruleBookInfo)
        ruleToc = try container.decodeIfPresent(TocRule.self, forKey: .ruleToc)
        ruleContent = try container.decodeIfPresent(ContentRule.self, forKey: .ruleContent)
        bookSourceComment = try container.decodeIfPresent(String.self, forKey: .bookSourceComment)
        respondTime = try container.decodeIfPresent(Int.self, forKey: .respondTime)
        lastUpdateTime = try container.decodeIfPresent(Int64.self, forKey: .lastUpdateTime)
        customOrder = try container.decodeIfPresent(Int.self, forKey: .customOrder) ?? 0
    }

    /// A default desktop-Chrome UA — real book sources routinely 403 requests with no
    /// `User-Agent` at all (a dead giveaway of a non-browser client), so one is always sent
    /// unless the source's own `header` field overrides it.
    public static let defaultUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    /// True when `loginUrl` is something a WebView can load directly -- a plain absolute http(s)
    /// address -- rather than one of the `@js:`/`<js>`-prefixed script forms the same field can
    /// also hold (mirroring the convention other JS-bearing rule fields use elsewhere in this
    /// format), which this app doesn't execute. Sources with only a script-driven login report as
    /// not loggable rather than a WebView trying to navigate to literal JS source text as a URL.
    public var hasWebLoginURL: Bool {
        guard let loginUrl, !loginUrl.isEmpty else { return false }
        return loginUrl.hasPrefix("http://") || loginUrl.hasPrefix("https://")
    }

    /// Parses `header` (a JSON-object-shaped string, e.g. `{"User-Agent": "..."}`) into a plain
    /// dictionary for building requests, merged over a default User-Agent. Malformed or missing
    /// header JSON degrades to just the default header rather than failing — a broken `header`
    /// field shouldn't block using an otherwise working source.
    public func parsedHeaders() -> [String: String] {
        var result: [String: String] = ["User-Agent": Self.defaultUserAgent]
        guard let header, let data = header.data(using: .utf8) else { return result }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return result }
        for (key, value) in object {
            if let stringValue = value as? String {
                result[key] = stringValue
            } else if let convertible = value as? CustomStringConvertible {
                result[key] = convertible.description
            }
        }
        return result
    }
}
