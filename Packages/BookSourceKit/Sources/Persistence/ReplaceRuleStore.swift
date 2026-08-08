import Foundation
import BookSourceModel

public actor ReplaceRuleStore {
    private let store: JSONFileStore<[ReplaceRule]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [ReplaceRule] {
        try await store.load() ?? []
    }

    public func enabled() async throws -> [ReplaceRule] {
        try await all().filter(\.enabled)
    }

    @discardableResult
    public func add(_ rule: ReplaceRule) async throws -> [ReplaceRule] {
        var rules = try await all()
        rules.append(rule)
        try await store.save(rules)
        return rules
    }

    public func update(_ rule: ReplaceRule) async throws {
        var rules = try await all()
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[idx] = rule
        try await store.save(rules)
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
