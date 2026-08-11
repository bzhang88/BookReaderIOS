import Foundation
import BookSourceModel

public actor HttpTTSEngineStore {
    private let store: JSONFileStore<[HttpTTSEngine]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [HttpTTSEngine] {
        try await store.load() ?? []
    }

    @discardableResult
    public func add(_ engine: HttpTTSEngine) async throws -> [HttpTTSEngine] {
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
