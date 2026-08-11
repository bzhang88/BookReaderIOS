import XCTest
import BookSourceModel
@testable import Persistence

final class CoverGalleryStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("cover_gallery.json")
    }

    func testAddPersistsANewCover() async throws {
        let store = CoverGalleryStore(fileURL: tempFileURL())
        try await store.add(SavedCover(url: "https://example.com/cover.jpg", bookName: "示例书"))
        let all = try await store.all()
        XCTAssertEqual(all.map(\.url), ["https://example.com/cover.jpg"])
    }

    func testAddingSameURLAgainUpdatesRatherThanDuplicating() async throws {
        let store = CoverGalleryStore(fileURL: tempFileURL())
        try await store.add(SavedCover(url: "https://example.com/cover.jpg", bookName: "书A", savedAt: Date(timeIntervalSince1970: 1)))
        try await store.add(SavedCover(url: "https://example.com/cover.jpg", bookName: "书B", savedAt: Date(timeIntervalSince1970: 2)))
        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.bookName, "书B")
    }

    func testAllOrdersMostRecentlySavedFirst() async throws {
        let store = CoverGalleryStore(fileURL: tempFileURL())
        try await store.add(SavedCover(url: "https://example.com/a.jpg", bookName: "A", savedAt: Date(timeIntervalSince1970: 1)))
        try await store.add(SavedCover(url: "https://example.com/b.jpg", bookName: "B", savedAt: Date(timeIntervalSince1970: 2)))
        let all = try await store.all()
        XCTAssertEqual(all.map(\.bookName), ["B", "A"])
    }

    func testRemoveDeletesByID() async throws {
        let store = CoverGalleryStore(fileURL: tempFileURL())
        let cover = SavedCover(url: "https://example.com/cover.jpg", bookName: "示例书")
        try await store.add(cover)
        try await store.remove(id: cover.id)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testCoversSurviveSimulatedAppRelaunch() async throws {
        let fileURL = tempFileURL()
        let session1 = CoverGalleryStore(fileURL: fileURL)
        try await session1.add(SavedCover(url: "https://example.com/cover.jpg", bookName: "示例书"))

        let session2 = CoverGalleryStore(fileURL: fileURL)
        let all = try await session2.all()
        XCTAssertEqual(all.map(\.url), ["https://example.com/cover.jpg"])
    }
}
