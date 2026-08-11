import Foundation

/// Registered shelf group names, independent of which (if any) books currently carry them.
///
/// `ShelfBook.group` alone can only represent groups that have at least one book in them right
/// now -- a group becomes invisible the moment its last book is moved out or removed, and there's
/// no way to create an empty group ahead of time to file books into later (both real gaps compared
/// to Legado's own group management, which supports empty groups). This store is the small piece
/// of state that fixes that: a name written here persists on its own, and `ShelfManagementView`
/// merges it with whatever names are still in live use across `ShelfStore` to show the complete
/// picture.
public actor ShelfGroupStore {
    private let store: JSONFileStore<[String]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [String] {
        try await store.load() ?? []
    }

    public func add(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var groups = try await all()
        guard !groups.contains(trimmed) else { return }
        groups.append(trimmed)
        try await store.save(groups)
    }

    /// Renames a registered group -- a no-op silently becomes an `add` if `oldName` was never
    /// actually registered (e.g. it only ever existed implicitly via book assignments), so renaming
    /// still works for groups that predate this store.
    public func rename(_ oldName: String, to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var groups = try await all()
        groups.removeAll { $0 == oldName || $0 == trimmed }
        groups.append(trimmed)
        try await store.save(groups)
    }

    public func remove(_ name: String) async throws {
        var groups = try await all()
        groups.removeAll { $0 == name }
        try await store.save(groups)
    }
}
