import XCTest
@testable import WebBookOrchestrator

final class ShelfListEntryTests: XCTestCase {
    func testEncodeThenDecodeRoundTrips() {
        let entries = [
            ShelfListEntry(name: "斗破苍穹", author: "天蚕土豆", intro: "简介"),
            ShelfListEntry(name: "无名书", author: nil, intro: nil)
        ]
        let json = ShelfListFormat.encode(entries)
        XCTAssertEqual(ShelfListFormat.decode(json), entries)
    }

    /// Matches Legado_Max's real export shape (`BookshelfViewModel.exportBookshelf`):
    /// `[{"name":..., "author":..., "intro":...}, ...]` -- a list exported from a real Legado
    /// install should import here without any translation step.
    func testDecodesLegadoStyleJSONArray() {
        let json = """
        [{"name": "斗破苍穹", "author": "天蚕土豆", "intro": "一个关于..."}]
        """
        let entries = ShelfListFormat.decode(json)
        XCTAssertEqual(entries, [ShelfListEntry(name: "斗破苍穹", author: "天蚕土豆", intro: "一个关于...")])
    }

    func testDecodesEntryMissingOptionalFields() {
        let json = #"[{"name": "无名书"}]"#
        XCTAssertEqual(ShelfListFormat.decode(json), [ShelfListEntry(name: "无名书")])
    }

    func testMalformedJSONReturnsNilRatherThanEmptyArray() {
        XCTAssertNil(ShelfListFormat.decode("not json at all"))
    }

    func testPlainJSONObjectRatherThanArrayReturnsNil() {
        XCTAssertNil(ShelfListFormat.decode(#"{"name": "斗破苍穹"}"#))
    }
}
