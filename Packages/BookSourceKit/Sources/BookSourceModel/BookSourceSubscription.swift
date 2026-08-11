import Foundation

/// A book-source JSON URL the user wants to periodically re-check for updates -- distinct from a
/// one-off "从网址导入" (item #6 in this session's roadmap), which fetches once and is forgotten.
/// A subscription is remembered so its URL can be re-fetched again later without the user having to
/// retype or re-find it. No automatic background scheduling in this first increment (that needs
/// `BackgroundTasks` entitlements and real-device testing this Windows-only dev setup can't verify)
/// -- refreshing is a manual "刷新" action the user triggers themselves.
public struct BookSourceSubscription: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var url: String
    public var lastUpdatedAt: Date?

    public init(id: String = UUID().uuidString, name: String, url: String, lastUpdatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.lastUpdatedAt = lastUpdatedAt
    }
}
