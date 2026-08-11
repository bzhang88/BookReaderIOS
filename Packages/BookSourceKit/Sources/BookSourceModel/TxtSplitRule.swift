import Foundation

/// A named, user-managed chapter-heading pattern for splitting locally-imported .txt files --
/// `TxtChapterSplitter`'s single hardcoded `defaultPattern` covers the most common Chinese novel
/// convention ("第X章"), but real files use other conventions too (numbered-only headings,
/// "Chapter X", bracketed titles, etc.), so this lets the user maintain a small library of
/// alternatives instead of being stuck with one regex.
public struct TxtSplitRule: Codable, Equatable, Identifiable, Sendable {
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
