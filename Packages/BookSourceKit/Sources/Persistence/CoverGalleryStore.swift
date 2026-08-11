import Foundation
import BookSourceModel

/// Persists covers the user has picked before so they can be reused across books without
/// re-searching -- populated implicitly (see `CoverPickerView`: every cover actually applied to a
/// book gets saved here), not through a separate explicit "save to gallery" step.
public actor CoverGalleryStore {
    private let store: JSONFileStore<[SavedCover]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    /// Most-recently-used first -- a browsable gallery is more useful ordered by recency than
    /// insertion order once it has more than a handful of entries.
    public func all() async throws -> [SavedCover] {
        try await store.load()?.sorted { $0.savedAt > $1.savedAt } ?? []
    }

    /// Re-picking a cover URL that's already saved just bumps its `savedAt`/`bookName` rather than
    /// piling up duplicate entries for the exact same image.
    @discardableResult
    public func add(_ cover: SavedCover) async throws -> [SavedCover] {
        var covers = try await store.load() ?? []
        if let idx = covers.firstIndex(where: { $0.url == cover.url }) {
            covers[idx] = cover
        } else {
            covers.append(cover)
        }
        try await store.save(covers)
        return covers
    }

    public func remove(id: String) async throws {
        var covers = try await store.load() ?? []
        covers.removeAll { $0.id == id }
        try await store.save(covers)
    }
}
