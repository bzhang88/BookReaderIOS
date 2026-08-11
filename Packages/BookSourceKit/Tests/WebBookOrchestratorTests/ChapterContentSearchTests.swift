import XCTest
@testable import WebBookOrchestrator

final class ChapterContentSearchTests: XCTestCase {
    func testFindsMatchInEachChapterThatContainsKeyword() {
        let chapters: [(index: Int, title: String, text: String)] = [
            (index: 0, title: "第一章", text: "这是一段没有关键词的文字"),
            (index: 1, title: "第二章", text: "主角捡到了一把宝剑，非常开心"),
            (index: 2, title: "第三章", text: "又是没有命中的一章")
        ]
        let results = ChapterContentSearch.search(chapters: chapters, keyword: "宝剑")
        XCTAssertEqual(results.map(\.chapterIndex), [1])
        XCTAssertEqual(results.first?.chapterTitle, "第二章")
        XCTAssertTrue(results.first?.snippet.contains("宝剑") ?? false)
    }

    func testMatchIsCaseInsensitive() {
        let chapters: [(index: Int, title: String, text: String)] = [(index: 0, title: "Ch1", text: "The Dragon awakens")]
        let results = ChapterContentSearch.search(chapters: chapters, keyword: "dragon")
        XCTAssertEqual(results.count, 1)
    }

    func testEmptyOrWhitespaceKeywordReturnsNoResults() {
        let chapters: [(index: Int, title: String, text: String)] = [(index: 0, title: "Ch1", text: "some text")]
        XCTAssertTrue(ChapterContentSearch.search(chapters: chapters, keyword: "").isEmpty)
        XCTAssertTrue(ChapterContentSearch.search(chapters: chapters, keyword: "   ").isEmpty)
    }

    func testNoMatchAnywhereReturnsEmpty() {
        let chapters: [(index: Int, title: String, text: String)] = [(index: 0, title: "Ch1", text: "abc")]
        XCTAssertTrue(ChapterContentSearch.search(chapters: chapters, keyword: "xyz").isEmpty)
    }

    func testSnippetDoesNotCrashWhenMatchIsNearTextBoundaries() {
        let chapters: [(index: Int, title: String, text: String)] = [(index: 0, title: "Ch1", text: "hi")]
        let results = ChapterContentSearch.search(chapters: chapters, keyword: "hi")
        XCTAssertEqual(results.first?.snippet, "hi")
    }

    func testSnippetTruncatesLongTextWithEllipsis() {
        let text = String(repeating: "x", count: 50) + "NEEDLE" + String(repeating: "y", count: 50)
        let chapters: [(index: Int, title: String, text: String)] = [(index: 0, title: "Ch1", text: text)]
        let results = ChapterContentSearch.search(chapters: chapters, keyword: "NEEDLE")
        let snippet = results.first?.snippet ?? ""
        XCTAssertTrue(snippet.hasPrefix("…"))
        XCTAssertTrue(snippet.hasSuffix("…"))
        XCTAssertTrue(snippet.contains("NEEDLE"))
        XCTAssertLessThan(snippet.count, text.count)
    }

    func testPreservesChapterOrderFromInput() {
        let chapters: [(index: Int, title: String, text: String)] = [
            (index: 5, title: "Ch5", text: "match here"),
            (index: 2, title: "Ch2", text: "match here too")
        ]
        let results = ChapterContentSearch.search(chapters: chapters, keyword: "match")
        XCTAssertEqual(results.map(\.chapterIndex), [5, 2])
    }
}
