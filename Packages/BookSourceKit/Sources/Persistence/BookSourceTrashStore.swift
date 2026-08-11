import Foundation
import BookSourceModel

/// Where deleted book sources go instead of being gone for good -- swiping to delete a row in a
/// long, similar-looking list of sources is easy to fat-finger, so `SourceLibraryView`'s delete
/// moves a source here rather than calling `BookSourceStore.remove` directly. Upserts by
/// `bookSourceUrl` just like `BookSourceStore.importSources`, so re-deleting the same source twice
/// (without restoring in between) updates the trashed copy rather than leaving a stale duplicate.
public actor BookSourceTrashStore {
    private let store: JSONFileStore<[BookSource]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [BookSource] {
        try await store.load() ?? []
    }

    @discardableResult
    public func add(_ source: BookSource) async throws -> [BookSource] {
        var sources = try await all()
        if let idx = sources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) {
            sources[idx] = source
        } else {
            sources.append(source)
        }
        try await store.save(sources)
        return sources
    }

    public func remove(bookSourceUrl: String) async throws {
        var sources = try await all()
        sources.removeAll { $0.bookSourceUrl == bookSourceUrl }
        try await store.save(sources)
    }

    public func removeAll() async throws {
        try await store.save([])
    }
}
