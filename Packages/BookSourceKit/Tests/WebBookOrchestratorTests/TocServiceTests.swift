import XCTest
import BookSourceModel
@testable import WebBookOrchestrator

final class TocServiceTests: XCTestCase {
    private func makeSource(nextTocUrl: String? = nil, chapterListPrefix: String = "") -> BookSource {
        var toc = TocRule()
        toc.chapterList = chapterListPrefix + "@css:.toc li"
        toc.chapterName = "@css:a@text"
        toc.chapterUrl = "@css:a@href"
        toc.updateTime = "@css:a@data-tag"
        toc.isVip = "@css:a@data-vip"
        toc.nextTocUrl = nextTocUrl

        return BookSource(
            bookSourceUrl: "https://example.com",
            bookSourceName: "Test Source",
            ruleToc: toc
        )
    }

    // MARK: - Zero next-page URLs: single page, done

    func testSinglePageNoNextURL() async throws {
        let html = """
        <div class="toc">
          <li><a href="/c/1">Chapter 1</a></li>
          <li><a href="/c/2">Chapter 2</a></li>
        </div>
        """
        let client = StubHTTPClient(responses: ["https://example.com/toc": html])
        let chapters = try await TocService.fetchChapterList(
            source: makeSource(), tocURL: "https://example.com/toc", httpClient: client
        )
        XCTAssertEqual(chapters.map(\.title), ["Chapter 1", "Chapter 2"])
        XCTAssertEqual(chapters.map(\.url), ["https://example.com/c/1", "https://example.com/c/2"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
    }

    // MARK: - Exactly one next-page URL: serial "follow the link" pagination

    func testSerialPaginationFollowsSingleNextLinkAcrossThreePages() async throws {
        let page1 = """
        <div class="toc"><li><a href="/c/1">Chapter 1</a></li></div>
        <a class="next" href="/toc?p=2">Next</a>
        """
        let page2 = """
        <div class="toc"><li><a href="/c/2">Chapter 2</a></li></div>
        <a class="next" href="/toc?p=3">Next</a>
        """
        let page3 = """
        <div class="toc"><li><a href="/c/3">Chapter 3</a></li></div>
        """
        let client = StubHTTPClient(responses: [
            "https://example.com/toc": page1,
            "https://example.com/toc?p=2": page2,
            "https://example.com/toc?p=3": page3
        ])
        let source = makeSource(nextTocUrl: "@css:.next@href")
        let chapters = try await TocService.fetchChapterList(
            source: source, tocURL: "https://example.com/toc", httpClient: client
        )
        XCTAssertEqual(chapters.map(\.title), ["Chapter 1", "Chapter 2", "Chapter 3"])
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2])
    }

    func testSerialPaginationGuardsAgainstRevisitingAPage() async throws {
        // page1 -> page2 -> page1 (a broken source looping back on itself); must not hang.
        let page1 = """
        <div class="toc"><li><a href="/c/1">Chapter 1</a></li></div>
        <a class="next" href="/toc?p=2">Next</a>
        """
        let page2 = """
        <div class="toc"><li><a href="/c/2">Chapter 2</a></li></div>
        <a class="next" href="/toc">Next</a>
        """
        let client = StubHTTPClient(responses: [
            "https://example.com/toc": page1,
            "https://example.com/toc?p=2": page2
        ])
        let source = makeSource(nextTocUrl: "@css:.next@href")
        let chapters = try await TocService.fetchChapterList(
            source: source, tocURL: "https://example.com/toc", httpClient: client
        )
        XCTAssertEqual(chapters.map(\.title), ["Chapter 1", "Chapter 2"])
    }

    // MARK: - Two-or-more next-page URLs: explicit array, fetched concurrently, order preserved

    func testConcurrentPaginationForExplicitPageArray() async throws {
        let page1 = """
        <div class="toc"><li><a href="/c/1">Chapter 1</a></li></div>
        <a class="pg" href="/toc?p=2">2</a>
        <a class="pg" href="/toc?p=3">3</a>
        """
        let page2 = "<div class=\"toc\"><li><a href=\"/c/2\">Chapter 2</a></li></div>"
        let page3 = "<div class=\"toc\"><li><a href=\"/c/3\">Chapter 3</a></li></div>"
        let client = StubHTTPClient(responses: [
            "https://example.com/toc": page1,
            "https://example.com/toc?p=2": page2,
            "https://example.com/toc?p=3": page3
        ])
        let source = makeSource(nextTocUrl: "@css:.pg@href")
        let chapters = try await TocService.fetchChapterList(
            source: source, tocURL: "https://example.com/toc", httpClient: client
        )
        // Order must follow the page list order (2 before 3), even though fetched concurrently.
        XCTAssertEqual(chapters.map(\.title), ["Chapter 1", "Chapter 2", "Chapter 3"])
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2])
    }

    // MARK: - Reversal, dedup, and flag fields

    func testLeadingDashReversesFinalList() async throws {
        let html = """
        <div class="toc">
          <li><a href="/c/1">Chapter 1</a></li>
          <li><a href="/c/2">Chapter 2</a></li>
          <li><a href="/c/3">Chapter 3</a></li>
        </div>
        """
        let client = StubHTTPClient(responses: ["https://example.com/toc": html])
        let chapters = try await TocService.fetchChapterList(
            source: makeSource(chapterListPrefix: "-"), tocURL: "https://example.com/toc", httpClient: client
        )
        XCTAssertEqual(chapters.map(\.title), ["Chapter 3", "Chapter 2", "Chapter 1"])
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2])
    }

    func testDuplicateChapterURLsAcrossPagesAreDeduped() async throws {
        let page1 = """
        <div class="toc"><li><a href="/c/1">Chapter 1</a></li></div>
        <a class="next" href="/toc?p=2">Next</a>
        """
        // page2 accidentally repeats chapter 1 before its own new chapter.
        let page2 = """
        <div class="toc">
          <li><a href="/c/1">Chapter 1</a></li>
          <li><a href="/c/2">Chapter 2</a></li>
        </div>
        """
        let client = StubHTTPClient(responses: [
            "https://example.com/toc": page1,
            "https://example.com/toc?p=2": page2
        ])
        let source = makeSource(nextTocUrl: "@css:.next@href")
        let chapters = try await TocService.fetchChapterList(
            source: source, tocURL: "https://example.com/toc", httpClient: client
        )
        XCTAssertEqual(chapters.map(\.url), ["https://example.com/c/1", "https://example.com/c/2"])
    }

    func testVipFlagParsedViaIsTrueConvention() async throws {
        let html = """
        <div class="toc">
          <li><a href="/c/1" data-vip="1">Chapter 1</a></li>
          <li><a href="/c/2" data-vip="false">Chapter 2</a></li>
        </div>
        """
        let client = StubHTTPClient(responses: ["https://example.com/toc": html])
        let chapters = try await TocService.fetchChapterList(
            source: makeSource(), tocURL: "https://example.com/toc", httpClient: client
        )
        XCTAssertEqual(chapters.map(\.isVip), [true, false])
    }

    func testEmptyChapterListRuleReturnsEmptyWithoutFetching() async throws {
        let client = StubHTTPClient(responses: [:])
        var toc = TocRule()
        toc.chapterList = ""
        let source = BookSource(bookSourceUrl: "https://example.com", bookSourceName: "X", ruleToc: toc)
        let chapters = try await TocService.fetchChapterList(
            source: source, tocURL: "https://example.com/toc", httpClient: client
        )
        XCTAssertEqual(chapters, [])
        let requested = await client.requestedURLs
        XCTAssertTrue(requested.isEmpty)
    }
}
