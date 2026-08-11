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
}
