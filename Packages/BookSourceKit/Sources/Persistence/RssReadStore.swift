import Foundation

/// Tracks which RSS article links have been opened -- keyed globally by link (an RSS article's
/// link is already effectively globally unique, same assumption `RssArticle.id`/`RssFavoriteArticle
/// .id` already make), not per-source, so this stays a single flat set rather than a
/// source-URL-keyed dictionary.
public actor RssReadStore {
    private let store: JSONFileStore<Set<String>>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func readLinks() async throws -> Set<String> {
        try await store.load() ?? []
    }

    public func isRead(_ link: String) async throws -> Bool {
        try await readLinks().contains(link)
    }

    public func markRead(_ link: String) async throws {
        var links = try await readLinks()
        guard links.insert(link).inserted else { return }
        try await store.save(links)
    }
}
