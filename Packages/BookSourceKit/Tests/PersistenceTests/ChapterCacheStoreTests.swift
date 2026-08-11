import XCTest
import WebBookOrchestrator
@testable import Persistence

final class ChapterCacheStoreTests: XCTestCase {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
    }

    func testSaveThenReadsBackSameContent() async throws {
        let store = ChapterCacheStore(directory: tempDirectory())
        let content = ChapterContent(text: "正文内容", titleOverride: "第一章")
        try await store.save(bookUrl: "https://example.com/book/1", index: 0, content: content)

        let read = try await store.chapter(bookUrl: "https://example.com/book/1", index: 0)
        XCTAssertEqual(read, content)
    }

    func testMissingChapterReturnsNil() async throws {
        let store = ChapterCacheStore(directory: tempDirectory())
        let read = try await store.chapter(bookUrl: "https://example.com/book/1", index: 0)
        XCTAssertNil(read)
    }

    func testDifferentBooksAreIsolated() async throws {
        let store = ChapterCacheStore(directory: tempDirectory())
        try await store.save(bookUrl: "https://example.com/book/1", index: 0, content: ChapterContent(text: "书一"))
        try await store.save(bookUrl: "https://example.com/book/2", index: 0, content: ChapterContent(text: "书二"))

        let one = try await store.chapter(bookUrl: "https://example.com/book/1", index: 0)
        let two = try await store.chapter(bookUrl: "https://example.com/book/2", index: 0)
        XCTAssertEqual(one?.text, "书一")
        XCTAssertEqual(two?.text, "书二")
    }

    func testDownloadedIndicesReflectsWhatsBeenSaved() async throws {
        let store = ChapterCacheStore(directory: tempDirectory())
        try await store.save(bookUrl: "https://example.com/book/1", index: 0, content: ChapterContent(text: "a"))
        try await store.save(bookUrl: "https://example.com/book/1", index: 2, content: ChapterContent(text: "c"))

        let indices = try await store.downloadedIndices(bookUrl: "https://example.com/book/1")
        XCTAssertEqual(indices, [0, 2])
    }

    func testRemoveBookClearsAllItsChapters() async throws {
        let store = ChapterCacheStore(directory: tempDirectory())
        try await store.save(bookUrl: "https://example.com/book/1", index: 0, content: ChapterContent(text: "a"))
        try await store.removeBook(bookUrl: "https://example.com/book/1")

        let indices = try await store.downloadedIndices(bookUrl: "https://example.com/book/1")
        XCTAssertTrue(indices.isEmpty)
    }

    func testRemovingUnknownBookIsANoOp() async throws {
        let store = ChapterCacheStore(directory: tempDirectory())
        try await store.removeBook(bookUrl: "https://example.com/never-downloaded")
    }

    func testCacheSurvivesSimulatedAppRelaunch() async throws {
        let directory = tempDirectory()
        let session1 = ChapterCacheStore(directory: directory)
        try await session1.save(bookUrl: "https://example.com/book/1", index: 5, content: ChapterContent(text: "正文"))

        let session2 = ChapterCacheStore(directory: directory)
        let read = try await session2.chapter(bookUrl: "https://example.com/book/1", index: 5)
        XCTAssertEqual(read?.text, "正文")
    }

    func testSizeBytesIsZeroForNeverDownloadedBook() async throws {
        let store = ChapterCacheStore(directory: tempDirectory())
        let size = await store.sizeBytes(bookUrl: "https://example.com/never-downloaded")
        XCTAssertEqual(size, 0)
    }

    func testSizeBytesIsPositiveAfterSaving() async throws {
        let store = ChapterCacheStore(directory: tempDirectory())
        try await store.save(bookUrl: "https://example.com/book/1", index: 0, content: ChapterContent(text: "正文内容"))
        let size = await store.sizeBytes(bookUrl: "https://example.com/book/1")
        XCTAssertGreaterThan(size, 0)
    }

    func testTotalSizeBytesSumsAcrossBooks() async throws {
        let store = ChapterCacheStore(directory: tempDirectory())
        try await store.save(bookUrl: "https://example.com/book/1", index: 0, content: ChapterContent(text: "书一"))
        try await store.save(bookUrl: "https://example.com/book/2", index: 0, content: ChapterContent(text: "书二"))

        let bookOneSize = await store.sizeBytes(bookUrl: "https://example.com/book/1")
        let bookTwoSize = await store.sizeBytes(bookUrl: "https://example.com/book/2")
        let total = await store.totalSizeBytes()
        XCTAssertEqual(total, bookOneSize + bookTwoSize)
    }

    func testRemoveAllClearsEveryBooksCache() async throws {
        let store = ChapterCacheStore(directory: tempDirectory())
        try await store.save(bookUrl: "https://example.com/book/1", index: 0, content: ChapterContent(text: "书一"))
        try await store.save(bookUrl: "https://example.com/book/2", index: 0, content: ChapterContent(text: "书二"))

        try await store.removeAll()

        let total = await store.totalSizeBytes()
        XCTAssertEqual(total, 0)
        let indices = try await store.downloadedIndices(bookUrl: "https://example.com/book/1")
        XCTAssertTrue(indices.isEmpty)
    }
}
