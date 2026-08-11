import Foundation

/// One cover image URL the user has kept for reuse -- confirmed against Legado_Max's real
/// `CoverGalleryActivity`/`CoverGalleryScreen` that this is a genuine persisted, browsable
/// collection (grouped, DB-backed there), not just an ephemeral search result. Scoped down to a
/// flat list here rather than replicating grouping, which `CoverPickerView`'s single-screen picker
/// doesn't need.
public struct SavedCover: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var url: String
    public var bookName: String
    public var savedAt: Date

    public init(id: String = UUID().uuidString, url: String, bookName: String, savedAt: Date = Date()) {
        self.id = id
        self.url = url
        self.bookName = bookName
        self.savedAt = savedAt
    }
}
