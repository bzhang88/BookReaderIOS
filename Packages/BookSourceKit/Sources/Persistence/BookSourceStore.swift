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

    /// Bulk enable/disable every source at once -- e.g. "disable all, then turn back on just the
    /// ones you actually use" is a much faster workflow than tapping through a hundred rows.
    public func setAllEnabled(_ enabled: Bool) async throws {
        var sources = try await all()
        for i in sources.indices { sources[i].enabled = enabled }
        try await store.save(sources)
    }

    /// Batch group reassignment, keyed by `bookSourceUrl` -- see `ShelfStore.setGroups`'s matching
    /// doc comment for why the value is `String??` (present-but-nil vs. absent-from-the-dictionary
    /// aren't the same thing: only URLs that are actual keys get touched at all, and a present `nil`
    /// value clears that source's group rather than leaving it alone). Used by
    /// `SourceGroupManagementView` to rename/delete a group across every source in it in one write.
    public func setGroups(_ groups: [String: String?]) async throws {
        var sources = try await all()
        for idx in sources.indices {
            if let newGroup = groups[sources[idx].bookSourceUrl] {
                sources[idx].bookSourceGroup = newGroup
            }
        }
        try await store.save(sources)
    }

    public func remove(bookSourceUrl: String) async throws {
        var sources = try await all()
        sources.removeAll { $0.bookSourceUrl == bookSourceUrl }
        try await store.save(sources)
    }
}
