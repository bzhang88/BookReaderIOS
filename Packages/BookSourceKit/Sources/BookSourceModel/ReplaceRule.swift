import Foundation

/// A user-defined content purification rule (e.g. stripping ads/promo text embedded in chapter
/// content) -- distinct from a book source's own built-in `ruleContent.replaceRegex`, which is
/// tied to one specific source's known markup. These are user-authored, reusable across sources
/// (or scoped to just one), matching Legado's separate "替换规则" manager.
public struct ReplaceRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Free-text grouping label -- same "can exist with zero members, independent of any one
    /// rule's own group string" story `BookSource.bookSourceGroup`/`ShelfBook.group` already have;
    /// `ReplaceRuleGroupManagementView` is the matching management screen.
    public var group: String?
    public var pattern: String
    public var replacement: String
    public var isRegex: Bool
    /// Comma/semicolon-separated substrings, matched by plain containment against the current
    /// book's name *or* its source's `bookSourceUrl` -- confirmed against Legado's real
    /// `ReplaceRuleDao` query (`scope LIKE '%'||:name||'%' or scope LIKE '%'||:origin||'%'`): the
    /// whole `scope` string just needs to *contain* the book name or the source URL as a substring,
    /// not equal either one exactly, and not be split/tokenized before matching -- a scope of
    /// `"书名A,书名B"` already matches a book named exactly "书名A" via plain substring containment,
    /// no comma-splitting needed to make that work. `nil`/empty applies to every book on every
    /// source. (This field used to be `scopeSourceUrl`, an exact-URL-only match -- renamed to match
    /// Legado's real field name/semantics, including for round-trip JSON compatibility with real
    /// Legado replace-rule exports.)
    public var scope: String?
    /// Same substring-containment semantics as `scope`, but subtractive: a match here vetoes the
    /// rule regardless of `scope`.
    public var excludeScope: String?
    /// Whether this rule fires against a chapter's title text. Modeled for round-trip fidelity with
    /// real Legado rule files and enforced by `ReplaceRuleApplier`'s `textKind` parameter, but no
    /// call site in this app actually purifies chapter *titles* yet (only content) -- titles are
    /// read by several other places (TOC lists, bookmarks, reading-progress display) that would all
    /// need to agree on using the purified version, a broader consistency change than this field's
    /// own modeling. Defaults `false`, matching that current reality.
    public var scopeTitle: Bool
    /// Defaults `true` -- every existing call site in this app already always purifies chapter
    /// content, so this default preserves that behavior unchanged for rules that predate this field.
    public var scopeContent: Bool
    /// Apply order, ascending -- `ReplaceRuleApplier` sorts by this before running rules, matching
    /// Legado's own `order`-based sequencing (earlier rules' output feeds later ones, so order can
    /// change the result, not just cosmetic list position).
    public var order: Int
    public var enabled: Bool

    public init(
        id: String = UUID().uuidString, name: String, group: String? = nil, pattern: String, replacement: String = "",
        isRegex: Bool = true, scope: String? = nil, excludeScope: String? = nil,
        scopeTitle: Bool = false, scopeContent: Bool = true, order: Int = 0, enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.pattern = pattern
        self.replacement = replacement
        self.isRegex = isRegex
        self.scope = scope
        self.excludeScope = excludeScope
        self.scopeTitle = scopeTitle
        self.scopeContent = scopeContent
        self.order = order
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case id, name, group, pattern, replacement, isRegex, scope
        /// The pre-rename key `scope` replaced -- kept only as a decode-time fallback (see
        /// `init(from:)`), never written by `encode(to:)`.
        case legacyScopeSourceUrl = "scopeSourceUrl"
        case excludeScope, scopeTitle, scopeContent, order, enabled
    }

    /// Custom only for the `scope`/`scopeSourceUrl` migration fallback -- everything else is a
    /// plain lenient decode, same `decodeIfPresent ?? default` shape used throughout this app's
    /// other models for safe Codable migrations (new field, old persisted data missing it).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        group = try container.decodeIfPresent(String.self, forKey: .group)
        pattern = try container.decode(String.self, forKey: .pattern)
        replacement = try container.decodeIfPresent(String.self, forKey: .replacement) ?? ""
        isRegex = try container.decodeIfPresent(Bool.self, forKey: .isRegex) ?? true
        // Prefer the current `scope` key; fall back to the pre-rename `scopeSourceUrl` key so data
        // persisted before this field existed under its Legado-matching name isn't silently
        // dropped -- real, if narrow: `LegadoReplaceRuleImport` (a `legado://import/replace...`
        // link) already writes this field, so already-imported rules could genuinely have it set.
        if let scopeValue = try container.decodeIfPresent(String.self, forKey: .scope) {
            scope = scopeValue
        } else {
            scope = try container.decodeIfPresent(String.self, forKey: .legacyScopeSourceUrl)
        }
        excludeScope = try container.decodeIfPresent(String.self, forKey: .excludeScope)
        scopeTitle = try container.decodeIfPresent(Bool.self, forKey: .scopeTitle) ?? false
        scopeContent = try container.decodeIfPresent(Bool.self, forKey: .scopeContent) ?? true
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    /// Required alongside the custom `init(from:)` above -- `CodingKeys` has a case
    /// (`legacyScopeSourceUrl`) with no matching stored property, which stops `Encodable` synthesis
    /// entirely (not just for the mismatched case), so this has to be written out by hand. Always
    /// writes the current `scope` key, never the legacy one -- every encode from here on moves data
    /// fully onto the new key.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(group, forKey: .group)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(replacement, forKey: .replacement)
        try container.encode(isRegex, forKey: .isRegex)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encodeIfPresent(excludeScope, forKey: .excludeScope)
        try container.encode(scopeTitle, forKey: .scopeTitle)
        try container.encode(scopeContent, forKey: .scopeContent)
        try container.encode(order, forKey: .order)
        try container.encode(enabled, forKey: .enabled)
    }
}
