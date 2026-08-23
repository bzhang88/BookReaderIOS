import XCTest
import WebBookOrchestrator
@testable import Persistence

final class RssFavoriteStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("rss_favorites.json")
    }

    private func sample(link: String = "https://a.com/article/1", title: String = "Article One") -> RssFavoriteArticle {
        RssFavoriteArticle(link: link, title: title, sourceUrl: "https://a.com/feed", sourceName: "A")
    }

    func testAddPersistsANewFavorite() async throws {
        let store = RssFavoriteStore(fileURL: tempFileURL())
        try await store.add(sample())
        let all = try await store.all()
        XCTAssertEqual(all.map(\.title), ["Article One"])
    }

    func testAddingTheSameLinkTwiceDoesNotDuplicate() async throws {
        let store = RssFavoriteStore(fileURL: tempFileURL())
        try await store.add(sample())
        try await store.add(sample())
        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
    }

    func testNewestFavoriteIsFirst() async throws {
        let store = RssFavoriteStore(fileURL: tempFileURL())
        try await store.add(sample(link: "https://a.com/article/1", title: "First"))
        try await store.add(sample(link: "https://a.com/article/2", title: "Second"))
        let all = try await store.all()
        XCTAssertEqual(all.map(\.title), ["Second", "First"])
    }

    func testIsFavoritedReflectsCurrentState() async throws {
        let store = RssFavoriteStore(fileURL: tempFileURL())
        let article = sample()
        var isFavorited = try await store.isFavorited(link: article.link)
        XCTAssertFalse(isFavorited)
        try await store.add(article)
        isFavorited = try await store.isFavorited(link: article.link)
        XCTAssertTrue(isFavorited)
    }

    func testRemoveDeletesByLink() async throws {
        let store = RssFavoriteStore(fileURL: tempFileURL())
        let article = sample()
        try await store.add(article)
        try await store.remove(link: article.link)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }
}
