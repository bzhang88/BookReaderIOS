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

    func testSetGroupsAppliesBatchAndSkipsBooksNotInTheMap() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        try await store.addOrUpdate(sampleBook(url: "https://example.com/book/1"))
        try await store.addOrUpdate(sampleBook(url: "https://example.com/book/2"))

        try await store.setGroups(["https://example.com/book/1": "玄幻"])

        let all = try await store.all()
        XCTAssertEqual(all.first { $0.bookUrl == "https://example.com/book/1" }?.group, "玄幻")
        XCTAssertNil(all.first { $0.bookUrl == "https://example.com/book/2" }?.group)
    }

    func testSetGroupsCanClearAGroupWithExplicitNil() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        var book = sampleBook()
        book.group = "玄幻"
        try await store.addOrUpdate(book)

        try await store.setGroups(["https://example.com/book/1": nil])

        let all = try await store.all()
        XCTAssertNil(all.first?.group)
    }

    func testUpdateTotalChapterCountPersists() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        try await store.addOrUpdate(sampleBook())
        try await store.updateTotalChapterCount(bookUrl: "https://example.com/book/1", count: 120)
        let all = try await store.all()
        XCTAssertEqual(all.first?.totalChapterCount, 120)
    }

    func testUpdateTotalChapterCountForUnknownBookIsANoOp() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        try await store.updateTotalChapterCount(bookUrl: "https://nope.com", count: 5)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testUpdateTotalChapterCountWithLastChapterTitleUpdatesBoth() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        try await store.addOrUpdate(sampleBook())
        try await store.updateTotalChapterCount(
            bookUrl: "https://example.com/book/1", count: 121, lastChapterTitle: "第121章 新章节"
        )
        let all = try await store.all()
        XCTAssertEqual(all.first?.totalChapterCount, 121)
        XCTAssertEqual(all.first?.lastChapterTitle, "第121章 新章节")
    }

    func testUpdateTotalChapterCountWithoutLastChapterTitleLeavesItUnchanged() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        var book = sampleBook()
        book.lastChapterTitle = "旧章节标题"
        try await store.addOrUpdate(book)
        try await store.updateTotalChapterCount(bookUrl: "https://example.com/book/1", count: 5)
        let all = try await store.all()
        XCTAssertEqual(all.first?.lastChapterTitle, "旧章节标题")
    }

    func testSetCoverUrlOverridesJustThatField() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        var book = sampleBook()
        book.coverUrl = "https://example.com/old-cover.jpg"
        try await store.addOrUpdate(book)

        try await store.setCoverUrl(bookUrl: "https://example.com/book/1", coverUrl: "https://example.com/new-cover.jpg")

        let all = try await store.all()
        XCTAssertEqual(all.first?.coverUrl, "https://example.com/new-cover.jpg")
        XCTAssertEqual(all.first?.name, "My Novel", "setCoverUrl must not touch other fields")
        XCTAssertEqual(all.first?.bookSourceUrl, "https://example.com", "changing the cover must not switch the source")
    }

    func testSetCoverUrlForUnknownBookIsANoOp() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        try await store.setCoverUrl(bookUrl: "https://nope.com", coverUrl: "https://example.com/cover.jpg")
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

    func testSetCanUpdateTogglesPersistedFlag() async throws {
        let fileURL = tempFileURL()
        let store = ShelfStore(fileURL: fileURL)
        try await store.addOrUpdate(sampleBook())
        try await store.setCanUpdate(bookUrl: "https://example.com/book/1", canUpdate: false)

        let reloaded = ShelfStore(fileURL: fileURL)
        let all = try await reloaded.all()
        XCTAssertEqual(all.first?.canUpdate, false)
    }

    /// The real migration-safety case: `canUpdate` didn't exist before this field was added.
    /// `JSONFileStore.load()` uses `try decoder.decode()` (throws, not nil-on-failure), and most
    /// callers wrap that in `try?` -- a non-optional `canUpdate` with only an `init` default would
    /// throw on this exact shape of pre-existing file and silently present as an *empty* shelf, not
    /// an error. This project already hit exactly this bug shape once before (`Bookmark.
    /// characterOffset`) and settled on `Optional` as the fix -- this test guards `ShelfBook` really
    /// applies it, not just claims to in a doc comment.
    func testDecodesPreExistingShelfJSONMissingCanUpdateField() throws {
        // `.iso8601` for `addedAt` matches `JSONFileStore`'s real configured strategy -- this test
        // uses its own plain `JSONDecoder` (not going through `JSONFileStore`) so it can decode a
        // literal fixture string directly, but still needs to match production's date format to be
        // a faithful "pre-existing real file" simulation.
        let json = """
        [{
            "bookSourceUrl": "https://example.com", "bookUrl": "https://example.com/book/1",
            "name": "My Novel", "tocUrl": "https://example.com/book/1/toc",
            "addedAt": "2023-11-14T22:13:20Z", "lastReadCharacterOffset": 0
        }]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let books = try decoder.decode([ShelfBook].self, from: Data(json.utf8))
        XCTAssertEqual(books.count, 1)
        XCTAssertNil(books.first?.canUpdate)
    }
}
