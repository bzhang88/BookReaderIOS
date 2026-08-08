import XCTest
@testable import WebBookOrchestrator

final class SearchURLBuilderTests: XCTestCase {
    func testPlainLiteralURLPassesThroughUnchangedOnEveryPlatform() throws {
        let built = try SearchURLBuilder.build(
            searchUrl: "https://example.com/search?wd=fixed", keyword: "ignored", page: 1, baseHeaders: [:]
        )
        XCTAssertEqual(built.url, "https://example.com/search?wd=fixed")
        XCTAssertEqual(built.method, "GET")
        XCTAssertNil(built.body)
    }

    func testPostOptionsWithLiteralBodyAndMergedHeaders() throws {
        let built = try SearchURLBuilder.build(
            searchUrl: #"https://example.com/search,{"method":"POST","body":"q=fixed","headers":{"X-Extra":"1"}}"#,
            keyword: "ignored", page: 1, baseHeaders: ["User-Agent": "UA"]
        )
        XCTAssertEqual(built.url, "https://example.com/search")
        XCTAssertEqual(built.method, "POST")
        XCTAssertEqual(built.body, "q=fixed")
        XCTAssertEqual(built.headers["User-Agent"], "UA")
        XCTAssertEqual(built.headers["X-Extra"], "1")
    }

    func testMalformedOptionsJSONFallsBackToPlainGET() throws {
        let built = try SearchURLBuilder.build(
            searchUrl: "https://example.com/search,{not valid json",
            keyword: "ignored", page: 1, baseHeaders: [:]
        )
        XCTAssertEqual(built.method, "GET")
    }

    #if canImport(JavaScriptCore)
    func testKeyAndPagePlaceholdersAreSubstitutedOnApplePlatforms() throws {
        let built = try SearchURLBuilder.build(
            searchUrl: "https://example.com/search?wd={{key}}&p={{page}}",
            keyword: "凡人修仙传", page: 2, baseHeaders: [:]
        )
        XCTAssertEqual(built.url, "https://example.com/search?wd=凡人修仙传&p=2")
    }

    func testPlaceholderInsidePostBodyIsSubstitutedOnApplePlatforms() throws {
        let built = try SearchURLBuilder.build(
            searchUrl: #"https://example.com/search,{"method":"POST","body":"q={{key}}"}"#,
            keyword: "novel", page: 1, baseHeaders: [:]
        )
        XCTAssertEqual(built.body, "q=novel")
    }
    #else
    func testPlaceholderThrowsNotYetImplementedWherePlatformLacksJavaScriptCore() {
        XCTAssertThrowsError(try SearchURLBuilder.build(
            searchUrl: "https://example.com/search?wd={{key}}", keyword: "novel", page: 1, baseHeaders: [:]
        ))
    }
    #endif
}
