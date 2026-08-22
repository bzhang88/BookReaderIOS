import Foundation

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

    public init(
        id: String = UUID().uuidString, name: String, pattern: String, enabled: Bool = true,
        colorHex: String? = nil, isBold: Bool? = nil, isUnderlined: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.enabled = enabled
        self.colorHex = colorHex
        self.isBold = isBold
        self.isUnderlined = isUnderlined
    }

    public var resolvedIsBold: Bool { isBold ?? true }
    public var resolvedIsUnderlined: Bool { isUnderlined ?? false }
}
