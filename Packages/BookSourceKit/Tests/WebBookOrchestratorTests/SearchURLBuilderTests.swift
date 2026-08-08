import XCTest
@testable import WebBookOrchestrator

final class SearchURLBuilderTests: XCTestCase {
    func testPlainLiteralURLPassesThroughUnchangedOnEveryPlatform() throws {
        let built = try SearchURLBuilder.build(
            searchUrl: "https://example.com/search?wd=fixed", keyword: "ignored", page: 1, baseHeaders: [:],
            resolveAgainst: "https://example.com"
        )
        XCTAssertEqual(built.url, "https://example.com/search?wd=fixed")
        XCTAssertEqual(built.method, "GET")
        XCTAssertNil(built.body)
    }

    /// Regression test for a real bug found on-device: a relative `searchUrl` (e.g.
    /// `/modules/article/search.php?...`, a real, common shape) was passed straight to
    /// `URLSession` unresolved, which fails with "unsupported URL" (NSURLErrorDomain -1002) since
    /// a scheme-less path isn't a valid request URL on its own.
    func testRelativeSearchURLIsResolvedAgainstTheSourcesBaseURL() throws {
        let built = try SearchURLBuilder.build(
            searchUrl: "/modules/article/search.php?searchkey=fixed", keyword: "ignored", page: 1,
            baseHeaders: [:], resolveAgainst: "https://www.example.net/"
        )
        XCTAssertEqual(built.url, "https://www.example.net/modules/article/search.php?searchkey=fixed")
    }

    func testPostOptionsWithLiteralBodyAndMergedHeaders() throws {
        let built = try SearchURLBuilder.build(
            searchUrl: #"https://example.com/search,{"method":"POST","body":"q=fixed","headers":{"X-Extra":"1"}}"#,
            keyword: "ignored", page: 1, baseHeaders: ["User-Agent": "UA"], resolveAgainst: "https://example.com"
        )
        XCTAssertEqual(built.url, "https://example.com/search")
        XCTAssertEqual(built.method, "POST")
        XCTAssertEqual(built.body, "q=fixed")
        XCTAssertEqual(built.headers["User-Agent"], "UA")
        XCTAssertEqual(built.headers["X-Extra"], "1")
    }

    /// The URL half of the POST "url,{options}" form is just as often relative as the plain form.
    func testRelativePostURLIsAlsoResolvedAgainstTheSourcesBaseURL() throws {
        let built = try SearchURLBuilder.build(
            searchUrl: #"/search,{"method":"POST","body":"q=fixed"}"#,
            keyword: "ignored", page: 1, baseHeaders: [:], resolveAgainst: "https://example.com"
        )
        XCTAssertEqual(built.url, "https://example.com/search")
    }

    func testMalformedOptionsJSONFallsBackToPlainGET() throws {
        let built = try SearchURLBuilder.build(
            searchUrl: "https://example.com/search,{not valid json",
            keyword: "ignored", page: 1, baseHeaders: [:], resolveAgainst: "https://example.com"
        )
        XCTAssertEqual(built.method, "GET")
    }

    #if canImport(JavaScriptCore)
    func testKeyAndPagePlaceholdersAreSubstitutedOnApplePlatforms() throws {
        let built = try SearchURLBuilder.build(
            searchUrl: "https://example.com/search?wd={{key}}&p={{page}}",
            keyword: "凡人修仙传", page: 2, baseHeaders: [:], resolveAgainst: "https://example.com"
        )
        XCTAssertEqual(built.url, "https://example.com/search?wd=凡人修仙传&p=2")
    }

    func testPlaceholderInsidePostBodyIsSubstitutedOnApplePlatforms() throws {
        let built = try SearchURLBuilder.build(
            searchUrl: #"https://example.com/search,{"method":"POST","body":"q={{key}}"}"#,
            keyword: "novel", page: 1, baseHeaders: [:], resolveAgainst: "https://example.com"
        )
        XCTAssertEqual(built.body, "q=novel")
    }
    #else
    func testPlaceholderThrowsNotYetImplementedWherePlatformLacksJavaScriptCore() {
        XCTAssertThrowsError(try SearchURLBuilder.build(
            searchUrl: "https://example.com/search?wd={{key}}", keyword: "novel", page: 1, baseHeaders: [:],
            resolveAgainst: "https://example.com"
        ))
    }
    #endif
}
