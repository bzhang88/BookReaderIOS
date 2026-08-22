import Foundation

/// Bridges real Legado JSON shapes (confirmed against `Legado_Max`'s actual entity field names,
/// not guessed) for `legado://import/...` types whose field names don't already match this app's
/// own simpler models. `bookSource`/`dictRule`/`rssSource` don't need one of these -- their real
/// field names already match this app's model 1:1, so `JSONDecoder` reads them directly.

/// Real `ReplaceRule.kt` fields: `id` (Int64), `name`, `group`, `pattern`, `replacement`, `scope`,
/// `excludeScope`, `scopeTitle`, `scopeContent`, `order`, `isEnabled`, `isRegex`, plus one this app
/// still doesn't model (`timeoutMillisecond` -- a per-execution regex timeout `NSRegularExpression`
/// has no simple built-in way to enforce, and a real one would need running the regex on a
/// cancellable background queue; not attempted here, same "decode what v1 uses, ignore the rest"
/// leniency `BookSource` itself already relies on for its own still-unmodeled fields).
public struct LegadoReplaceRuleImport: Decodable {
    public var id: Int64?
    public var name: String
    public var group: String?
    public var pattern: String
    public var replacement: String?
    public var scope: String?
    public var excludeScope: String?
    public var scopeTitle: Bool?
    public var scopeContent: Bool?
    public var order: Int?
    public var isEnabled: Bool?
    public var isRegex: Bool?

    /// A Legado numeric `id` maps to the same string every time, so re-importing the same rule
    /// updates it in place (matches every store's existing `add` = upsert-by-id semantics) instead
    /// of piling up duplicates with fresh random UUIDs on every import.
    public func toReplaceRule() -> ReplaceRule {
        ReplaceRule(
            id: id.map(String.init) ?? UUID().uuidString,
            name: name,
            group: group,
            pattern: pattern,
            replacement: replacement ?? "",
            isRegex: isRegex ?? true,
            scope: scope,
            excludeScope: excludeScope,
            scopeTitle: scopeTitle ?? false,
            scopeContent: scopeContent ?? true,
            order: order ?? 0,
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
