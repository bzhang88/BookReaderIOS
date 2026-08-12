import Foundation

public actor BookmarkStore {
    private let store: JSONFileStore<[Bookmark]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [Bookmark] {
        try await store.load() ?? []
    }

    public func bookmarks(bookIdentifier: String) async throws -> [Bookmark] {
        try await all().filter { $0.bookIdentifier == bookIdentifier }
    }

    public func isBookmarked(bookIdentifier: String, chapterIndex: Int) async throws -> Bool {
        try await all().contains { $0.bookIdentifier == bookIdentifier && $0.chapterIndex == chapterIndex }
    }

    @discardableResult
    public func add(_ bookmark: Bookmark) async throws -> [Bookmark] {
        var bookmarks = try await all()
        bookmarks.append(bookmark)
        try await store.save(bookmarks)
        return bookmarks
    }

    /// Replaces an existing bookmark by `id` (falls back to appending if it's somehow not found) --
    /// used to edit a bookmark's `note` after the fact. `add` always appends, so calling it a second
    /// time with the same bookmark's id would create a duplicate rather than editing it in place.
    @discardableResult
    public func update(_ bookmark: Bookmark) async throws -> [Bookmark] {
        var bookmarks = try await all()
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[index] = bookmark
        } else {
            bookmarks.append(bookmark)
        }
        try await store.save(bookmarks)
        return bookmarks
    }

    /// Removes whatever bookmark exists for this exact (book, chapter) pair -- used by the
    /// reader's toggle button, which only ever has one bookmark per chapter to remove.
    public func remove(bookIdentifier: String, chapterIndex: Int) async throws {
        var bookmarks = try await all()
        bookmarks.removeAll { $0.bookIdentifier == bookIdentifier && $0.chapterIndex == chapterIndex }
        try await store.save(bookmarks)
    }

    public func remove(id: String) async throws {
        var bookmarks = try await all()
        bookmarks.removeAll { $0.id == id }
        try await store.save(bookmarks)
    }
}
