import XCTest
@testable import BookSourceModel

final class LegadoImportDecodingTests: XCTestCase {
    private struct Item: Codable, Equatable {
        var name: String
    }

    func testDecodesTopLevelArray() throws {
        let data = Data(#"[{"name":"a"},{"name":"b"}]"#.utf8)
        let items = try LegadoImportDecoding.decodeArrayOrSingle(Item.self, from: data)
        XCTAssertEqual(items, [Item(name: "a"), Item(name: "b")])
    }

    func testToleratesABareSingleObject() throws {
        let data = Data(#"{"name":"solo"}"#.utf8)
        let items = try LegadoImportDecoding.decodeArrayOrSingle(Item.self, from: data)
        XCTAssertEqual(items, [Item(name: "solo")])
    }

    func testThrowsTheArrayDecodingErrorNotTheFallbacksConfusingOne() throws {
        // A malformed array (missing a required field in one element) should surface an error
        // about *that*, not the generic "expected Dictionary, found array" from the failed
        // single-object fallback attempt.
        let data = Data(#"[{"name":"a"},{"wrongKey":"b"}]"#.utf8)
        XCTAssertThrowsError(try LegadoImportDecoding.decodeArrayOrSingle(Item.self, from: data))
    }
}
