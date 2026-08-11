import XCTest
@testable import Persistence

final class ShelfGroupStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("shelf_groups.json")
    }

    func testAddThenListsIt() async throws {
        let store = ShelfGroupStore(fileURL: tempFileURL())
        try await store.add("游戏")
        let all = try await store.all()
        XCTAssertEqual(all, ["游戏"])
    }

    func testAddingSameNameTwiceDoesNotDuplicate() async throws {
        let store = ShelfGroupStore(fileURL: tempFileURL())
        try await store.add("游戏")
        try await store.add("游戏")
        let all = try await store.all()
        XCTAssertEqual(all, ["游戏"])
    }

    func testBlankNameIsIgnored() async throws {
        let store = ShelfGroupStore(fileURL: tempFileURL())
        try await store.add("   ")
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testRenameUpdatesExistingEntry() async throws {
        let store = ShelfGroupStore(fileURL: tempFileURL())
        try await store.add("游戏")
        try await store.rename("游戏", to: "网游")
        let all = try await store.all()
        XCTAssertEqual(all, ["网游"])
    }

    func testRenamingAnUnregisteredNameStillRegistersTheNewOne() async throws {
        let store = ShelfGroupStore(fileURL: tempFileURL())
        try await store.rename("游戏", to: "网游")
        let all = try await store.all()
        XCTAssertEqual(all, ["网游"])
    }

    func testRemoveDeletesTheEntry() async throws {
        let store = ShelfGroupStore(fileURL: tempFileURL())
        try await store.add("游戏")
        try await store.remove("游戏")
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testGroupsSurviveSimulatedAppRelaunch() async throws {
        let fileURL = tempFileURL()
        let session1 = ShelfGroupStore(fileURL: fileURL)
        try await session1.add("游戏")

        let session2 = ShelfGroupStore(fileURL: fileURL)
        let all = try await session2.all()
        XCTAssertEqual(all, ["游戏"])
    }
}
