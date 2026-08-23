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

    func testSetGroupsForOneBookReplacesItsWholeGroupSet() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        var book = sampleBook()
        book.groups = ["旧分组"]
        try await store.addOrUpdate(book)

        try await store.setGroups(bookUrl: "https://example.com/book/1", to: ["玄幻", "在读"])

        let all = try await store.all()
        XCTAssertEqual(all.first?.groups, ["玄幻", "在读"])
    }

    func testSetGroupsForOneBookCanClearToEmpty() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        var book = sampleBook()
        book.groups = ["玄幻"]
        try await store.addOrUpdate(book)

        try await store.setGroups(bookUrl: "https://example.com/book/1", to: [])

        let all = try await store.all()
        XCTAssertEqual(all.first?.groups, [])
    }

    func testBatchSetGroupsAppliesToListedBooksAndSkipsOthers() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        try await store.addOrUpdate(sampleBook(url: "https://example.com/book/1"))
        try await store.addOrUpdate(sampleBook(url: "https://example.com/book/2"))

        try await store.setGroups(["https://example.com/book/1": ["玄幻"]])

        let all = try await store.all()
        XCTAssertEqual(all.first { $0.bookUrl == "https://example.com/book/1" }?.groups, ["玄幻"])
        XCTAssertEqual(all.first { $0.bookUrl == "https://example.com/book/2" }?.groups, [])
    }

    func testAddGroupToBooksUnionsRatherThanReplaces() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        var book = sampleBook()
        book.groups = ["在读"]
        try await store.addOrUpdate(book)

        try await store.addGroupToBooks(["https://example.com/book/1": "玄幻"])

        let all = try await store.all()
        XCTAssertEqual(all.first?.groups, ["在读", "玄幻"])
    }

    func testAddGroupToBooksIsANoOpWhenAlreadyPresent() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        var book = sampleBook()
        book.groups = ["玄幻"]
        try await store.addOrUpdate(book)

        try await store.addGroupToBooks(["https://example.com/book/1": "玄幻"])

        let all = try await store.all()
        XCTAssertEqual(all.first?.groups, ["玄幻"])
    }

    func testRenameGroupEverywherePreservesOtherMemberships() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        var book1 = sampleBook(url: "https://example.com/book/1")
        book1.groups = ["旧名", "在读"]
        var book2 = sampleBook(url: "https://example.com/book/2")
        book2.groups = ["其他分组"]
        try await store.addOrUpdate(book1)
        try await store.addOrUpdate(book2)

        try await store.renameGroupEverywhere("旧名", to: "新名")

        let all = try await store.all()
        XCTAssertEqual(all.first { $0.bookUrl == "https://example.com/book/1" }?.groups, ["新名", "在读"])
        XCTAssertEqual(all.first { $0.bookUrl == "https://example.com/book/2" }?.groups, ["其他分组"])
    }

    func testRenameGroupEverywhereDedupesIfBookAlreadyHasBothNames() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        var book = sampleBook()
        book.groups = ["旧名", "新名"]
        try await store.addOrUpdate(book)

        try await store.renameGroupEverywhere("旧名", to: "新名")

        let all = try await store.all()
        XCTAssertEqual(all.first?.groups, ["新名"])
    }

    func testRemoveGroupEverywherePreservesOtherMemberships() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        var book = sampleBook()
        book.groups = ["玄幻", "在读"]
        try await store.addOrUpdate(book)

        try await store.removeGroupEverywhere("玄幻")

        let all = try await store.all()
        XCTAssertEqual(all.first?.groups, ["在读"])
    }

    /// Real migration-safety case: `shelf.json` written before multi-group support has a single
    /// `String` under the `"group"` key, not a `[String]` -- must transparently upgrade to a
    /// one-element array rather than throwing (which `JSONFileStore.load()`'s `try decoder.decode()`
    /// would turn into a silently-empty shelf for every `try?`-wrapped caller).
    func testDecodesPreExistingShelfJSONWithSingleStringGroup() throws {
        let json = """
        [{
            "bookSourceUrl": "https://example.com", "bookUrl": "https://example.com/book/1",
            "name": "My Novel", "tocUrl": "https://example.com/book/1/toc",
            "addedAt": "2023-11-14T22:13:20Z", "lastReadCharacterOffset": 0, "group": "玄幻"
        }]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let books = try decoder.decode([ShelfBook].self, from: Data(json.utf8))
        XCTAssertEqual(books.first?.groups, ["玄幻"])
    }

    func testGroupsRoundTripsThroughEncodeDecode() throws {
        var book = sampleBook()
        book.groups = ["玄幻", "在读"]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(book)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ShelfBook.self, from: data)
        XCTAssertEqual(decoded.groups, ["玄幻", "在读"])
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
        XCTAssertEqual(books.first?.groups, [], "group key entirely absent should decode as no groups, not throw")
        XCTAssertNil(books.first?.customName)
        XCTAssertNil(books.first?.customAuthor)
        XCTAssertNil(books.first?.customIntro)
        XCTAssertNil(books.first?.pinnedAt)
    }

    // MARK: - Custom info overrides

    func testSetCustomInfoPersistsAllThreeOverrides() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        try await store.addOrUpdate(sampleBook())

        try await store.setCustomInfo(bookUrl: "https://example.com/book/1", name: "自定义书名", author: "自定义作者", intro: "自定义简介")

        let all = try await store.all()
        XCTAssertEqual(all.first?.customName, "自定义书名")
        XCTAssertEqual(all.first?.customAuthor, "自定义作者")
        XCTAssertEqual(all.first?.customIntro, "自定义简介")
    }

    func testSetCustomInfoWithBlankStringsClearsTheOverride() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        var book = sampleBook()
        book.customName = "旧的自定义书名"
        try await store.addOrUpdate(book)

        try await store.setCustomInfo(bookUrl: "https://example.com/book/1", name: "  ", author: nil, intro: nil)

        let all = try await store.all()
        XCTAssertNil(all.first?.customName, "a blank/whitespace-only override should clear back to nil, not be stored as blank")
    }

    func testCustomInfoRoundTripsThroughEncodeDecode() throws {
        var book = sampleBook()
        book.customName = "自定义书名"
        book.customAuthor = "自定义作者"
        book.customIntro = "自定义简介"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(book)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ShelfBook.self, from: data)
        XCTAssertEqual(decoded.customName, "自定义书名")
        XCTAssertEqual(decoded.customAuthor, "自定义作者")
        XCTAssertEqual(decoded.customIntro, "自定义简介")
    }

    // MARK: - Pinning

    func testSetPinnedTrueStampsATimestamp() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        try await store.addOrUpdate(sampleBook())

        try await store.setPinned(bookUrl: "https://example.com/book/1", pinned: true)

        let all = try await store.all()
        XCTAssertNotNil(all.first?.pinnedAt)
    }

    func testSetPinnedFalseClearsTheTimestamp() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        var book = sampleBook()
        book.pinnedAt = Date()
        try await store.addOrUpdate(book)

        try await store.setPinned(bookUrl: "https://example.com/book/1", pinned: false)

        let all = try await store.all()
        XCTAssertNil(all.first?.pinnedAt)
    }

    func testSetPinnedForUnknownBookIsANoOp() async throws {
        let store = ShelfStore(fileURL: tempFileURL())
        try await store.setPinned(bookUrl: "https://nope.com", pinned: true)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }
}
