import Foundation
import BookSourceModel

/// Persisted collection of imported 书源. Importing is upsert-by-`bookSourceUrl` (the source's
/// own primary key), matching how real book-source files get re-imported/updated in practice —
/// re-importing the same file (e.g. after the maintainer fixes a rule) should update in place,
/// not duplicate.
public actor BookSourceStore {
    private let store: JSONFileStore<[BookSource]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [BookSource] {
        try await store.load() ?? []
    }

    public func enabled() async throws -> [BookSource] {
        try await all().filter(\.enabled)
    }

    /// Imports (inserting or updating by `bookSourceUrl`) a batch of sources, as decoded from one
    /// real-world book-source JSON file (which is usually an array of many sources).
    /// Returns (inserted, updated) counts.
    @discardableResult
    public func importSources(_ newSources: [BookSource]) async throws -> (inserted: Int, updated: Int) {
        var existing = try await all()
        var indexByUrl: [String: Int] = [:]
        for (i, source) in existing.enumerated() { indexByUrl[source.bookSourceUrl] = i }

        var inserted = 0
        var updated = 0
        for source in newSources {
            if let idx = indexByUrl[source.bookSourceUrl] {
                existing[idx] = source
                updated += 1
            } else {
                indexByUrl[source.bookSourceUrl] = existing.count
                existing.append(source)
                inserted += 1
            }
        }
        try await store.save(existing)
        return (inserted, updated)
    }

    public func setEnabled(bookSourceUrl: String, enabled: Bool) async throws {
        var sources = try await all()
        guard let idx = sources.firstIndex(where: { $0.bookSourceUrl == bookSourceUrl }) else { return }
        sources[idx].enabled = enabled
        try await store.save(sources)
    }

    public func remove(bookSourceUrl: String) async throws {
        var sources = try await all()
        sources.removeAll { $0.bookSourceUrl == bookSourceUrl }
        try await store.save(sources)
    }
}
