import Foundation
import BookSourceModel

public actor HighlightRuleStore {
    private let store: JSONFileStore<[HighlightRule]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [HighlightRule] {
        try await store.load() ?? []
    }

    public func enabled() async throws -> [HighlightRule] {
        try await all().filter(\.enabled)
    }

    @discardableResult
    public func add(_ rule: HighlightRule) async throws -> [HighlightRule] {
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

    /// Batch group reassignment, keyed by rule `id` -- same pattern as `ReplaceRuleStore.setGroups`,
    /// used by `HighlightRuleGroupManagementView` to rename/delete a group across every rule in it
    /// in one write.
    public func setGroups(_ groups: [String: String?]) async throws {
        var rules = try await all()
        for idx in rules.indices {
            if let newGroup = groups[rules[idx].id] {
                rules[idx].group = newGroup
            }
        }
        try await store.save(rules)
    }
}
