import XCTest
import BookSourceModel
@testable import Persistence

final class AIProviderStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("ai_providers.json")
    }

    func testAddInsertsNewProvider() async throws {
        let store = AIProviderStore(fileURL: tempFileURL())
        try await store.add(AIProvider(name: "OpenAI", baseURL: "https://api.openai.com/v1", modelName: "gpt-4"))
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["OpenAI"])
    }

    func testAddWithExistingIDUpdatesInPlace() async throws {
        let store = AIProviderStore(fileURL: tempFileURL())
        let provider = AIProvider(name: "V1", baseURL: "https://a.com", modelName: "m1")
        try await store.add(provider)

        var edited = provider
        edited.name = "V2"
        try await store.add(edited)

        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "V2")
    }

    func testRemoveDeletesByID() async throws {
        let store = AIProviderStore(fileURL: tempFileURL())
        let provider = AIProvider(name: "ToDelete", baseURL: "https://a.com", modelName: "m")
        try await store.add(provider)
        try await store.remove(id: provider.id)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testPersistsAcrossStoreInstances() async throws {
        let fileURL = tempFileURL()
        let store = AIProviderStore(fileURL: fileURL)
        try await store.add(AIProvider(name: "Persisted", baseURL: "https://a.com", modelName: "m"))

        let reloaded = AIProviderStore(fileURL: fileURL)
        let all = try await reloaded.all()
        XCTAssertEqual(all.map(\.name), ["Persisted"])
    }
}
