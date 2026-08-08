import XCTest
@testable import Persistence

final class JSONFileStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("data.json")
    }

    func testLoadReturnsNilWhenFileDoesNotExist() async throws {
        let store = JSONFileStore<[String]>(fileURL: tempFileURL())
        let loaded = try await store.load()
        XCTAssertNil(loaded)
    }

    func testSaveThenLoadRoundTrips() async throws {
        let store = JSONFileStore<[String]>(fileURL: tempFileURL())
        try await store.save(["a", "b", "c"])
        let loaded = try await store.load()
        XCTAssertEqual(loaded, ["a", "b", "c"])
    }

    func testSaveCreatesIntermediateDirectories() async throws {
        let url = tempFileURL() // parent directory doesn't exist yet
        let store = JSONFileStore<[Int]>(fileURL: url)
        try await store.save([1, 2, 3])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSecondInstancePointingAtSameFileSeesSavedData() async throws {
        // Simulates "app relaunch": a brand new store instance, same file on disk.
        let url = tempFileURL()
        let writer = JSONFileStore<[String]>(fileURL: url)
        try await writer.save(["persisted"])

        let reader = JSONFileStore<[String]>(fileURL: url)
        let loaded = try await reader.load()
        XCTAssertEqual(loaded, ["persisted"])
    }
}
