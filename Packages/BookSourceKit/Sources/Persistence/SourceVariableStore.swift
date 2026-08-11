import Foundation

/// Per-source variable storage -- confirmed against Legado_Max's real `BaseSource.setVariable`/
/// `getVariable` that this is a separate runtime key-value store (`CacheManager.put("sourceVariable_
/// ${getKey()}", variable)`), not a field on the book source's own definition, so this mirrors that
/// shape (a dictionary keyed by `bookSourceUrl`) rather than adding a `variable` field to
/// `BookSource` itself. Honest limitation: this app's rule engine doesn't expose a `source.
/// getVariable()`/`setVariable()` JS bridge the way real Legado's does, so a value saved here isn't
/// consumed by anything yet -- this just gives the storage + editor a place to exist, matching how
/// AI provider configuration landed before any feature actually called the API.
public actor SourceVariableStore {
    private let store: JSONFileStore<[String: String]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func variable(bookSourceUrl: String) async throws -> String? {
        try await store.load()?[bookSourceUrl]
    }

    public func setVariable(_ variable: String?, bookSourceUrl: String) async throws {
        var all = try await store.load() ?? [:]
        if let variable, !variable.isEmpty {
            all[bookSourceUrl] = variable
        } else {
            all.removeValue(forKey: bookSourceUrl)
        }
        try await store.save(all)
    }
}
