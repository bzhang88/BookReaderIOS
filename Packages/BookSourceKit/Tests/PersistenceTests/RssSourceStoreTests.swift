import XCTest
import BookSourceModel
@testable import Persistence

final class RssSourceStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("rss_sources.json")
    }

    func testAddInsertsNewSource() async throws {
        let store = RssSourceStore(fileURL: tempFileURL())
        try await store.add(RssSource(sourceUrl: "https://a.com/feed", sourceName: "A"))
        let all = try await store.all()
        XCTAssertEqual(all.map(\.sourceName), ["A"])
    }

    func testAddWithExistingURLUpdatesInPlace() async throws {
        let store = RssSourceStore(fileURL: tempFileURL())
        try await store.add(RssSource(sourceUrl: "https://a.com/feed", sourceName: "A v1"))
        try await store.add(RssSource(sourceUrl: "https://a.com/feed", sourceName: "A v2"))
        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.sourceName, "A v2")
    }

    func testRemoveDeletesByURL() async throws {
        let store = RssSourceStore(fileURL: tempFileURL())
        try await store.add(RssSource(sourceUrl: "https://a.com/feed", sourceName: "A"))
        try await store.remove(sourceUrl: "https://a.com/feed")
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testSetEnabledTogglesPersistedFlag() async throws {
        let fileURL = tempFileURL()
        let store = RssSourceStore(fileURL: fileURL)
        try await store.add(RssSource(sourceUrl: "https://a.com/feed", sourceName: "A", enabled: true))
        try await store.setEnabled(sourceUrl: "https://a.com/feed", enabled: false)

        let reloaded = RssSourceStore(fileURL: fileURL)
        let all = try await reloaded.all()
        XCTAssertEqual(all.first?.enabled, false)
    }
}
