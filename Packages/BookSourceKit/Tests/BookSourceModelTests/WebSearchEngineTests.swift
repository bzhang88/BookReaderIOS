import XCTest
@testable import BookSourceModel

final class WebSearchEngineTests: XCTestCase {
    func testSubstitutesAndPercentEncodesQuery() {
        let engine = WebSearchEngine(name: "测试", urlTemplate: "https://example.com/search?q={{query}}")
        let url = engine.url(forQuery: "hello world")
        XCTAssertEqual(url?.absoluteString, "https://example.com/search?q=hello%20world")
    }

    func testEncodesNonASCIIQuery() {
        let engine = WebSearchEngine(name: "测试", urlTemplate: "https://example.com/search?q={{query}}")
        let url = engine.url(forQuery: "凡人修仙传")
        XCTAssertEqual(url?.absoluteString, "https://example.com/search?q=%E5%87%A1%E4%BA%BA%E4%BF%AE%E4%BB%99%E4%BC%A0")
    }

    func testBlankQueryReturnsNil() {
        let engine = WebSearchEngine(name: "测试", urlTemplate: "https://example.com/search?q={{query}}")
        XCTAssertNil(engine.url(forQuery: "   "))
    }

    func testDefaultsIncludeBingAndBaidu() {
        XCTAssertEqual(WebSearchEngine.defaults.map(\.name), ["必应", "百度"])
    }
}
