import Foundation
import BookSourceModel

public actor TagGroupRuleStore {
    private let store: JSONFileStore<[TagGroupRule]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [TagGroupRule] {
        try await store.load() ?? []
    }

    public func enabled() async throws -> [TagGroupRule] {
        try await all().filter(\.enabled)
    }

    @discardableResult
    public func add(_ rule: TagGroupRule) async throws -> [TagGroupRule] {
        var rules = try await all()
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
        } else {
            rules.append(rule)
        }
        try await store.save(rules)
        return rules
    }

    public func remove(id: String) async throws {
        var rules = try await all()
        rules.removeAll { $0.id == id }
        try await store.save(rules)
    }

    public func setEnabled(id: String, enabled: Bool) async throws {
        var rules = try await all()
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[idx].enabled = enabled
        try await store.save(rules)
    }
}
