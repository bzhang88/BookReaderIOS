import XCTest
@testable import WebBookOrchestrator

final class TxtChapterSplitterTests: XCTestCase {
    private typealias Chapter = TxtChapterSplitter.Chapter

    func testSplitsSimpleArabicNumeralChapters() {
        let text = """
        第1章 开始
        这是第一章的正文。
        第2章 风起
        这是第二章的正文。
        """
        let chapters = TxtChapterSplitter.split(text, fallbackTitle: "全文")
        XCTAssertEqual(chapters.map(\.title), ["第1章 开始", "第2章 风起"])
        XCTAssertTrue(chapters[0].text.contains("这是第一章的正文。"))
        XCTAssertTrue(chapters[1].text.contains("这是第二章的正文。"))
    }

    func testSplitsCJKNumeralChapters() {
        let text = """
        第一章 楔子
        正文一
        第二十三章 尾声
        正文二
        """
        let chapters = TxtChapterSplitter.split(text, fallbackTitle: "全文")
        XCTAssertEqual(chapters.map(\.title), ["第一章 楔子", "第二十三章 尾声"])
    }

    func testTextBeforeFirstHeadingBecomesPrefaceChapter() {
        let text = """
        内容简介：这是一本关于冒险的小说。
        第一章 出发
        正文
        """
        let chapters = TxtChapterSplitter.split(text, fallbackTitle: "全文")
        XCTAssertEqual(chapters.map(\.title), ["前言", "第一章 出发"])
        XCTAssertTrue(chapters[0].text.contains("内容简介"))
    }

    func testNoPrefaceChapterWhenTextStartsWithAHeading() {
        let text = """
        第一章 出发
        正文
        """
        let chapters = TxtChapterSplitter.split(text, fallbackTitle: "全文")
        XCTAssertEqual(chapters.map(\.title), ["第一章 出发"])
    }

    func testNoMatchesFallsBackToOneWholeChapter() {
        let text = "这是一段完全没有章节标题格式的文本，只是普通段落。"
        let chapters = TxtChapterSplitter.split(text, fallbackTitle: "全文")
        XCTAssertEqual(chapters, [Chapter(title: "全文", text: text)])
    }

    func testEmptyTextProducesNoChapters() {
        XCTAssertEqual(TxtChapterSplitter.split("", fallbackTitle: "全文"), [])
        XCTAssertEqual(TxtChapterSplitter.split("   \n\n  ", fallbackTitle: "全文"), [])
    }

    func testHandlesVolumeAndChapterMixedHeadings() {
        let text = """
        第一卷 少年游
        卷首语
        第一章 出场
        正文一
        第二章 离乡
        正文二
        """
        let chapters = TxtChapterSplitter.split(text, fallbackTitle: "全文")
        XCTAssertEqual(chapters.map(\.title), ["第一卷 少年游", "第一章 出场", "第二章 离乡"])
    }

    func testLastChapterRunsToEndOfText() {
        let text = """
        第一章 开始
        line one
        line two
        """
        let chapters = TxtChapterSplitter.split(text, fallbackTitle: "全文")
        XCTAssertEqual(chapters.count, 1)
        XCTAssertTrue(chapters[0].text.contains("line one"))
        XCTAssertTrue(chapters[0].text.contains("line two"))
    }
}
