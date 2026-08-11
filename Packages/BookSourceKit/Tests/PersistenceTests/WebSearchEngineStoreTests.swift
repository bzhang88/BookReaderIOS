import XCTest
import BookSourceModel
@testable import Persistence

final class WebSearchEngineStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("web_search_engines.json")
    }

    func testAddPersistsANewEngine() async throws {
        let store = WebSearchEngineStore(fileURL: tempFileURL())
        try await store.add(WebSearchEngine(name: "Google", urlTemplate: "https://google.com/search?q={{query}}"))
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["Google"])
    }

    func testRemoveDeletesByID() async throws {
        let store = WebSearchEngineStore(fileURL: tempFileURL())
        let engine = WebSearchEngine(name: "Google", urlTemplate: "https://google.com/search?q={{query}}")
        try await store.add(engine)
        try await store.remove(id: engine.id)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testAddingSameIDUpdatesInPlace() async throws {
        let store = WebSearchEngineStore(fileURL: tempFileURL())
        var engine = WebSearchEngine(name: "Google", urlTemplate: "https://google.com/search?q={{query}}")
        try await store.add(engine)
        engine.name = "Google v2"
        try await store.add(engine)
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["Google v2"])
    }
}
