import XCTest
@testable import WebBookOrchestrator

final class TxtExporterTests: XCTestCase {
    func testCombineIncludesBookTitleAndAllChapters() {
        let chapters: [(title: String, text: String)] = [
            (title: "第一章 开始", text: "正文一"),
            (title: "第二章 继续", text: "正文二")
        ]
        let combined = TxtExporter.combine(bookTitle: "我的小说", chapters: chapters)
        XCTAssertTrue(combined.contains("我的小说"))
        XCTAssertTrue(combined.contains("第一章 开始"))
        XCTAssertTrue(combined.contains("正文一"))
        XCTAssertTrue(combined.contains("第二章 继续"))
        XCTAssertTrue(combined.contains("正文二"))
    }

    func testCombinePreservesChapterOrder() {
        let chapters: [(title: String, text: String)] = [
            (title: "Ch1", text: "a"),
            (title: "Ch2", text: "b")
        ]
        let combined = TxtExporter.combine(bookTitle: "T", chapters: chapters)
        let ch1Range = combined.range(of: "Ch1")!
        let ch2Range = combined.range(of: "Ch2")!
        XCTAssertLessThan(ch1Range.lowerBound, ch2Range.lowerBound)
    }

    func testCombineWithNoChaptersStillIncludesTitle() {
        let combined = TxtExporter.combine(bookTitle: "空书", chapters: [])
        XCTAssertTrue(combined.contains("空书"))
    }

    func testSanitizedFileNameStripsInvalidCharacters() {
        XCTAssertEqual(TxtExporter.sanitizedFileName("a/b\\c:d*e?f\"g<h>i|j"), "a_b_c_d_e_f_g_h_i_j")
    }

    func testSanitizedFileNameLeavesNormalTitlesUnchanged() {
        XCTAssertEqual(TxtExporter.sanitizedFileName("我的小说 第一部"), "我的小说 第一部")
    }

    func testSanitizedFileNameFallsBackForEmptyResult() {
        XCTAssertEqual(TxtExporter.sanitizedFileName(""), "导出")
        XCTAssertEqual(TxtExporter.sanitizedFileName("   "), "导出")
    }
}
