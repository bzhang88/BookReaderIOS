import XCTest
@testable import WebBookOrchestrator

final class ReadAloudTextFilterTests: XCTestCase {
    func testNormalTextIsSpeakable() {
        XCTAssertTrue(ReadAloudTextFilter.isSpeakable("他抬起头，看向远方。"))
    }

    func testEmptyTextIsNotSpeakable() {
        XCTAssertFalse(ReadAloudTextFilter.isSpeakable(""))
        XCTAssertFalse(ReadAloudTextFilter.isSpeakable("   "))
    }

    func testPunctuationOnlySceneBreakIsNotSpeakable() {
        XCTAssertFalse(ReadAloudTextFilter.isSpeakable("——"))
        XCTAssertFalse(ReadAloudTextFilter.isSpeakable("* * *"))
        XCTAssertFalse(ReadAloudTextFilter.isSpeakable("……"))
        XCTAssertFalse(ReadAloudTextFilter.isSpeakable("。！？"))
    }

    func testTextWithAtLeastOneRealCharacterIsSpeakable() {
        XCTAssertTrue(ReadAloudTextFilter.isSpeakable("——他说"))
    }

    func testWhitespaceSurroundedRealTextIsSpeakable() {
        XCTAssertTrue(ReadAloudTextFilter.isSpeakable("  你好  "))
    }
}
