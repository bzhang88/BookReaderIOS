import Foundation

/// Which part of a chapter a `HighlightRule` applies to -- matches Legado's own `targetScope`
/// (`TARGET_ALL`/`TARGET_TITLE`/`TARGET_BODY`). Raw `Int` (not just the enum) is what's actually
/// stored on `HighlightRule`, for the same reason every other migration-sensitive field here is
/// `Optional` rather than this enum directly: a `nil`/unrecognized raw value must still decode
/// successfully as "全部" rather than failing the whole rule's decode.
public enum HighlightTargetScope: Int, CaseIterable, Sendable {
    case all = 0
    case title = 1
    case body = 2
}

/// A regex pattern to visually call out within reading content (e.g. flagging character names, or
/// a phrase the reader wants to track) -- distinct from `ReplaceRule`, which removes/rewrites text
/// rather than just marking it.
public struct HighlightRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var pattern: String
    public var enabled: Bool
    /// A `#RRGGBB` string, resolved to a real color only at the app-target rendering layer (this
    /// package has no SwiftUI dependency). `nil` falls back to the reader's original hardcoded
    /// orange, both for a rule created before this field existed and for one where the user never
    /// picked a color.
    public var colorHex: String?
    /// `Optional`, not a plain `Bool` defaulted to `true` in the memberwise init -- a non-optional
    /// field with only an `init` default throws on synthesized `Decodable` when decoding any
    /// `highlight_rules.json` written before this field existed (same migration-safety shape this
    /// project has hit before; see `ShelfBook.canUpdate`'s doc comment). `nil` reads as `true`,
    /// matching every highlight rule's appearance before this field existed.
    public var isBold: Bool?
    /// Same `nil`-is-the-old-default convention as `isBold`, but `nil` reads as `false` here --
    /// underlining wasn't part of the original hardcoded style.
    public var isUnderlined: Bool?
    /// `nil` for "no group"/a rule saved before this field existed -- same convention as
    /// `ReplaceRule.group`.
    public var group: String?
    /// Raw `HighlightTargetScope`, `nil` reading as `.all` -- see that enum's own doc comment.
    public var targetScope: Int?

    public init(
        id: String = UUID().uuidString, name: String, pattern: String, enabled: Bool = true,
        colorHex: String? = nil, isBold: Bool? = nil, isUnderlined: Bool? = nil, group: String? = nil,
        targetScope: HighlightTargetScope? = nil
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.enabled = enabled
        self.colorHex = colorHex
        self.isBold = isBold
        self.isUnderlined = isUnderlined
        self.group = group
        self.targetScope = targetScope?.rawValue
    }

    public var resolvedIsBold: Bool { isBold ?? true }
    public var resolvedIsUnderlined: Bool { isUnderlined ?? false }
    public var resolvedTargetScope: HighlightTargetScope {
        targetScope.flatMap(HighlightTargetScope.init(rawValue:)) ?? .all
    }

    /// Whether this rule should be considered when styling a title-line span vs a body-paragraph
    /// span -- `.all` matches both, `.title`/`.body` match only their own.
    public func applies(toTitle isTitle: Bool) -> Bool {
        switch resolvedTargetScope {
        case .all: return true
        case .title: return isTitle
        case .body: return !isTitle
        }
    }
}
