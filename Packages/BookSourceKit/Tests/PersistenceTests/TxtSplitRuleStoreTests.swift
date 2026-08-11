import XCTest
import BookSourceModel
@testable import Persistence

final class TxtSplitRuleStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("txt_split_rules.json")
    }

    func testAddPersistsANewRule() async throws {
        let store = TxtSplitRuleStore(fileURL: tempFileURL())
        try await store.add(TxtSplitRule(name: "Name", pattern: "^第.+章$"))
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["Name"])
    }

    func testEnabledFiltersOutDisabledRules() async throws {
        let store = TxtSplitRuleStore(fileURL: tempFileURL())
        try await store.add(TxtSplitRule(name: "On", pattern: "a", enabled: true))
        try await store.add(TxtSplitRule(name: "Off", pattern: "b", enabled: false))
        let enabled = try await store.enabled()
        XCTAssertEqual(enabled.map(\.name), ["On"])
    }

    func testRemoveDeletesByID() async throws {
        let store = TxtSplitRuleStore(fileURL: tempFileURL())
        let rule = TxtSplitRule(name: "ToDelete", pattern: "a")
        try await store.add(rule)
        try await store.remove(id: rule.id)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testSetEnabledTogglesPersistedFlag() async throws {
        let fileURL = tempFileURL()
        let store = TxtSplitRuleStore(fileURL: fileURL)
        let rule = TxtSplitRule(name: "Toggle", pattern: "a", enabled: true)
        try await store.add(rule)
        try await store.setEnabled(id: rule.id, enabled: false)

        let reloaded = TxtSplitRuleStore(fileURL: fileURL)
        let all = try await reloaded.all()
        XCTAssertEqual(all.first?.enabled, false)
    }

    func testEnabledPreservesListOrderAsPriorityOrder() async throws {
        let store = TxtSplitRuleStore(fileURL: tempFileURL())
        try await store.add(TxtSplitRule(name: "First", pattern: "a"))
        try await store.add(TxtSplitRule(name: "Second", pattern: "b"))
        let enabled = try await store.enabled()
        XCTAssertEqual(enabled.map(\.name), ["First", "Second"])
    }

    func testSetAllReplacesOrderNotJustValues() async throws {
        let fileURL = tempFileURL()
        let store = TxtSplitRuleStore(fileURL: fileURL)
        let first = TxtSplitRule(name: "First", pattern: "a")
        let second = TxtSplitRule(name: "Second", pattern: "b")
        try await store.add(first)
        try await store.add(second)

        try await store.setAll([second, first])

        let reloaded = TxtSplitRuleStore(fileURL: fileURL)
        let all = try await reloaded.all()
        XCTAssertEqual(all.map(\.name), ["Second", "First"])
    }
}
