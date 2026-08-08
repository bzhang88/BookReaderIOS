import Foundation

/// A regex pattern to visually call out within reading content (e.g. flagging character names, or
/// a phrase the reader wants to track) -- distinct from `ReplaceRule`, which removes/rewrites text
/// rather than just marking it.
public struct HighlightRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var pattern: String
    public var enabled: Bool

    public init(id: String = UUID().uuidString, name: String, pattern: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.enabled = enabled
    }
}
