import Foundation
import BookSourceModel

public actor RssSourceStore {
    private let store: JSONFileStore<[RssSource]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [RssSource] {
        try await store.load() ?? []
    }

    @discardableResult
    public func add(_ source: RssSource) async throws -> [RssSource] {
        var sources = try await all()
        if let idx = sources.firstIndex(where: { $0.sourceUrl == source.sourceUrl }) {
            sources[idx] = source
        } else {
            sources.append(source)
        }
        try await store.save(sources)
        return sources
    }

    public func remove(sourceUrl: String) async throws {
        var sources = try await all()
        sources.removeAll { $0.sourceUrl == sourceUrl }
        try await store.save(sources)
    }

    public func setEnabled(sourceUrl: String, enabled: Bool) async throws {
        var sources = try await all()
        guard let idx = sources.firstIndex(where: { $0.sourceUrl == sourceUrl }) else { return }
        sources[idx].enabled = enabled
        try await store.save(sources)
    }
}
