import XCTest
@testable import BookSourceModel

final class RssSourceTests: XCTestCase {
    func testDecodesPreExistingSourceJSONMissingSortAndLoginURLFields() throws {
        let json = """
        {"sourceUrl": "https://a.com/feed", "sourceName": "A", "enabled": true}
        """
        let source = try JSONDecoder().decode(RssSource.self, from: Data(json.utf8))
        XCTAssertNil(source.sortUrl)
        XCTAssertNil(source.loginUrl)
    }

    func testSortAndLoginURLRoundTripThroughEncodeDecode() throws {
        let source = RssSource(
            sourceUrl: "https://a.com/feed", sourceName: "A",
            sortUrl: "科技::https://a.com/tech\n财经::https://a.com/finance", loginUrl: "https://a.com/login"
        )
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(RssSource.self, from: data)
        XCTAssertEqual(decoded.sortUrl, source.sortUrl)
        XCTAssertEqual(decoded.loginUrl, source.loginUrl)
    }
}
