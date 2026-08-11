import Foundation
import BookSourceModel

/// User-added web search engines only -- `WebSearchEngine.defaults` (Bing/Baidu) ship built in and
/// aren't persisted here, matching how the picker in `WebSearchPanelView` shows defaults + this
/// store's contents concatenated rather than seeding the store with copies of the defaults.
public actor WebSearchEngineStore {
    private let store: JSONFileStore<[WebSearchEngine]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [WebSearchEngine] {
        try await store.load() ?? []
    }

    @discardableResult
    public func add(_ engine: WebSearchEngine) async throws -> [WebSearchEngine] {
        var engines = try await all()
        if let idx = engines.firstIndex(where: { $0.id == engine.id }) {
            engines[idx] = engine
        } else {
            engines.append(engine)
        }
        try await store.save(engines)
        return engines
    }

    public func remove(id: String) async throws {
        var engines = try await all()
        engines.removeAll { $0.id == id }
        try await store.save(engines)
    }
}
