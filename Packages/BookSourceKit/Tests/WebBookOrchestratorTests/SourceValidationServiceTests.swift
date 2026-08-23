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
            // The bare base URL -- the new domain-reachability check's target. Any stubbed response
            // (regardless of content) is enough for it to count as "reachable."
            "https://example.com": "<html><body>ok</body></html>",
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
        // .domain always runs first, ahead of whatever `depth` was configured -- see
        // `SourceValidationStage`'s own doc comment for why it's not part of the depth chain.
        XCTAssertEqual(outcomes[0].stageResults.map(\.stage), [.domain, .search])
        XCTAssertTrue(outcomes[0].stageResults.allSatisfy(\.success))
    }

    func testContentDepthRunsAllFourStagesInOrder() async throws {
        let source = makeFullPipelineSource()
        let client = stubbedClient()
        let outcomes = await collect(
            SourceValidationService.validate(sources: [source], keyword: "novel", depth: .content, httpClient: client)
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].stageResults.map(\.stage), [.domain, .search, .detail, .toc, .content])
        XCTAssertTrue(outcomes[0].isFullyPassing)
    }

    func testDomainUnreachableAbortsBeforeEverAttemptingSearch() async throws {
        let source = makeFullPipelineSource()
        // Nothing stubbed at all -- StubHTTPClient throws for unknown URLs, including the bare
        // base URL the domain check hits first.
        let client = StubHTTPClient(responses: [:])
        let outcomes = await collect(
            SourceValidationService.validate(sources: [source], keyword: "novel", depth: .content, httpClient: client)
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].stageResults.map(\.stage), [.domain], "search should never even be attempted")
        XCTAssertFalse(outcomes[0].stageResults[0].success)
        XCTAssertFalse(outcomes[0].isFullyPassing)
    }

    func testStopsAtFirstFailingStageRatherThanContinuing() async throws {
        let source = makeFullPipelineSource()
        // Domain resolves, but nothing else is stubbed -- search should fail and the chain should
        // stop there, before ever attempting detail.
        let client = StubHTTPClient(responses: ["https://example.com": "<html></html>"])
        let outcomes = await collect(
            SourceValidationService.validate(sources: [source], keyword: "novel", depth: .content, httpClient: client)
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].stageResults.map(\.stage), [.domain, .search])
        XCTAssertTrue(outcomes[0].stageResults[0].success)
        XCTAssertFalse(outcomes[0].stageResults[1].success)
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
        XCTAssertEqual(outcomes[0].stageResults.map(\.stage), [.domain, .search])
        XCTAssertFalse(outcomes[0].stageResults[1].success, "zero results counts as a search failure for validation purposes")
    }

    func testValidatesMultipleSourcesIndependently() async throws {
        let good = makeFullPipelineSource()
        var bad = makeFullPipelineSource()
        bad.bookSourceUrl = "https://bad.example.com"
        bad.searchUrl = "https://bad.example.com/search?wd=fixed"

        let client = StubHTTPClient(responses: [
            "https://example.com": "<html></html>",
            "https://example.com/search?wd=fixed": """
            <html><body><ul><li class="item"><a class="name" href="/book/1">Novel One</a></li></ul></body></html>
            """,
            "https://bad.example.com": "<html></html>"
            // bad's search URL is intentionally left unstubbed -- its domain resolves but search fails.
        ])
        let outcomes = await collect(
            SourceValidationService.validate(sources: [good, bad], keyword: "novel", depth: .search, httpClient: client)
        )
        XCTAssertEqual(outcomes.count, 2)
        let goodOutcome = outcomes.first { $0.source.bookSourceUrl == "https://example.com" }
        let badOutcome = outcomes.first { $0.source.bookSourceUrl == "https://bad.example.com" }
        XCTAssertEqual(goodOutcome?.stageResults.last?.success, true)
        XCTAssertEqual(badOutcome?.stageResults.last?.success, false)
    }

    // MARK: - 发现页 (explore) check

    private func makeExploreSource(exploreUrl: String?) -> BookSource {
        var source = makeFullPipelineSource()
        source.exploreUrl = exploreUrl
        var explore = ExploreRule()
        explore.bookList = "@css:.item"
        explore.name = "@css:.name@text"
        explore.bookUrl = "@css:.name@href"
        source.ruleExplore = explore
        return source
    }

    func testExploreCheckPassesWhenExploreURLReturnsResults() async throws {
        let source = makeExploreSource(exploreUrl: "https://example.com/explore/fantasy")
        let client = StubHTTPClient(responses: [
            "https://example.com": "<html></html>",
            "https://example.com/search?wd=fixed": """
            <html><body><ul><li class="item"><a class="name" href="/book/1">Novel One</a></li></ul></body></html>
            """,
            "https://example.com/explore/fantasy": """
            <html><body><ul><li class="item"><a class="name" href="/book/2">Explore Novel</a></li></ul></body></html>
            """
        ])

        let outcomes = await collect(
            SourceValidationService.validate(sources: [source], keyword: "novel", depth: .search, httpClient: client)
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].stageResults.map(\.stage), [.domain, .search, .explore])
        XCTAssertTrue(outcomes[0].isFullyPassing)
    }

    func testExploreCheckFailsWhenExploreURLIsUnreachable() async throws {
        let source = makeExploreSource(exploreUrl: "https://example.com/explore/fantasy")
        // Explore URL intentionally left unstubbed.
        let client = StubHTTPClient(responses: [
            "https://example.com": "<html></html>",
            "https://example.com/search?wd=fixed": """
            <html><body><ul><li class="item"><a class="name" href="/book/1">Novel One</a></li></ul></body></html>
            """
        ])

        let outcomes = await collect(
            SourceValidationService.validate(sources: [source], keyword: "novel", depth: .search, httpClient: client)
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].stageResults.map(\.stage), [.domain, .search, .explore])
        XCTAssertFalse(outcomes[0].stageResults.last?.success ?? true)
        XCTAssertFalse(outcomes[0].isFullyPassing)
    }

    func testExploreCheckIsSkippedEntirelyWhenSourceHasNoExploreURL() async throws {
        let source = makeExploreSource(exploreUrl: nil)
        let client = stubbedClient()

        let outcomes = await collect(
            SourceValidationService.validate(sources: [source], keyword: "novel", depth: .search, httpClient: client)
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].stageResults.map(\.stage), [.domain, .search], "no explore result at all, not a failing one")
        XCTAssertTrue(outcomes[0].isFullyPassing)
    }

    /// Explore is independent of the search chain -- a source whose search fails should still get an
    /// explore result, not have it silently skipped, matching Legado's own `checkDiscovery` being a
    /// separate step from the search/info/category/content checks.
    func testExploreCheckStillRunsEvenWhenSearchStageFails() async throws {
        var source = makeExploreSource(exploreUrl: "https://example.com/explore/fantasy")
        source.ruleSearch?.bookList = "@css:.nonexistent"
        let client = StubHTTPClient(responses: [
            "https://example.com": "<html></html>",
            "https://example.com/search?wd=fixed": """
            <html><body><ul><li class="item"><a class="name" href="/book/1">Novel One</a></li></ul></body></html>
            """,
            "https://example.com/explore/fantasy": """
            <html><body><ul><li class="item"><a class="name" href="/book/2">Explore Novel</a></li></ul></body></html>
            """
        ])

        let outcomes = await collect(
            SourceValidationService.validate(sources: [source], keyword: "novel", depth: .content, httpClient: client)
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].stageResults.map(\.stage), [.domain, .search, .explore])
        XCTAssertFalse(outcomes[0].stageResults[1].success, "search itself still failed")
        XCTAssertTrue(outcomes[0].stageResults[2].success, "explore ran independently and succeeded")
    }
}
