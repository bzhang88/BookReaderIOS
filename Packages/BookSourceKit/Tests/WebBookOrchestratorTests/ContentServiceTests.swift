import XCTest
import BookSourceModel
@testable import WebBookOrchestrator

final class ContentServiceTests: XCTestCase {
    private func makeSource(nextContentUrl: String? = nil, replaceRegex: String? = nil, subContent: String? = nil) -> BookSource {
        var content = ContentRule()
        content.content = "@css:.content p@text"
        content.nextContentUrl = nextContentUrl
        content.replaceRegex = replaceRegex
        content.subContent = subContent
        return BookSource(bookSourceUrl: "https://example.com", bookSourceName: "Test Source", ruleContent: content)
    }

    private func chapter(url: String = "https://example.com/c/1", isVolume: Bool = false, tag: String? = nil, title: String = "Chapter 1") -> BookChapter {
        BookChapter(index: 0, title: title, url: url, isVolume: isVolume, tag: tag)
    }

    // MARK: - Basic extraction

    func testExtractsPlainTextParagraphsJoinedByNewline() async throws {
        let html = "<div class=\"content\"><p>First line.</p><p>Second line.</p></div>"
        let client = StubHTTPClient(responses: ["https://example.com/c/1": html])
        let result = try await ContentService.fetchContent(source: makeSource(), chapter: chapter(), httpClient: client)
        XCTAssertEqual(result.text, "First line.\nSecond line.")
    }

    func testHTMLKeywordExtractionIsConvertedToPlainText() async throws {
        let html = "<div class=\"content\"><p>First para.<br>with a break.</p></div>"
        let client = StubHTTPClient(responses: ["https://example.com/c/1": html])
        var source = makeSource()
        source.ruleContent?.content = "@css:.content@html"
        let result = try await ContentService.fetchContent(source: source, chapter: chapter(), httpClient: client)
        XCTAssertEqual(result.text, "First para.\nwith a break.")
    }

    // MARK: - Short circuits

    func testVolumeChapterReturnsTagWithoutFetching() async throws {
        let client = StubHTTPClient(responses: [:])
        let result = try await ContentService.fetchContent(
            source: makeSource(), chapter: chapter(isVolume: true, tag: "Part One"), httpClient: client
        )
        XCTAssertEqual(result.text, "Part One")
        let requested = await client.requestedURLs
        XCTAssertTrue(requested.isEmpty)
    }

    func testBlankContentRuleReturnsChapterURLWithoutFetching() async throws {
        let client = StubHTTPClient(responses: [:])
        var source = makeSource()
        source.ruleContent?.content = ""
        let result = try await ContentService.fetchContent(source: source, chapter: chapter(), httpClient: client)
        XCTAssertEqual(result.text, "https://example.com/c/1")
        let requested = await client.requestedURLs
        XCTAssertTrue(requested.isEmpty)
    }

    // MARK: - Pagination (same 3-way branch as TocService)

    func testSerialContentPaginationAcrossTwoPages() async throws {
        let page1 = """
        <div class="content"><p>Page one text.</p></div>
        <a class="next" href="/c/1?p=2">Next</a>
        """
        let page2 = "<div class=\"content\"><p>Page two text.</p></div>"
        let client = StubHTTPClient(responses: [
            "https://example.com/c/1": page1,
            "https://example.com/c/1?p=2": page2
        ])
        let source = makeSource(nextContentUrl: "@css:.next@href")
        let result = try await ContentService.fetchContent(source: source, chapter: chapter(), httpClient: client)
        XCTAssertEqual(result.text, "Page one text.\nPage two text.")
    }

    // Real book-source data (imported into this app's own library) has sources whose
    // `nextContentUrl` rule literally reads `text.下一章@href` -- "next *chapter*", not "next page" --
    // because on that source's last content page of a chapter, the page-turn button and the
    // next-chapter button are the exact same link. Without this guard, `ContentService` would follow
    // it anyway (it's a URL like any other to the pagination loop) and keep chaining through every
    // remaining chapter in the book, appending the entire rest of it into what's nominally one
    // chapter. Legado guards against exactly this (`nextUrl == nextChapterUrl` stops rather than
    // follows); `nextChapterUrl` here is that same guard.
    func testContentPaginationStopsWhenNextContentUrlIsActuallyTheNextChapter() async throws {
        let page1 = """
        <div class="content"><p>Last page of chapter 1.</p></div>
        <a class="next" href="/c/2">下一章</a>
        """
        let chapter2 = "<div class=\"content\"><p>All of chapter 2's text.</p></div>"
        let client = StubHTTPClient(responses: [
            "https://example.com/c/1": page1,
            "https://example.com/c/2": chapter2
        ])
        let source = makeSource(nextContentUrl: "@css:.next@href")
        let result = try await ContentService.fetchContent(
            source: source, chapter: chapter(), httpClient: client, nextChapterUrl: "https://example.com/c/2"
        )
        XCTAssertEqual(result.text, "Last page of chapter 1.")
        let requested = await client.requestedURLs
        XCTAssertFalse(requested.contains("https://example.com/c/2"))
    }

    // Same guard, genuine in-chapter pagination case: the scraped "next" URL does NOT match
    // `nextChapterUrl`, so it's followed and appended exactly like `testSerialContentPaginationAcrossTwoPages`
    // -- confirms the guard only suppresses the one specific URL, not pagination in general.
    func testContentPaginationStillFollowsGenuineNextPageWhenNextChapterUrlDiffers() async throws {
        let page1 = """
        <div class="content"><p>Page one text.</p></div>
        <a class="next" href="/c/1?p=2">下一页</a>
        """
        let page2 = "<div class=\"content\"><p>Page two text.</p></div>"
        let client = StubHTTPClient(responses: [
            "https://example.com/c/1": page1,
            "https://example.com/c/1?p=2": page2
        ])
        let source = makeSource(nextContentUrl: "@css:.next@href")
        let result = try await ContentService.fetchContent(
            source: source, chapter: chapter(), httpClient: client, nextChapterUrl: "https://example.com/c/2"
        )
        XCTAssertEqual(result.text, "Page one text.\nPage two text.")
    }

    func testConcurrentContentPaginationPreservesOrder() async throws {
        let page1 = """
        <div class="content"><p>Page one.</p></div>
        <a class="pg" href="/c/1?p=2">2</a>
        <a class="pg" href="/c/1?p=3">3</a>
        """
        let page2 = "<div class=\"content\"><p>Page two.</p></div>"
        let page3 = "<div class=\"content\"><p>Page three.</p></div>"
        let client = StubHTTPClient(responses: [
            "https://example.com/c/1": page1,
            "https://example.com/c/1?p=2": page2,
            "https://example.com/c/1?p=3": page3
        ])
        let source = makeSource(nextContentUrl: "@css:.pg@href")
        let result = try await ContentService.fetchContent(source: source, chapter: chapter(), httpClient: client)
        XCTAssertEqual(result.text, "Page one.\nPage two.\nPage three.")
    }

    // MARK: - replaceRegex (verified against real Legado behavior: applied once to the whole
    // trimmed-and-joined text, then every line -- including blank ones -- gets a 　　 indent)

    func testReplaceRegexPurifiesAndIndentsEveryLine() async throws {
        let html = "<div class=\"content\"><p>Hello[AD]</p><p>World[AD]</p></div>"
        let client = StubHTTPClient(responses: ["https://example.com/c/1": html])
        let source = makeSource(replaceRegex: "##\\[AD\\]")
        let result = try await ContentService.fetchContent(source: source, chapter: chapter(), httpClient: client)
        XCTAssertEqual(result.text, "\u{3000}\u{3000}Hello\n\u{3000}\u{3000}World")
    }

    func testReplaceRegexWithExplicitReplacementTemplate() async throws {
        let html = "<div class=\"content\"><p>chapter[1]</p></div>"
        let client = StubHTTPClient(responses: ["https://example.com/c/1": html])
        let source = makeSource(replaceRegex: "##\\[(\\d+)\\]##($1)")
        let result = try await ContentService.fetchContent(source: source, chapter: chapter(), httpClient: client)
        XCTAssertEqual(result.text, "\u{3000}\u{3000}chapter(1)")
    }

    func testReplaceRegexWithoutLeadingHashHashIsIgnored() async throws {
        // No "##" at all means it can't be parsed as a regex suffix (matches real behavior: a
        // bare pattern with no selector-escape would otherwise misparse as a CSS selector) --
        // degrade to leaving the text untouched rather than guessing.
        let html = "<div class=\"content\"><p>Hello[AD]</p></div>"
        let client = StubHTTPClient(responses: ["https://example.com/c/1": html])
        let source = makeSource(replaceRegex: "\\[AD\\]")
        let result = try await ContentService.fetchContent(source: source, chapter: chapter(), httpClient: client)
        XCTAssertEqual(result.text, "Hello[AD]")
    }

    // MARK: - subContent

    func testLiteralSubContentIsAppended() async throws {
        let html = """
        <div class="content"><p>Main text.</p></div>
        <div class="extra">Extra footnote.</div>
        """
        let client = StubHTTPClient(responses: ["https://example.com/c/1": html])
        let source = makeSource(subContent: "@css:.extra@text")
        let result = try await ContentService.fetchContent(source: source, chapter: chapter(), httpClient: client)
        XCTAssertEqual(result.text, "Main text.\nExtra footnote.")
    }

    // MARK: - title override (content-page-only chapter title, rare but supported)

    func testTitleRuleOverridesChapterTitle() async throws {
        let html = """
        <h1 class="real-title">The Actual Chapter Title</h1>
        <div class="content"><p>Body text.</p></div>
        """
        let client = StubHTTPClient(responses: ["https://example.com/c/1": html])
        var source = makeSource()
        source.ruleContent?.title = "@css:.real-title@text"
        let result = try await ContentService.fetchContent(source: source, chapter: chapter(), httpClient: client)
        XCTAssertEqual(result.titleOverride, "The Actual Chapter Title")
        XCTAssertEqual(result.text, "Body text.")
    }

    func testURLSubContentIsFetchedAndAppended() async throws {
        let html = """
        <div class="content"><p>Main text.</p></div>
        <a class="extra-link" href="https://example.com/extra.txt">extra</a>
        """
        let client = StubHTTPClient(responses: [
            "https://example.com/c/1": html,
            "https://example.com/extra.txt": "Fetched extra content."
        ])
        let source = makeSource(subContent: "@css:.extra-link@href")
        let result = try await ContentService.fetchContent(source: source, chapter: chapter(), httpClient: client)
        XCTAssertEqual(result.text, "Main text.\nFetched extra content.")
    }
}
