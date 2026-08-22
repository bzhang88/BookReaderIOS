import XCTest
import BookSourceModel
@testable import Persistence

final class BookSourceStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("sources.json")
    }

    private func source(url: String, name: String, enabled: Bool = true) -> BookSource {
        BookSource(bookSourceUrl: url, bookSourceName: name, enabled: enabled)
    }

    func testImportInsertsNewSources() async throws {
        let store = BookSourceStore(fileURL: tempFileURL())
        let result = try await store.importSources([
            source(url: "https://a.com", name: "A"),
            source(url: "https://b.com", name: "B")
        ])
        XCTAssertEqual(result.inserted, 2)
        XCTAssertEqual(result.updated, 0)
        let all = try await store.all()
        XCTAssertEqual(Set(all.map(\.bookSourceName)), ["A", "B"])
    }

    func testReimportingSameURLUpdatesInPlaceRatherThanDuplicating() async throws {
        let store = BookSourceStore(fileURL: tempFileURL())
        try await store.importSources([source(url: "https://a.com", name: "A v1")])
        let result = try await store.importSources([source(url: "https://a.com", name: "A v2")])

        XCTAssertEqual(result.inserted, 0)
        XCTAssertEqual(result.updated, 1)
        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.bookSourceName, "A v2")
    }

    func testEnabledFiltersOutDisabledSources() async throws {
        let store = BookSourceStore(fileURL: tempFileURL())
        try await store.importSources([
            source(url: "https://a.com", name: "A", enabled: true),
            source(url: "https://b.com", name: "B", enabled: false)
        ])
        let enabled = try await store.enabled()
        XCTAssertEqual(enabled.map(\.bookSourceName), ["A"])
    }

    func testSetEnabledTogglesPersistedFlag() async throws {
        let fileURL = tempFileURL()
        let store = BookSourceStore(fileURL: fileURL)
        try await store.importSources([source(url: "https://a.com", name: "A", enabled: true)])
        try await store.setEnabled(bookSourceUrl: "https://a.com", enabled: false)

        let reloaded = BookSourceStore(fileURL: fileURL)
        let all = try await reloaded.all()
        XCTAssertEqual(all.first?.enabled, false)
    }

    func testSetAllEnabledTogglesEveryPersistedSource() async throws {
        let fileURL = tempFileURL()
        let store = BookSourceStore(fileURL: fileURL)
        try await store.importSources([
            source(url: "https://a.com", name: "A", enabled: true),
            source(url: "https://b.com", name: "B", enabled: false),
            source(url: "https://c.com", name: "C", enabled: true)
        ])

        try await store.setAllEnabled(false)
        let reloaded1 = BookSourceStore(fileURL: fileURL)
        let allDisabled = try await reloaded1.all()
        XCTAssertTrue(allDisabled.allSatisfy { !$0.enabled })

        try await store.setAllEnabled(true)
        let reloaded2 = BookSourceStore(fileURL: fileURL)
        let allEnabled = try await reloaded2.all()
        XCTAssertTrue(allEnabled.allSatisfy(\.enabled))
    }

    func testRemove() async throws {
        let store = BookSourceStore(fileURL: tempFileURL())
        try await store.importSources([source(url: "https://a.com", name: "A")])
        try await store.remove(bookSourceUrl: "https://a.com")
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testSetGroupsAppliesBatchAndSkipsSourcesNotInTheMap() async throws {
        let store = BookSourceStore(fileURL: tempFileURL())
        try await store.importSources([
            source(url: "https://a.com", name: "A"),
            source(url: "https://b.com", name: "B")
        ])

        try await store.setGroups(["https://a.com": "玄幻"])

        let all = try await store.all()
        XCTAssertEqual(all.first { $0.bookSourceUrl == "https://a.com" }?.bookSourceGroup, "玄幻")
        XCTAssertNil(all.first { $0.bookSourceUrl == "https://b.com" }?.bookSourceGroup)
    }

    func testSetGroupsCanClearAGroupWithExplicitNil() async throws {
        let store = BookSourceStore(fileURL: tempFileURL())
        try await store.importSources([BookSource(bookSourceUrl: "https://a.com", bookSourceName: "A", bookSourceGroup: "玄幻")])

        try await store.setGroups(["https://a.com": nil])

        let all = try await store.all()
        XCTAssertNil(all.first?.bookSourceGroup)
    }
}
