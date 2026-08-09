import XCTest
@testable import Persistence

final class LocalBookStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("local_books.json")
    }

    private func sampleBook(id: String = "book-1") -> LocalBook {
        LocalBook(id: id, title: "本地小说", chapters: [
            LocalChapter(title: "第一章", text: "正文一"),
            LocalChapter(title: "第二章", text: "正文二")
        ])
    }

    func testAddThenListsIt() async throws {
        let store = LocalBookStore(fileURL: tempFileURL())
        try await store.add(sampleBook())
        let all = try await store.all()
        XCTAssertEqual(all.map(\.title), ["本地小说"])
        XCTAssertEqual(all.first?.chapters.count, 2)
    }

    func testAddingTwoDistinctBooksKeepsBoth() async throws {
        let store = LocalBookStore(fileURL: tempFileURL())
        try await store.add(sampleBook(id: "book-1"))
        try await store.add(sampleBook(id: "book-2"))
        let all = try await store.all()
        XCTAssertEqual(all.count, 2)
    }

    func testRemove() async throws {
        let store = LocalBookStore(fileURL: tempFileURL())
        try await store.add(sampleBook())
        try await store.remove(id: "book-1")
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testUpdateProgressForUnknownBookIsANoOp() async throws {
        let store = LocalBookStore(fileURL: tempFileURL())
        try await store.updateProgress(id: "nope", chapterIndex: 3)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testProgressSurvivesSimulatedAppRelaunch() async throws {
        let fileURL = tempFileURL()
        let session1 = LocalBookStore(fileURL: fileURL)
        try await session1.add(sampleBook())
        try await session1.updateProgress(id: "book-1", chapterIndex: 1)

        let session2 = LocalBookStore(fileURL: fileURL)
        let all = try await session2.all()

        XCTAssertEqual(all.first?.lastReadChapterIndex, 1)
        XCTAssertNotNil(all.first?.lastReadAt)
    }
}
