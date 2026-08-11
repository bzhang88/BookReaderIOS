import XCTest
@testable import Persistence

final class HttpTTSCacheTests: XCTestCase {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
    }

    // MARK: - Pure eviction logic

    func testFilesToEvictReturnsEmptyWhenUnderBudget() {
        let files = [(url: URL(fileURLWithPath: "/a"), modifiedAt: Date(), size: Int64(10))]
        XCTAssertTrue(HttpTTSCache.filesToEvict(files: files, maxTotalBytes: 100).isEmpty)
    }

    func testFilesToEvictRemovesOldestFirstUntilUnderBudget() {
        let now = Date()
        let files: [(url: URL, modifiedAt: Date, size: Int64)] = [
            (URL(fileURLWithPath: "/oldest"), now.addingTimeInterval(-300), 40),
            (URL(fileURLWithPath: "/middle"), now.addingTimeInterval(-200), 40),
            (URL(fileURLWithPath: "/newest"), now.addingTimeInterval(-100), 40)
        ]
        // total 120, budget 100 -- must evict "oldest" (leaves 80, under budget), not more.
        let toEvict = HttpTTSCache.filesToEvict(files: files, maxTotalBytes: 100)
        XCTAssertEqual(toEvict, [URL(fileURLWithPath: "/oldest")])
    }

    func testFilesToEvictCanRemoveMultipleFilesIfNeeded() {
        let now = Date()
        let files: [(url: URL, modifiedAt: Date, size: Int64)] = [
            (URL(fileURLWithPath: "/a"), now.addingTimeInterval(-300), 50),
            (URL(fileURLWithPath: "/b"), now.addingTimeInterval(-200), 50),
            (URL(fileURLWithPath: "/c"), now.addingTimeInterval(-100), 50)
        ]
        // total 150, budget 40 -- needs to evict a and b (leaves 50, still over 40... but stops
        // once remaining <= budget is no longer guaranteed each single step; verify the actual
        // trace: remaining starts 150 > 40 -> evict a (remaining 100) > 40 -> evict b (remaining 50)
        // > 40 -> evict c (remaining 0) <= 40 -> stop. All three evicted since budget is very tight.
        let toEvict = HttpTTSCache.filesToEvict(files: files, maxTotalBytes: 40)
        XCTAssertEqual(toEvict, [URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b"), URL(fileURLWithPath: "/c")])
    }

    // MARK: - Real file behavior

    func testStoreThenCachedFileURLRoundTrips() async throws {
        let cache = HttpTTSCache(directory: tempDirectory())
        let url = try await cache.store(engineID: "e1", text: "hello", audio: Data("fake-audio".utf8))
        let cached = await cache.cachedFileURL(engineID: "e1", text: "hello")
        XCTAssertEqual(cached, url)
        XCTAssertEqual(try? Data(contentsOf: url), Data("fake-audio".utf8))
    }

    func testCacheMissReturnsNil() async throws {
        let cache = HttpTTSCache(directory: tempDirectory())
        let cached = await cache.cachedFileURL(engineID: "e1", text: "never stored")
        XCTAssertNil(cached)
    }

    func testDifferentEnginesWithSameTextDoNotCollide() async throws {
        let cache = HttpTTSCache(directory: tempDirectory())
        try await cache.store(engineID: "e1", text: "hello", audio: Data("from-e1".utf8))
        try await cache.store(engineID: "e2", text: "hello", audio: Data("from-e2".utf8))
        let e1URL = await cache.cachedFileURL(engineID: "e1", text: "hello")
        let e2URL = await cache.cachedFileURL(engineID: "e2", text: "hello")
        XCTAssertNotEqual(e1URL, e2URL)
    }

    func testRemoveAllClearsCacheAndSizeGoesToZero() async throws {
        let cache = HttpTTSCache(directory: tempDirectory())
        try await cache.store(engineID: "e1", text: "hello", audio: Data("fake-audio".utf8))
        try await cache.removeAll()
        let total = await cache.totalSizeBytes()
        XCTAssertEqual(total, 0)
        let cached = await cache.cachedFileURL(engineID: "e1", text: "hello")
        XCTAssertNil(cached)
    }

    func testStoreEvictsOldestFileWhenOverBudget() async throws {
        let cache = HttpTTSCache(directory: tempDirectory(), maxTotalBytes: 15)
        _ = try await cache.store(engineID: "e1", text: "first", audio: Data(repeating: 0, count: 10))
        // Give the filesystem's mtime resolution room to distinguish write order (modern
        // filesystems -- APFS, NTFS -- resolve well under this; no need for a full second).
        try await Task.sleep(nanoseconds: 50_000_000)
        _ = try await cache.store(engineID: "e1", text: "second", audio: Data(repeating: 0, count: 10))

        let firstStillCached = await cache.cachedFileURL(engineID: "e1", text: "first")
        let secondStillCached = await cache.cachedFileURL(engineID: "e1", text: "second")
        XCTAssertNil(firstStillCached, "oldest entry should have been evicted once over budget")
        XCTAssertNotNil(secondStillCached)
    }
}
