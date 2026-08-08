import Foundation

/// A rule that auto-assigns a shelf book to a display group ("tag") when its name/author/intro
/// matches a pattern -- e.g. a rule matching "网游|系统流" tagged "游戏" groups every game-themed
/// book together without the user manually filing each one.
public struct TagGroupRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var groupName: String
    public var pattern: String
    public var enabled: Bool

    public init(id: String = UUID().uuidString, groupName: String, pattern: String, enabled: Bool = true) {
        self.id = id
        self.groupName = groupName
        self.pattern = pattern
        self.enabled = enabled
    }
}
