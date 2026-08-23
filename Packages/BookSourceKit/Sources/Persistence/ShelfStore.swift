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

    /// Full replacement of one book's group membership -- used by the manual multi-select group
    /// picker (`ShelfGroupPickerView`), where the confirmed selection *is* the book's new complete
    /// set of groups, not an addition to whatever it already had.
    public func setGroups(bookUrl: String, to groups: [String]) async throws {
        var books = try await all()
        guard let idx = books.firstIndex(where: { $0.bookUrl == bookUrl }) else { return }
        books[idx].groups = groups
        try await store.save(books)
    }

    /// Batch version of `setGroups(bookUrl:to:)` -- one save instead of one `addOrUpdate` round-trip
    /// per book, matters once a shelf has dozens of books. Used by `ShelfView`'s batch "移动分组"
    /// action: every selected book's groups are replaced with the same chosen set in one write.
    public func setGroups(_ groups: [String: [String]]) async throws {
        var books = try await all()
        for idx in books.indices {
            if let newGroups = groups[books[idx].bookUrl] {
                books[idx].groups = newGroups
            }
        }
        try await store.save(books)
    }

    /// Adds one group to each listed book's *existing* groups (a union, not a replace) -- used by
    /// the "自动分组" tag-rule sweep, which computes one matched group per book but shouldn't wipe
    /// out groups the user assigned manually; a book the sweep matches into "玄幻" while it's also
    /// manually filed under "在读" keeps both after the sweep runs.
    public func addGroupToBooks(_ additions: [String: String]) async throws {
        var books = try await all()
        for idx in books.indices {
            guard let group = additions[books[idx].bookUrl], !books[idx].groups.contains(group) else { continue }
            books[idx].groups.append(group)
        }
        try await store.save(books)
    }

    /// Renames a group across every book that currently has it, preserving each book's other group
    /// memberships -- a book filed under both `oldName` and some unrelated group keeps that other
    /// group after the rename, unlike a naive "replace the whole array with just the new name."
    /// De-dupes afterward in case a book already happened to be in both `oldName` and `newName`.
    public func renameGroupEverywhere(_ oldName: String, to newName: String) async throws {
        var books = try await all()
        for idx in books.indices {
            guard let position = books[idx].groups.firstIndex(of: oldName) else { continue }
            books[idx].groups[position] = newName
            var seen = Set<String>()
            books[idx].groups = books[idx].groups.filter { seen.insert($0).inserted }
        }
        try await store.save(books)
    }

    /// Removes one group from every book that has it, preserving each book's other group
    /// memberships -- matches Legado's own behavior (a group is just a label, not a container the
    /// books live inside, so deleting it ungroups rather than removing the books).
    public func removeGroupEverywhere(_ name: String) async throws {
        var books = try await all()
        for idx in books.indices {
            books[idx].groups.removeAll { $0 == name }
        }
        try await store.save(books)
    }

    /// Overrides just this book's cover image, independent of its source -- lets the user pick a
    /// better-looking cover found on another source (or paste a direct image URL) without actually
    /// switching which source the book reads from (that's `addOrUpdate` replacing the whole entry,
    /// a different operation).
    public func setCoverUrl(bookUrl: String, coverUrl: String) async throws {
        var books = try await all()
        guard let idx = books.firstIndex(where: { $0.bookUrl == bookUrl }) else { return }
        books[idx].coverUrl = coverUrl
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

    /// Refreshes `totalChapterCount` -- called opportunistically wherever a book's real chapter
    /// list is already being fetched (resuming into the reader, switching source), not on its own
    /// schedule. A no-op for a book no longer on the shelf.
    ///
    /// `lastChapterTitle` defaults to `nil`, meaning "leave it alone" -- most callers (resuming into
    /// the reader) only ever know the chapter *count*, not which chapter is actually newest. Real bug
    /// found comparing against Legado: `ShelfView.checkForUpdates()` used to only ever call this
    /// two-arg form, so a successful update-check that found real new chapters bumped the unread
    /// badge but left the shelf row's "最新: …" text showing the old title -- passing the freshly
    /// fetched title through here (only when the caller actually has one) is that missing write path.
    public func updateTotalChapterCount(bookUrl: String, count: Int, lastChapterTitle: String? = nil) async throws {
        var books = try await all()
        guard let idx = books.firstIndex(where: { $0.bookUrl == bookUrl }) else { return }
        books[idx].totalChapterCount = count
        if let lastChapterTitle {
            books[idx].lastChapterTitle = lastChapterTitle
        }
        try await store.save(books)
    }

    /// Toggles `ShelfBook.canUpdate` -- see that field's own doc comment for the `nil`-means-`true`
    /// convention this preserves (passing `true` here writes an explicit `true`, not back to `nil`,
    /// which is fine: both read as "check this book" via `canUpdate ?? true`).
    public func setCanUpdate(bookUrl: String, canUpdate: Bool) async throws {
        var books = try await all()
        guard let idx = books.firstIndex(where: { $0.bookUrl == bookUrl }) else { return }
        books[idx].canUpdate = canUpdate
        try await store.save(books)
    }
}
