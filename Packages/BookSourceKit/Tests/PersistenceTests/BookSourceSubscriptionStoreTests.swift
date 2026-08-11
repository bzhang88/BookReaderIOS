import XCTest
import BookSourceModel
@testable import Persistence

final class BookSourceSubscriptionStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("book_source_subscriptions.json")
    }

    func testAddPersistsANewSubscription() async throws {
        let store = BookSourceSubscriptionStore(fileURL: tempFileURL())
        try await store.add(BookSourceSubscription(name: "My Sub", url: "https://example.com/sources.json"))
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["My Sub"])
    }

    func testAddingSameIdTwiceUpdatesRatherThanDuplicates() async throws {
        let store = BookSourceSubscriptionStore(fileURL: tempFileURL())
        let sub = BookSourceSubscription(name: "Original", url: "https://example.com/sources.json")
        try await store.add(sub)
        var renamed = sub
        renamed.name = "Renamed"
        try await store.add(renamed)

        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Renamed")
    }

    func testRemoveDeletesByID() async throws {
        let store = BookSourceSubscriptionStore(fileURL: tempFileURL())
        let sub = BookSourceSubscription(name: "ToDelete", url: "https://example.com/sources.json")
        try await store.add(sub)
        try await store.remove(id: sub.id)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testSetLastUpdatedAtPersists() async throws {
        let fileURL = tempFileURL()
        let store = BookSourceSubscriptionStore(fileURL: fileURL)
        let sub = BookSourceSubscription(name: "My Sub", url: "https://example.com/sources.json")
        try await store.add(sub)

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.setLastUpdatedAt(id: sub.id, date: date)

        let reloaded = BookSourceSubscriptionStore(fileURL: fileURL)
        let all = try await reloaded.all()
        XCTAssertEqual(all.first?.lastUpdatedAt, date)
    }

    func testSetLastUpdatedAtForUnknownIdIsANoOp() async throws {
        let store = BookSourceSubscriptionStore(fileURL: tempFileURL())
        try await store.setLastUpdatedAt(id: "nope", date: Date())
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }
}
