import XCTest
@testable import BookSourceModel

final class HttpTTSEngineTests: XCTestCase {
    func testSubstitutesAndPercentEncodesText() {
        let engine = HttpTTSEngine(name: "测试引擎", urlTemplate: "https://tts.example.com/speak?t={{text}}")
        let url = engine.url(forText: "hello world")
        XCTAssertEqual(url?.absoluteString, "https://tts.example.com/speak?t=hello%20world")
    }

    func testBlankTextReturnsNil() {
        let engine = HttpTTSEngine(name: "测试引擎", urlTemplate: "https://tts.example.com/speak?t={{text}}")
        XCTAssertNil(engine.url(forText: "   "))
    }

    func testParsedHeadersMergesOverDefaultUserAgent() {
        let engine = HttpTTSEngine(
            name: "测试引擎", urlTemplate: "https://tts.example.com/speak?t={{text}}",
            header: "{\"Referer\": \"https://tts.example.com\"}"
        )
        let headers = engine.parsedHeaders()
        XCTAssertEqual(headers["Referer"], "https://tts.example.com")
        XCTAssertEqual(headers["User-Agent"], BookSource.defaultUserAgent)
    }

    func testParsedHeadersDegradesToDefaultOnMalformedJSON() {
        let engine = HttpTTSEngine(name: "测试引擎", urlTemplate: "https://tts.example.com/speak?t={{text}}", header: "not json")
        XCTAssertEqual(engine.parsedHeaders(), ["User-Agent": BookSource.defaultUserAgent])
    }

    /// Migration-safety case: `header` didn't exist before this field was added -- guards that
    /// decoding an old `http_tts_engines.json` (missing the key entirely) doesn't throw.
    func testDecodesPreExistingEngineJSONMissingHeaderField() throws {
        let json = """
        {"id": "abc", "name": "测试引擎", "urlTemplate": "https://tts.example.com/speak?t={{text}}"}
        """
        let engine = try JSONDecoder().decode(HttpTTSEngine.self, from: Data(json.utf8))
        XCTAssertNil(engine.header)
    }
}
