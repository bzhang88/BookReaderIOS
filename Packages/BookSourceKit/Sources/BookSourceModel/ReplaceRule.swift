import Foundation

/// A user-defined content purification rule (e.g. stripping ads/promo text embedded in chapter
/// content) -- distinct from a book source's own built-in `ruleContent.replaceRegex`, which is
/// tied to one specific source's known markup. These are user-authored, reusable across sources
/// (or scoped to just one), matching Legado's separate "替换规则" manager.
public struct ReplaceRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var pattern: String
    public var replacement: String
    public var isRegex: Bool
    /// `nil` applies to every source; otherwise only chapters fetched from this exact source.
    public var scopeSourceUrl: String?
    public var enabled: Bool

    public init(
        id: String = UUID().uuidString, name: String, pattern: String, replacement: String = "",
        isRegex: Bool = true, scopeSourceUrl: String? = nil, enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.replacement = replacement
        self.isRegex = isRegex
        self.scopeSourceUrl = scopeSourceUrl
        self.enabled = enabled
    }
}
