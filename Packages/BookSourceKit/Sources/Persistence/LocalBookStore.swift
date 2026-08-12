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
