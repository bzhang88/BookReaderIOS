import Foundation
import BookSourceModel

public actor TxtSplitRuleStore {
    private let store: JSONFileStore<[TxtSplitRule]>

    public init(fileURL: URL) {
        self.store = JSONFileStore(fileURL: fileURL)
    }

    public func all() async throws -> [TxtSplitRule] {
        try await store.load() ?? []
    }

    /// In list order -- `TxtChapterSplitter.splitTryingRules` tries them one at a time and stops at
    /// the first one that actually produces multiple chapters, so order here is priority order.
    public func enabled() async throws -> [TxtSplitRule] {
        try await all().filter(\.enabled)
    }

    @discardableResult
    public func add(_ rule: TxtSplitRule) async throws -> [TxtSplitRule] {
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

    /// Replaces the whole list at once, in the exact order given -- unlike `add`, which only ever
    /// updates a rule at its *existing* position, this is how reordering (list order doubles as
    /// `splitTryingRules`' priority order) actually gets persisted.
    public func setAll(_ rules: [TxtSplitRule]) async throws {
        try await store.save(rules)
    }
}
