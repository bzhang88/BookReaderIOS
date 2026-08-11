import Foundation

/// Bridges real Legado JSON shapes (confirmed against `Legado_Max`'s actual entity field names,
/// not guessed) for `legado://import/...` types whose field names don't already match this app's
/// own simpler models. `bookSource`/`dictRule`/`rssSource` don't need one of these -- their real
/// field names already match this app's model 1:1, so `JSONDecoder` reads them directly.

/// Real `ReplaceRule.kt` fields: `id` (Int64), `name`, `pattern`, `replacement`, `scope`,
/// `isEnabled`, `isRegex`, plus several this app doesn't model (`group`, `scopeTitle`,
/// `scopeContent`, `excludeScope`, `timeoutMillisecond`, `order`) that are simply dropped, the same
/// "decode what v1 uses, ignore the rest" leniency `BookSource` itself already relies on.
public struct LegadoReplaceRuleImport: Decodable {
    public var id: Int64?
    public var name: String
    public var pattern: String
    public var replacement: String?
    public var scope: String?
    public var isEnabled: Bool?
    public var isRegex: Bool?

    /// A Legado numeric `id` maps to the same string every time, so re-importing the same rule
    /// updates it in place (matches every store's existing `add` = upsert-by-id semantics) instead
    /// of piling up duplicates with fresh random UUIDs on every import.
    public func toReplaceRule() -> ReplaceRule {
        ReplaceRule(
            id: id.map(String.init) ?? UUID().uuidString,
            name: name,
            pattern: pattern,
            replacement: replacement ?? "",
            isRegex: isRegex ?? true,
            scopeSourceUrl: scope,
            enabled: isEnabled ?? true
        )
    }
}

/// Real `TxtTocRule.kt` fields: `id` (Int64), `name`, `rule` (this app's `pattern`), `enable` (this
/// app's `enabled`), plus `replacement`/`example`/`serialNumber` this app doesn't model.
public struct LegadoTxtTocRuleImport: Decodable {
    public var id: Int64?
    public var name: String
    public var rule: String
    public var enable: Bool?

    public func toTxtSplitRule() -> TxtSplitRule {
        TxtSplitRule(
            id: id.map(String.init) ?? UUID().uuidString,
            name: name,
            pattern: rule,
            enabled: enable ?? true
        )
    }
}
