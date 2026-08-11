import XCTest
import BookSourceModel
@testable import Persistence

final class BookSourceTrashStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("book_source_trash.json")
    }

    private func sampleSource(url: String = "https://example.com/source") -> BookSource {
        BookSource(bookSourceUrl: url, bookSourceName: "Test Source")
    }

    func testAddPersistsATrashedSource() async throws {
        let store = BookSourceTrashStore(fileURL: tempFileURL())
        try await store.add(sampleSource())
        let all = try await store.all()
        XCTAssertEqual(all.map(\.bookSourceName), ["Test Source"])
    }

    func testAddingSameUrlTwiceUpdatesRatherThanDuplicates() async throws {
        let store = BookSourceTrashStore(fileURL: tempFileURL())
        try await store.add(sampleSource())
        var updated = sampleSource()
        updated.bookSourceName = "Renamed"
        try await store.add(updated)

        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.bookSourceName, "Renamed")
    }

    func testRemoveDeletesByUrl() async throws {
        let store = BookSourceTrashStore(fileURL: tempFileURL())
        try await store.add(sampleSource())
        try await store.remove(bookSourceUrl: "https://example.com/source")
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testRemoveAllClearsEverything() async throws {
        let store = BookSourceTrashStore(fileURL: tempFileURL())
        try await store.add(sampleSource(url: "https://example.com/1"))
        try await store.add(sampleSource(url: "https://example.com/2"))
        try await store.removeAll()
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testTrashSurvivesSimulatedAppRelaunch() async throws {
        let fileURL = tempFileURL()
        let session1 = BookSourceTrashStore(fileURL: fileURL)
        try await session1.add(sampleSource())

        let session2 = BookSourceTrashStore(fileURL: fileURL)
        let all = try await session2.all()
        XCTAssertEqual(all.map(\.bookSourceName), ["Test Source"])
    }
}
