import XCTest
import BookSourceModel
@testable import Persistence

final class DictRuleStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("dict_rules.json")
    }

    private func rule(name: String, enabled: Bool = true) -> DictRule {
        DictRule(name: name, urlRule: "https://dict.example.com/search?w={{key}}", showRule: "@css:.def@text", enabled: enabled)
    }

    func testAddPersistsANewRule() async throws {
        let store = DictRuleStore(fileURL: tempFileURL())
        try await store.add(rule(name: "汉典"))
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["汉典"])
    }

    func testAddingSameIDUpdatesInPlace() async throws {
        let store = DictRuleStore(fileURL: tempFileURL())
        var original = rule(name: "汉典")
        try await store.add(original)
        original.name = "汉典 v2"
        try await store.add(original)
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["汉典 v2"])
    }

    func testEnabledFiltersOutDisabledRules() async throws {
        let store = DictRuleStore(fileURL: tempFileURL())
        try await store.add(rule(name: "On", enabled: true))
        try await store.add(rule(name: "Off", enabled: false))
        let enabled = try await store.enabled()
        XCTAssertEqual(enabled.map(\.name), ["On"])
    }

    func testRemoveDeletesByID() async throws {
        let store = DictRuleStore(fileURL: tempFileURL())
        let toDelete = rule(name: "ToDelete")
        try await store.add(toDelete)
        try await store.remove(id: toDelete.id)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testSetEnabledTogglesPersistedFlag() async throws {
        let fileURL = tempFileURL()
        let store = DictRuleStore(fileURL: fileURL)
        let toggled = rule(name: "Toggle")
        try await store.add(toggled)
        try await store.setEnabled(id: toggled.id, enabled: false)

        let reloaded = DictRuleStore(fileURL: fileURL)
        let all = try await reloaded.all()
        XCTAssertEqual(all.first?.enabled, false)
    }
}
