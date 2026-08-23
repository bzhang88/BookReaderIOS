import Foundation
import WebBookOrchestrator

public actor RssFavoriteStore {
    private let store: JSONFileStore<[RssFavoriteArticle]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    /// Newest-favorited-first -- matches how a "saved for later" list is actually read (most
    /// recently added closest to hand), not insertion order into the file.
    public func all() async throws -> [RssFavoriteArticle] {
        try await store.load() ?? []
    }

    public func isFavorited(link: String) async throws -> Bool {
        try await all().contains { $0.link == link }
    }

    public func add(_ article: RssFavoriteArticle) async throws {
        var all = try await all()
        guard !all.contains(where: { $0.link == article.link }) else { return }
        all.insert(article, at: 0)
        try await store.save(all)
    }

    public func remove(link: String) async throws {
        var all = try await all()
        all.removeAll { $0.link == link }
        try await store.save(all)
    }
}
