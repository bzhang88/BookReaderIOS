import XCTest
import BookSourceModel
@testable import Persistence

final class ReplaceRuleStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("replace_rules.json")
    }

    func testAddPersistsANewRule() async throws {
        let store = ReplaceRuleStore(fileURL: tempFileURL())
        try await store.add(ReplaceRule(name: "Ad", pattern: "ad", replacement: ""))
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["Ad"])
    }

    func testAddWithExistingIDUpdatesInPlaceInsteadOfDuplicating() async throws {
        let store = ReplaceRuleStore(fileURL: tempFileURL())
        let rule = ReplaceRule(name: "Original", pattern: "a")
        try await store.add(rule)

        var edited = rule
        edited.name = "Edited"
        try await store.add(edited)

        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Edited")
    }

    func testEnabledFiltersOutDisabledRules() async throws {
        let store = ReplaceRuleStore(fileURL: tempFileURL())
        try await store.add(ReplaceRule(name: "On", pattern: "a", enabled: true))
        try await store.add(ReplaceRule(name: "Off", pattern: "b", enabled: false))
        let enabled = try await store.enabled()
        XCTAssertEqual(enabled.map(\.name), ["On"])
    }

    func testUpdateReplacesRuleByID() async throws {
        let fileURL = tempFileURL()
        let store = ReplaceRuleStore(fileURL: fileURL)
        let original = ReplaceRule(name: "Original", pattern: "a")
        try await store.add(original)

        var edited = original
        edited.name = "Edited"
        edited.pattern = "b"
        try await store.update(edited)

        let reloaded = ReplaceRuleStore(fileURL: fileURL)
        let all = try await reloaded.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Edited")
        XCTAssertEqual(all.first?.pattern, "b")
    }

    func testRemoveDeletesRuleByID() async throws {
        let store = ReplaceRuleStore(fileURL: tempFileURL())
        let rule = ReplaceRule(name: "ToDelete", pattern: "a")
        try await store.add(rule)
        try await store.remove(id: rule.id)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testSetEnabledTogglesPersistedFlag() async throws {
        let fileURL = tempFileURL()
        let store = ReplaceRuleStore(fileURL: fileURL)
        let rule = ReplaceRule(name: "Toggle", pattern: "a", enabled: true)
        try await store.add(rule)
        try await store.setEnabled(id: rule.id, enabled: false)

        let reloaded = ReplaceRuleStore(fileURL: fileURL)
        let all = try await reloaded.all()
        XCTAssertEqual(all.first?.enabled, false)
    }

    func testSetGroupsAppliesBatchAndSkipsRulesNotInTheMap() async throws {
        let store = ReplaceRuleStore(fileURL: tempFileURL())
        let ruleA = ReplaceRule(name: "A", pattern: "a")
        let ruleB = ReplaceRule(name: "B", pattern: "b")
        try await store.add(ruleA)
        try await store.add(ruleB)

        try await store.setGroups([ruleA.id: "通用"])

        let all = try await store.all()
        XCTAssertEqual(all.first { $0.id == ruleA.id }?.group, "通用")
        XCTAssertNil(all.first { $0.id == ruleB.id }?.group)
    }

    func testSetGroupsCanClearAGroupWithExplicitNil() async throws {
        let store = ReplaceRuleStore(fileURL: tempFileURL())
        let rule = ReplaceRule(name: "A", group: "通用", pattern: "a")
        try await store.add(rule)

        try await store.setGroups([rule.id: nil])

        let all = try await store.all()
        XCTAssertNil(all.first?.group)
    }
}
