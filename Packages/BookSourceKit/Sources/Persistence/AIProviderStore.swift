import Foundation
import BookSourceModel

public actor AIProviderStore {
    private let store: JSONFileStore<[AIProvider]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [AIProvider] {
        try await store.load() ?? []
    }

    @discardableResult
    public func add(_ provider: AIProvider) async throws -> [AIProvider] {
        var providers = try await all()
        if let idx = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[idx] = provider
        } else {
            providers.append(provider)
        }
        try await store.save(providers)
        return providers
    }

    public func remove(id: String) async throws {
        var providers = try await all()
        providers.removeAll { $0.id == id }
        try await store.save(providers)
    }
}
