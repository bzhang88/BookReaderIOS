import XCTest
@testable import Persistence

final class BookmarkStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("bookmarks.json")
    }

    private func sampleBookmark(bookIdentifier: String = "https://example.com/book/1", chapterIndex: Int = 0) -> Bookmark {
        Bookmark(
            isLocal: false, bookSourceUrl: "https://example.com", bookIdentifier: bookIdentifier,
            tocUrl: "https://example.com/book/1/toc", bookTitle: "My Novel", chapterIndex: chapterIndex,
            chapterTitle: "Chapter \(chapterIndex + 1)"
        )
    }

    func testAddThenListsIt() async throws {
        let store = BookmarkStore(fileURL: tempFileURL())
        try await store.add(sampleBookmark())
        let all = try await store.all()
        XCTAssertEqual(all.map(\.bookTitle), ["My Novel"])
    }

    func testBookmarksFiltersToOneBook() async throws {
        let store = BookmarkStore(fileURL: tempFileURL())
        try await store.add(sampleBookmark(bookIdentifier: "book-1"))
        try await store.add(sampleBookmark(bookIdentifier: "book-2"))
        let forBook1 = try await store.bookmarks(bookIdentifier: "book-1")
        XCTAssertEqual(forBook1.count, 1)
    }

    func testIsBookmarkedReflectsExactChapter() async throws {
        let store = BookmarkStore(fileURL: tempFileURL())
        try await store.add(sampleBookmark(bookIdentifier: "book-1", chapterIndex: 3))
        let hit = try await store.isBookmarked(bookIdentifier: "book-1", chapterIndex: 3)
        let miss = try await store.isBookmarked(bookIdentifier: "book-1", chapterIndex: 4)
        XCTAssertTrue(hit)
        XCTAssertFalse(miss)
    }

    func testRemoveByBookAndChapter() async throws {
        let store = BookmarkStore(fileURL: tempFileURL())
        try await store.add(sampleBookmark(bookIdentifier: "book-1", chapterIndex: 0))
        try await store.add(sampleBookmark(bookIdentifier: "book-1", chapterIndex: 1))
        try await store.remove(bookIdentifier: "book-1", chapterIndex: 0)
        let remaining = try await store.bookmarks(bookIdentifier: "book-1")
        XCTAssertEqual(remaining.map(\.chapterIndex), [1])
    }

    func testRemoveById() async throws {
        let store = BookmarkStore(fileURL: tempFileURL())
        let bookmark = sampleBookmark()
        try await store.add(bookmark)
        try await store.remove(id: bookmark.id)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testUpdateEditsInPlaceRatherThanDuplicating() async throws {
        let store = BookmarkStore(fileURL: tempFileURL())
        var bookmark = sampleBookmark()
        try await store.add(bookmark)
        bookmark.note = "记得回来看这段"
        try await store.update(bookmark)
        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.note, "记得回来看这段")
    }

    func testUpdateFallsBackToAppendingWhenIdNotFound() async throws {
        let store = BookmarkStore(fileURL: tempFileURL())
        let bookmark = sampleBookmark()
        try await store.update(bookmark)
        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
    }

    func testBookmarksSurviveSimulatedAppRelaunch() async throws {
        let fileURL = tempFileURL()
        let session1 = BookmarkStore(fileURL: fileURL)
        try await session1.add(sampleBookmark())

        let session2 = BookmarkStore(fileURL: fileURL)
        let all = try await session2.all()
        XCTAssertEqual(all.count, 1)
    }
}
