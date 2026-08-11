import XCTest
import BookSourceModel
@testable import Persistence

final class HttpTTSEngineStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("http_tts_engines.json")
    }

    func testAddPersistsANewEngine() async throws {
        let store = HttpTTSEngineStore(fileURL: tempFileURL())
        try await store.add(HttpTTSEngine(name: "云朗读", urlTemplate: "https://tts.example.com/speak?t={{text}}"))
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["云朗读"])
    }

    func testRemoveDeletesByID() async throws {
        let store = HttpTTSEngineStore(fileURL: tempFileURL())
        let engine = HttpTTSEngine(name: "云朗读", urlTemplate: "https://tts.example.com/speak?t={{text}}")
        try await store.add(engine)
        try await store.remove(id: engine.id)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testAddingSameIDUpdatesInPlace() async throws {
        let store = HttpTTSEngineStore(fileURL: tempFileURL())
        var engine = HttpTTSEngine(name: "云朗读", urlTemplate: "https://tts.example.com/speak?t={{text}}")
        try await store.add(engine)
        engine.name = "云朗读 v2"
        try await store.add(engine)
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["云朗读 v2"])
    }
}
