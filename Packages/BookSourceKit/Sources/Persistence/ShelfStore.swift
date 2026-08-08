import Foundation

public actor ShelfStore {
    private let store: JSONFileStore<[ShelfBook]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [ShelfBook] {
        try await store.load() ?? []
    }

    public func book(bookUrl: String) async throws -> ShelfBook? {
        try await all().first { $0.bookUrl == bookUrl }
    }

    @discardableResult
    public func addOrUpdate(_ book: ShelfBook) async throws -> [ShelfBook] {
        var books = try await all()
        if let idx = books.firstIndex(where: { $0.bookUrl == book.bookUrl }) {
            books[idx] = book
        } else {
            books.append(book)
        }
        try await store.save(books)
        return books
    }

    @discardableResult
    public func remove(bookUrl: String) async throws -> [ShelfBook] {
        var books = try await all()
        books.removeAll { $0.bookUrl == bookUrl }
        try await store.save(books)
        return books
    }

    /// Applies a batch of tag-group matches (bookUrl -> group name) in one save rather than one
    /// `addOrUpdate` round-trip per book -- matters once a shelf has dozens of books.
    public func setGroups(_ groups: [String: String?]) async throws {
        var books = try await all()
        for idx in books.indices {
            if let newGroup = groups[books[idx].bookUrl] {
                books[idx].group = newGroup
            }
        }
        try await store.save(books)
    }

    /// Records exact resume position — the one piece of state Phase 5's acceptance test
    /// (force-quit, relaunch days later, resume exactly where left off) actually depends on.
    public func updateProgress(
        bookUrl: String, chapterIndex: Int, chapterTitle: String?, characterOffset: Int
    ) async throws {
        var books = try await all()
        guard let idx = books.firstIndex(where: { $0.bookUrl == bookUrl }) else { return }
        books[idx].lastReadChapterIndex = chapterIndex
        books[idx].lastReadChapterTitle = chapterTitle
        books[idx].lastReadCharacterOffset = characterOffset
        books[idx].lastReadAt = Date()
        try await store.save(books)
    }
}
