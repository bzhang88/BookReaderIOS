import XCTest
import BookSourceModel
@testable import WebBookOrchestrator

final class SourceValidationServiceTests: XCTestCase {
    private func makeFullPipelineSource() -> BookSource {
        var search = SearchRule()
        search.bookList = "@css:.item"
        search.name = "@css:.name@text"
        search.bookUrl = "@css:.name@href"

        var info = BookInfoRule()
        info.name = "@css:.title@text"
        info.tocUrl = "@css:.toc-link@href"

        var toc = TocRule()
        toc.chapterList = "@css:.toc li"
        toc.chapterName = "@css:a@text"
        toc.chapterUrl = "@css:a@href"

        var content = ContentRule()
        content.content = "@css:.content p@text"

        return BookSource(
            bookSourceUrl: "https://example.com", bookSourceName: "Full Pipeline Source",
            searchUrl: "https://example.com/search?wd=fixed",
            ruleSearch: search, ruleBookInfo: info, ruleToc: toc, ruleContent: content
        )
    }

    private func stubbedClient() -> StubHTTPClient {
        StubHTTPClient(responses: [
            "https://example.com/search?wd=fixed": """
            <html><body><ul><li class="item"><a class="name" href="/book/1">Novel One</a></li></ul></body></html>
            """,
            "https://example.com/book/1": """
            <html><body><h1 class="title">Novel One</h1><a class="toc-link" href="/book/1/toc">TOC</a></body></html>
            """,
            "https://example.com/book/1/toc": """
            <div class="toc"><li><a href="/c/1">Chapter 1</a></li></div>
            """,
            "https://example.com/c/1": """
            <div class="content"><p>Chapter text.</p></div>
            """
        ])
    }

    private func collect(_ stream: AsyncStream<SourceValidationOutcome>) async -> [SourceValidationOutcome] {
        var outcomes: [SourceValidationOutcome] = []
        for await outcome in stream { outcomes.append(outcome) }
        return outcomes
    }

    func testSearchOnlyDepthOnlyRunsSearchStage() async throws {
        let source = makeFullPipelineSource()
        let client = stubbedClient()
        let outcomes = await collect(
            SourceValidationService.validate(sources: [source], keyword: "novel", depth: .search, httpClient: client)
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].stageResults.map(\.stage), [.search])
        XCTAssertTrue(outcomes[0].stageResults[0].success)
    }

    func testContentDepthRunsAllFourStagesInOrder() async throws {
        let source = makeFullPipelineSource()
        let client = stubbedClient()
        let outcomes = await collect(
            SourceValidationService.validate(sources: [source], keyword: "novel", depth: .content, httpClient: client)
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].stageResults.map(\.stage), [.search, .detail, .toc, .content])
        XCTAssertTrue(outcomes[0].isFullyPassing)
    }

    func testStopsAtFirstFailingStageRatherThanContinuing() async throws {
        let source = makeFullPipelineSource()
        // No stubbed response for the search URL -- StubHTTPClient throws for unknown URLs.
        let client = StubHTTPClient(responses: [:])
        let outcomes = await collect(
            SourceValidationService.validate(sources: [source], keyword: "novel", depth: .content, httpClient: client)
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].stageResults.map(\.stage), [.search])
        XCTAssertFalse(outcomes[0].stageResults[0].success)
        XCTAssertFalse(outcomes[0].isFullyPassing)
    }

    func testEmptySearchResultsStopsBeforeDetailEvenAtDeeperDepth() async throws {
        var source = makeFullPipelineSource()
        source.ruleSearch?.bookList = "@css:.nonexistent"
        let client = stubbedClient()
        let outcomes = await collect(
            SourceValidationService.validate(sources: [source], keyword: "novel", depth: .content, httpClient: client)
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].stageResults.map(\.stage), [.search])
        XCTAssertFalse(outcomes[0].stageResults[0].success, "zero results counts as a search failure for validation purposes")
    }

    func testValidatesMultipleSourcesIndependently() async throws {
        let good = makeFullPipelineSource()
        var bad = makeFullPipelineSource()
        bad.bookSourceUrl = "https://bad.example.com"
        bad.searchUrl = "https://bad.example.com/search?wd=fixed"

        let client = stubbedClient()
        let outcomes = await collect(
            SourceValidationService.validate(sources: [good, bad], keyword: "novel", depth: .search, httpClient: client)
        )
        XCTAssertEqual(outcomes.count, 2)
        let goodOutcome = outcomes.first { $0.source.bookSourceUrl == "https://example.com" }
        let badOutcome = outcomes.first { $0.source.bookSourceUrl == "https://bad.example.com" }
        XCTAssertEqual(goodOutcome?.stageResults.first?.success, true)
        XCTAssertEqual(badOutcome?.stageResults.first?.success, false)
    }
}
