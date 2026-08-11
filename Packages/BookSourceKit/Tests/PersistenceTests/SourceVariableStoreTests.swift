import XCTest
@testable import Persistence

final class SourceVariableStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("source_variables.json")
    }

    func testSetThenGetRoundTrips() async throws {
        let store = SourceVariableStore(fileURL: tempFileURL())
        try await store.setVariable("token=abc123", bookSourceUrl: "https://example.com")
        let value = try await store.variable(bookSourceUrl: "https://example.com")
        XCTAssertEqual(value, "token=abc123")
    }

    func testUnknownSourceReturnsNil() async throws {
        let store = SourceVariableStore(fileURL: tempFileURL())
        let value = try await store.variable(bookSourceUrl: "https://nowhere.example.com")
        XCTAssertNil(value)
    }

    func testSettingNilClearsTheVariable() async throws {
        let store = SourceVariableStore(fileURL: tempFileURL())
        try await store.setVariable("token=abc123", bookSourceUrl: "https://example.com")
        try await store.setVariable(nil, bookSourceUrl: "https://example.com")
        let value = try await store.variable(bookSourceUrl: "https://example.com")
        XCTAssertNil(value)
    }

    func testSettingEmptyStringClearsTheVariable() async throws {
        let store = SourceVariableStore(fileURL: tempFileURL())
        try await store.setVariable("token=abc123", bookSourceUrl: "https://example.com")
        try await store.setVariable("", bookSourceUrl: "https://example.com")
        let value = try await store.variable(bookSourceUrl: "https://example.com")
        XCTAssertNil(value)
    }

    func testVariableSurvivesSimulatedAppRelaunch() async throws {
        let fileURL = tempFileURL()
        let session1 = SourceVariableStore(fileURL: fileURL)
        try await session1.setVariable("token=abc123", bookSourceUrl: "https://example.com")

        let session2 = SourceVariableStore(fileURL: fileURL)
        let value = try await session2.variable(bookSourceUrl: "https://example.com")
        XCTAssertEqual(value, "token=abc123")
    }
}
