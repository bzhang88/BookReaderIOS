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
}
