import XCTest
@testable import BookSourceModel

final class BookSourceImportDecoderTests: XCTestCase {
    func testDecodesATopLevelArrayOfSources() throws {
        let json = """
        [
          {"bookSourceUrl": "https://a.example.com", "bookSourceName": "A"},
          {"bookSourceUrl": "https://b.example.com", "bookSourceName": "B"}
        ]
        """
        let sources = try BookSourceImportDecoder.decode(from: Data(json.utf8))
        XCTAssertEqual(sources.map(\.bookSourceName), ["A", "B"])
    }

    func testFallsBackToASingleBareSourceObject() throws {
        let json = """
        {"bookSourceUrl": "https://a.example.com", "bookSourceName": "A"}
        """
        let sources = try BookSourceImportDecoder.decode(from: Data(json.utf8))
        XCTAssertEqual(sources.map(\.bookSourceName), ["A"])
    }

    func testThrowsTheArrayDecodingErrorOnCompletelyInvalidJSON() {
        let json = "not json at all"
        XCTAssertThrowsError(try BookSourceImportDecoder.decode(from: Data(json.utf8)))
    }
}
