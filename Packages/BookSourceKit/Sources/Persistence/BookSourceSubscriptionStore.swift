import Foundation
import BookSourceModel

public actor BookSourceSubscriptionStore {
    private let store: JSONFileStore<[BookSourceSubscription]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [BookSourceSubscription] {
        try await store.load() ?? []
    }

    @discardableResult
    public func add(_ subscription: BookSourceSubscription) async throws -> [BookSourceSubscription] {
        var subscriptions = try await all()
        if let idx = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
            subscriptions[idx] = subscription
        } else {
            subscriptions.append(subscription)
        }
        try await store.save(subscriptions)
        return subscriptions
    }

    public func remove(id: String) async throws {
        var subscriptions = try await all()
        subscriptions.removeAll { $0.id == id }
        try await store.save(subscriptions)
    }

    public func setLastUpdatedAt(id: String, date: Date) async throws {
        var subscriptions = try await all()
        guard let idx = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[idx].lastUpdatedAt = date
        try await store.save(subscriptions)
    }
}
