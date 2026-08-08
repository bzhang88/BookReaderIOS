import XCTest
@testable import Persistence

final class ShelfStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("shelf.json")
    }

    private func sampleBook(url: String = "https://example.com/book/1") -> ShelfBook {
        ShelfBook(
            bookSourceUrl: "https://example.com", bookUrl: url, name: "My Novel",
            author: "Author A", tocUrl: "https://example.com/book/1/toc"
        )
    }

    func testAddThenListsIt() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        try await store.addOrUpdate(sampleBook())
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["My Novel"])
    }

    func testAddingSameBookUrlTwiceUpdatesRatherThanDuplicates() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        try await store.addOrUpdate(sampleBook())
        var updated = sampleBook()
        updated.lastChapterTitle = "Chapter 99"
        try await store.addOrUpdate(updated)

        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.lastChapterTitle, "Chapter 99")
    }

    func testRemove() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        try await store.addOrUpdate(sampleBook())
        try await store.remove(bookUrl: "https://example.com/book/1")
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testUpdateProgressForUnknownBookIsANoOp() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        try await store.updateProgress(bookUrl: "https://nope.com", chapterIndex: 3, chapterTitle: "X", characterOffset: 10)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Phase 5 acceptance scenario: force-quit, relaunch days later, resume exactly

    func testProgressSurvivesSimulatedAppRelaunch() async throws {
        let fileURL = tempFileURL()

        // "Session 1": add the book, read partway into chapter 4.
        let session1 = ShelfStore(fileURL: fileURL)
        try await session1.addOrUpdate(sampleBook())
        try await session1.updateProgress(
            bookUrl: "https://example.com/book/1", chapterIndex: 4, chapterTitle: "Chapter 5",
            characterOffset: 1234
        )

        // "App force-quit and relaunched days later": a brand new ShelfStore instance, same file.
        let session2 = ShelfStore(fileURL: fileURL)
        let resumed = try await session2.book(bookUrl: "https://example.com/book/1")

        XCTAssertEqual(resumed?.lastReadChapterIndex, 4)
        XCTAssertEqual(resumed?.lastReadChapterTitle, "Chapter 5")
        XCTAssertEqual(resumed?.lastReadCharacterOffset, 1234)
        XCTAssertNotNil(resumed?.lastReadAt)
    }
}
