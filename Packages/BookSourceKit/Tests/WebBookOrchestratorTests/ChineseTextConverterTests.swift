import XCTest
@testable import WebBookOrchestrator

final class ChineseTextConverterTests: XCTestCase {
    #if canImport(CoreFoundation)
    func testConvertsSimplifiedToTraditional() {
        XCTAssertEqual(ChineseTextConverter.convert("汉字", direction: .simplifiedToTraditional), "漢字")
    }

    func testConvertsTraditionalToSimplified() {
        XCTAssertEqual(ChineseTextConverter.convert("漢字", direction: .traditionalToSimplified), "汉字")
    }
    #else
    // No CoreFoundation on this platform (this Windows dev machine) -- confirms the graceful
    // no-op fallback doesn't crash or return something obviously broken. The real conversion is
    // only verified where CoreFoundation actually exists, i.e. the macOS CI runner.
    func testConvertReturnsNonEmptyResultWithoutCoreFoundation() {
        let result = ChineseTextConverter.convert("汉字", direction: .simplifiedToTraditional)
        XCTAssertFalse(result.isEmpty)
    }
    #endif

    func testConvertLeavesNonChineseTextUnchanged() {
        XCTAssertEqual(ChineseTextConverter.convert("Hello 123", direction: .simplifiedToTraditional), "Hello 123")
    }

    func testConvertHandlesEmptyString() {
        XCTAssertEqual(ChineseTextConverter.convert("", direction: .simplifiedToTraditional), "")
    }
}
