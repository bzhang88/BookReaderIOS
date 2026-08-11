import Foundation

/// A user-configured dictionary/word-lookup source. Confirmed against Legado_Max's real `DictRule`
/// entity that this is deliberately simple -- not a parallel rule DSL to book sources, just a name
/// plus a URL template and an extraction rule, reusing the exact same `{{key}}`-templated-URL +
/// CSS/JSON-extraction machinery book sources already use (see `DictLookupService`).
public struct DictRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// URL template -- `{{key}}` (and the shared `SearchURLBuilder` machinery's other bindings) get
    /// substituted with the looked-up word.
    public var urlRule: String
    /// A rule-engine extraction string (same DSL as `ruleSearch.name`/etc.) applied to the fetched
    /// response to pull out the definition text/HTML.
    public var showRule: String
    public var enabled: Bool

    public init(id: String = UUID().uuidString, name: String, urlRule: String, showRule: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.urlRule = urlRule
        self.showRule = showRule
        self.enabled = enabled
    }
}
