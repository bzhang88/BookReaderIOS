import Foundation

/// Recently-searched keywords, most recent first -- lets `GlobalSearchView` show a tappable
/// history list (matching Legado's "最近搜索" chips) instead of always starting from a blank
/// search field with no memory of what was searched before.
public actor SearchHistoryStore {
    private let store: JSONFileStore<[String]>
    private let limit: Int

    public init(fileURL: URL, limit: Int = 20) {
        self.store = JSONFileStore(fileURL: fileURL)
        self.limit = limit
    }

    public func recent() async throws -> [String] {
        try await store.load() ?? []
    }

    /// Moves `keyword` to the front if already present rather than leaving a stale duplicate
    /// further down the list, then trims to `limit` -- unbounded history would grow the JSON file
    /// forever for a feature that's only useful for the most recent handful of searches anyway.
    public func record(_ keyword: String) async throws {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var history = try await recent()
        history.removeAll { $0 == trimmed }
        history.insert(trimmed, at: 0)
        if history.count > limit {
            history = Array(history.prefix(limit))
        }
        try await store.save(history)
    }

    public func clear() async throws {
        try await store.save([])
    }
}
