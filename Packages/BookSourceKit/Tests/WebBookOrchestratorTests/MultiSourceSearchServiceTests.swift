import XCTest
import BookSourceModel
import NetworkClient
@testable import WebBookOrchestrator

/// An `HTTPClient` that sleeps before responding, so cancellation tests have something real to
/// interrupt mid-flight instead of racing against instantly-resolved stub responses.
private actor DelayedStubHTTPClient: HTTPClient {
    private let delayNanoseconds: UInt64
    private let responses: [String: String]
    private(set) var completedURLs: [String] = []

    init(delaySeconds: Double, responses: [String: String]) {
        self.delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
        self.responses = responses
    }

    func fetch(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        guard let body = responses[request.url] else {
            throw HTTPClientError.invalidURL(request.url)
        }
        completedURLs.append(request.url)
        return HTTPResponse(finalURL: request.url, statusCode: 200, body: body)
    }
}

/// Tracks how many `fetch` calls are simultaneously in flight, and the highest count ever reached --
/// lets a test assert on real observed peak concurrency rather than just trusting the implementation.
private actor ConcurrencyTrackingHTTPClient: HTTPClient {
    private let delayNanoseconds: UInt64
    private let responses: [String: String]
    private var inFlight = 0
    private(set) var peakInFlight = 0

    init(delaySeconds: Double, responses: [String: String]) {
        self.delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
        self.responses = responses
    }

    func fetch(_ request: HTTPRequest) async throws -> HTTPResponse {
        inFlight += 1
        peakInFlight = max(peakInFlight, inFlight)
        try await Task.sleep(nanoseconds: delayNanoseconds)
        inFlight -= 1
        guard let body = responses[request.url] else {
            throw HTTPClientError.invalidURL(request.url)
        }
        return HTTPResponse(finalURL: request.url, statusCode: 200, body: body)
    }
}

final class MultiSourceSearchServiceTests: XCTestCase {
    private func makeSource(name: String, url: String) -> BookSource {
        var rule = SearchRule()
        rule.bookList = "@css:.item"
        rule.name = "@css:.name@text"
        rule.bookUrl = "@css:.name@href"
        return BookSource(
            bookSourceUrl: url, bookSourceName: name, searchUrl: "\(url)/search?wd=fixed", ruleSearch: rule
        )
    }

    private let html = """
    <ul><li class="item"><a class="name" href="/book/1">Found It</a></li></ul>
    """

    func testStreamsOneOutcomePerSourceRegardlessOfCompletionOrder() async throws {
        let sourceA = makeSource(name: "A", url: "https://a.example.com")
        let sourceB = makeSource(name: "B", url: "https://b.example.com")
        let client = StubHTTPClient(responses: [
            "https://a.example.com/search?wd=fixed": html,
            "https://b.example.com/search?wd=fixed": html
        ])

        var outcomes: [MultiSourceSearchService.SourceOutcome] = []
        for await outcome in MultiSourceSearchService.search(sources: [sourceA, sourceB], keyword: "novel", httpClient: client) {
            outcomes.append(outcome)
        }

        XCTAssertEqual(outcomes.count, 2)
        XCTAssertEqual(Set(outcomes.map(\.source.bookSourceName)), ["A", "B"])
        for outcome in outcomes {
            XCTAssertEqual(outcome.results.first?.name, "Found It")
            XCTAssertNil(outcome.errorDescription)
        }
    }

    func testOneFailingSourceReportsErrorWithoutLosingOthersResults() async throws {
        let working = makeSource(name: "Working", url: "https://working.example.com")
        let dead = makeSource(name: "Dead", url: "https://dead.example.com")
        let client = StubHTTPClient(responses: [
            "https://working.example.com/search?wd=fixed": html
            // "dead" source's URL is intentionally absent -- StubHTTPClient throws for it.
        ])

        var outcomes: [MultiSourceSearchService.SourceOutcome] = []
        for await outcome in MultiSourceSearchService.search(sources: [working, dead], keyword: "novel", httpClient: client) {
            outcomes.append(outcome)
        }

        let workingOutcome = try XCTUnwrap(outcomes.first { $0.source.bookSourceName == "Working" })
        let deadOutcome = try XCTUnwrap(outcomes.first { $0.source.bookSourceName == "Dead" })
        XCTAssertEqual(workingOutcome.results.count, 1)
        XCTAssertNil(workingOutcome.errorDescription)
        XCTAssertTrue(deadOutcome.results.isEmpty)
        XCTAssertNotNil(deadOutcome.errorDescription)
    }

    func testCancellingTheConsumingTaskStopsBeforeAllSourcesComplete() async throws {
        let sources = (0..<5).map { makeSource(name: "S\($0)", url: "https://s\($0).example.com") }
        var responses: [String: String] = [:]
        for (i, _) in sources.enumerated() {
            responses["https://s\(i).example.com/search?wd=fixed"] = html
        }
        let client = DelayedStubHTTPClient(delaySeconds: 0.3, responses: responses)

        let collector = OutcomeCollector()
        let consumingTask = Task {
            for await outcome in MultiSourceSearchService.search(sources: sources, keyword: "novel", httpClient: client) {
                await collector.add(outcome)
            }
        }

        // Cancel well before any of the 0.3s-delayed sources would finish.
        try await Task.sleep(nanoseconds: 50_000_000)
        consumingTask.cancel()
        _ = await consumingTask.result

        let finalCount = await collector.outcomes.count
        XCTAssertLessThan(finalCount, sources.count, "expected cancellation to stop the stream before all 5 sources completed")
    }

    func testConcurrencyIsBoundedByMaxConcurrent() async throws {
        let sources = (0..<10).map { makeSource(name: "S\($0)", url: "https://s\($0).example.com") }
        var responses: [String: String] = [:]
        for (i, _) in sources.enumerated() {
            responses["https://s\(i).example.com/search?wd=fixed"] = html
        }
        let client = ConcurrencyTrackingHTTPClient(delaySeconds: 0.05, responses: responses)

        var outcomes: [MultiSourceSearchService.SourceOutcome] = []
        for await outcome in MultiSourceSearchService.search(sources: sources, keyword: "novel", httpClient: client, maxConcurrent: 3) {
            outcomes.append(outcome)
        }

        XCTAssertEqual(outcomes.count, 10, "every source should still eventually complete, just not all at once")
        let peak = await client.peakInFlight
        XCTAssertLessThanOrEqual(peak, 3, "expected at most maxConcurrent (3) simultaneous searches, observed \(peak)")
    }

    func testUnboundedDefaultStillLetsAllSourcesRunConcurrentlyForASmallCollection() async throws {
        // Real-world default (16) shouldn't visibly throttle a small, everyday-sized collection --
        // guards against accidentally serializing everything by making maxConcurrent too small.
        let sources = (0..<5).map { makeSource(name: "S\($0)", url: "https://s\($0).example.com") }
        var responses: [String: String] = [:]
        for (i, _) in sources.enumerated() {
            responses["https://s\(i).example.com/search?wd=fixed"] = html
        }
        let client = ConcurrencyTrackingHTTPClient(delaySeconds: 0.05, responses: responses)

        var outcomes: [MultiSourceSearchService.SourceOutcome] = []
        for await outcome in MultiSourceSearchService.search(sources: sources, keyword: "novel", httpClient: client) {
            outcomes.append(outcome)
        }

        XCTAssertEqual(outcomes.count, 5)
        let peak = await client.peakInFlight
        XCTAssertEqual(peak, 5, "expected all 5 sources to run concurrently under the default 16-way cap")
    }
}

private actor OutcomeCollector {
    private(set) var outcomes: [MultiSourceSearchService.SourceOutcome] = []
    func add(_ outcome: MultiSourceSearchService.SourceOutcome) { outcomes.append(outcome) }
}
