import XCTest
@testable import BookSourceModel

final class ExploreKindParserTests: XCTestCase {
    func testParsesNamedCategoriesSeparatedByDoubleColon() {
        let raw = "玄幻::https://example.com/fantasy\n都市::https://example.com/urban"
        let kinds = ExploreKindParser.parse(raw)
        XCTAssertEqual(kinds, [
            ExploreKind(name: "玄幻", url: "https://example.com/fantasy"),
            ExploreKind(name: "都市", url: "https://example.com/urban")
        ])
    }

    func testBareURLLineBecomesItsOwnUnnamedCategory() {
        let kinds = ExploreKindParser.parse("https://example.com/all")
        XCTAssertEqual(kinds, [ExploreKind(name: "https://example.com/all", url: "https://example.com/all")])
    }

    func testSkipsBlankLines() {
        let raw = "玄幻::https://example.com/fantasy\n\n\n都市::https://example.com/urban\n"
        let kinds = ExploreKindParser.parse(raw)
        XCTAssertEqual(kinds.count, 2)
    }

    func testTrimsWhitespaceAroundNameAndURL() {
        let kinds = ExploreKindParser.parse("  玄幻  ::  https://example.com/fantasy  ")
        XCTAssertEqual(kinds, [ExploreKind(name: "玄幻", url: "https://example.com/fantasy")])
    }

    func testEmptyInputProducesNoKinds() {
        XCTAssertTrue(ExploreKindParser.parse("").isEmpty)
        XCTAssertTrue(ExploreKindParser.parse("   \n  \n").isEmpty)
    }

    func testLineWithEmptyURLAfterSeparatorIsSkipped() {
        let kinds = ExploreKindParser.parse("玄幻::\n都市::https://example.com/urban")
        XCTAssertEqual(kinds, [ExploreKind(name: "都市", url: "https://example.com/urban")])
    }
}
