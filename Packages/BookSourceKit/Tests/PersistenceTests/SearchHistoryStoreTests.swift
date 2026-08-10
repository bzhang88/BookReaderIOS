import XCTest
@testable import Persistence

final class SearchHistoryStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("search_history.json")
    }

    func testRecordThenListsItMostRecentFirst() async throws {
        let store = SearchHistoryStore(fileURL: tempFileURL())
        try await store.record("斗破苍穹")
        try await store.record("完美世界")
        let recent = try await store.recent()
        XCTAssertEqual(recent, ["完美世界", "斗破苍穹"])
    }

    func testRecordingSameKeywordAgainMovesItToFrontRatherThanDuplicating() async throws {
        let store = SearchHistoryStore(fileURL: tempFileURL())
        try await store.record("斗破苍穹")
        try await store.record("完美世界")
        try await store.record("斗破苍穹")
        let recent = try await store.recent()
        XCTAssertEqual(recent, ["斗破苍穹", "完美世界"])
    }

    func testBlankKeywordIsIgnored() async throws {
        let store = SearchHistoryStore(fileURL: tempFileURL())
        try await store.record("   ")
        let recent = try await store.recent()
        XCTAssertTrue(recent.isEmpty)
    }

    func testHistoryIsTrimmedToLimit() async throws {
        let store = SearchHistoryStore(fileURL: tempFileURL(), limit: 3)
        try await store.record("a")
        try await store.record("b")
        try await store.record("c")
        try await store.record("d")
        let recent = try await store.recent()
        XCTAssertEqual(recent, ["d", "c", "b"])
    }

    func testClearEmptiesHistory() async throws {
        let store = SearchHistoryStore(fileURL: tempFileURL())
        try await store.record("斗破苍穹")
        try await store.clear()
        let recent = try await store.recent()
        XCTAssertTrue(recent.isEmpty)
    }

    func testHistorySurvivesSimulatedAppRelaunch() async throws {
        let fileURL = tempFileURL()
        let session1 = SearchHistoryStore(fileURL: fileURL)
        try await session1.record("斗破苍穹")

        let session2 = SearchHistoryStore(fileURL: fileURL)
        let recent = try await session2.recent()
        XCTAssertEqual(recent, ["斗破苍穹"])
    }
}
