import XCTest
@testable import Persistence

final class RssReadStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("rss_read.json")
    }

    func testUnmarkedLinkIsNotRead() async throws {
        let store = RssReadStore(fileURL: tempFileURL())
        let isRead = try await store.isRead("https://a.com/article/1")
        XCTAssertFalse(isRead)
    }

    func testMarkReadPersists() async throws {
        let fileURL = tempFileURL()
        let store = RssReadStore(fileURL: fileURL)
        try await store.markRead("https://a.com/article/1")

        let reloaded = RssReadStore(fileURL: fileURL)
        let isRead = try await reloaded.isRead("https://a.com/article/1")
        XCTAssertTrue(isRead)
    }

    func testMarkingTheSameLinkTwiceIsANoOp() async throws {
        let store = RssReadStore(fileURL: tempFileURL())
        try await store.markRead("https://a.com/article/1")
        try await store.markRead("https://a.com/article/1")
        let links = try await store.readLinks()
        XCTAssertEqual(links, ["https://a.com/article/1"])
    }

    func testMultipleLinksAreTrackedIndependently() async throws {
        let store = RssReadStore(fileURL: tempFileURL())
        try await store.markRead("https://a.com/article/1")
        let links = try await store.readLinks()
        XCTAssertTrue(links.contains("https://a.com/article/1"))
        XCTAssertFalse(links.contains("https://a.com/article/2"))
    }
}
