import XCTest
import BookSourceModel
@testable import Persistence

final class HighlightRuleStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("highlight_rules.json")
    }

    func testAddPersistsANewRule() async throws {
        let store = HighlightRuleStore(fileURL: tempFileURL())
        try await store.add(HighlightRule(name: "Name", pattern: "张三"))
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["Name"])
    }

    func testEnabledFiltersOutDisabledRules() async throws {
        let store = HighlightRuleStore(fileURL: tempFileURL())
        try await store.add(HighlightRule(name: "On", pattern: "a", enabled: true))
        try await store.add(HighlightRule(name: "Off", pattern: "b", enabled: false))
        let enabled = try await store.enabled()
        XCTAssertEqual(enabled.map(\.name), ["On"])
    }

    func testRemoveDeletesByID() async throws {
        let store = HighlightRuleStore(fileURL: tempFileURL())
        let rule = HighlightRule(name: "ToDelete", pattern: "a")
        try await store.add(rule)
        try await store.remove(id: rule.id)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testSetEnabledTogglesPersistedFlag() async throws {
        let fileURL = tempFileURL()
        let store = HighlightRuleStore(fileURL: fileURL)
        let rule = HighlightRule(name: "Toggle", pattern: "a", enabled: true)
        try await store.add(rule)
        try await store.setEnabled(id: rule.id, enabled: false)

        let reloaded = HighlightRuleStore(fileURL: fileURL)
        let all = try await reloaded.all()
        XCTAssertEqual(all.first?.enabled, false)
    }

    func testSetGroupsReassignsGroupForListedIDs() async throws {
        let store = HighlightRuleStore(fileURL: tempFileURL())
        let a = HighlightRule(name: "A", pattern: "a", group: "旧分组")
        let b = HighlightRule(name: "B", pattern: "b", group: "旧分组")
        let c = HighlightRule(name: "C", pattern: "c", group: "其他分组")
        try await store.add(a)
        try await store.add(b)
        try await store.add(c)

        try await store.setGroups([a.id: "新分组", b.id: "新分组"])

        let all = try await store.all()
        XCTAssertEqual(all.first { $0.id == a.id }?.group, "新分组")
        XCTAssertEqual(all.first { $0.id == b.id }?.group, "新分组")
        XCTAssertEqual(all.first { $0.id == c.id }?.group, "其他分组")
    }

    func testSetGroupsCanClearAGroupBackToNil() async throws {
        let store = HighlightRuleStore(fileURL: tempFileURL())
        let rule = HighlightRule(name: "A", pattern: "a", group: "旧分组")
        try await store.add(rule)

        let clearedGroup: String? = nil
        try await store.setGroups([rule.id: clearedGroup])

        let all = try await store.all()
        XCTAssertNil(all.first?.group)
    }
}
