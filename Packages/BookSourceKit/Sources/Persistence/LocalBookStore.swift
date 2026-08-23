import Foundation

public actor LocalBookStore {
    private let store: JSONFileStore<[LocalBook]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [LocalBook] {
        try await store.load() ?? []
    }

    @discardableResult
    public func add(_ book: LocalBook) async throws -> [LocalBook] {
        var books = try await all()
        books.append(book)
        try await store.save(books)
        return books
    }

    public func remove(id: String) async throws {
        var books = try await all()
        books.removeAll { $0.id == id }
        try await store.save(books)
    }

    /// Replaces an existing local book's title/chapters in place, preserving its `id` -- and so any
    /// bookmarks/reading-progress state keyed off that id -- rather than `add`'s always-append
    /// behavior, which used to produce a second, fully duplicate entry (with orphaned bookmarks
    /// pointing at the now-abandoned original) every time the same file was re-imported. Reading
    /// progress resets: a re-split file can shift chapter boundaries, so a stale
    /// `lastReadChapterIndex` would silently point at the wrong chapter rather than visibly (but
    /// correctly) starting over. A no-op if `id` isn't actually on the shelf.
    public func replaceContent(id: String, title: String, chapters: [LocalChapter]) async throws {
        var books = try await all()
        guard let idx = books.firstIndex(where: { $0.id == id }) else { return }
        books[idx].title = title
        books[idx].chapters = chapters
        books[idx].lastReadChapterIndex = nil
        books[idx].lastReadCharacterOffset = nil
        books[idx].lastReadAt = nil
        try await store.save(books)
    }

    /// `characterOffset` defaults to 0 (start of chapter) rather than being required -- most call
    /// sites are a plain chapter change, where 0 is exactly right; only the periodic/`onDisappear`
    /// position-save calls pass a real mid-chapter value.
    public func updateProgress(id: String, chapterIndex: Int, characterOffset: Int = 0) async throws {
        var books = try await all()
        guard let idx = books.firstIndex(where: { $0.id == id }) else { return }
        books[idx].lastReadChapterIndex = chapterIndex
        books[idx].lastReadCharacterOffset = characterOffset
        books[idx].lastReadAt = Date()
        try await store.save(books)
    }
}
