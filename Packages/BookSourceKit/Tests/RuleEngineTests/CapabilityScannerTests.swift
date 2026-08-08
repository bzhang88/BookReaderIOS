import XCTest
import BookSourceModel
@testable import RuleEngine

final class CapabilityScannerTests: XCTestCase {
    private func makeSource(
        type: Int = 0,
        search: SearchRule? = nil,
        toc: TocRule? = nil,
        content: ContentRule? = nil
    ) -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.com", bookSourceName: "Test",
            bookSourceType: type, ruleSearch: search, ruleToc: toc, ruleContent: content
        )
    }

    func testFullyCompatibleSourceHasNoIssues() {
        var search = SearchRule()
        search.bookList = "@css:li.clearfix"
        search.name = "@css:.name@text"
        search.bookUrl = "@css:.name>a@href"

        var toc = TocRule()
        toc.chapterList = "@css:.toc li"
        toc.chapterName = "@css:a@text"
        toc.chapterUrl = "@css:a@href"

        var content = ContentRule()
        content.content = "@css:.content@text"

        let report = CapabilityScanner.scan(makeSource(search: search, toc: toc, content: content))
        XCTAssertTrue(report.isFullyCompatible)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testWebJsFieldIsFlaggedEvenThoughItsOwnValueWouldParse() {
        var content = ContentRule()
        content.content = "@css:.content@text"
        content.webJs = "document.title" // a plain string -- would parse fine as CSS text, but the *feature* isn't supported

        let report = CapabilityScanner.scan(makeSource(content: content))
        XCTAssertFalse(report.isFullyCompatible)
        XCTAssertTrue(report.issues.contains { $0.field == "ruleContent.webJs" })
    }

    func testPreUpdateJsFieldIsFlagged() {
        var toc = TocRule()
        toc.chapterList = "@css:.toc li"
        toc.preUpdateJs = "someFunction()"

        let report = CapabilityScanner.scan(makeSource(toc: toc))
        XCTAssertTrue(report.issues.contains { $0.field == "ruleToc.preUpdateJs" })
    }

    func testNonTextSourceTypeIsFlagged() {
        let report = CapabilityScanner.scan(makeSource(type: 1)) // 1 = audio
        XCTAssertTrue(report.issues.contains { $0.field == "bookSourceType" })
    }

    func testUnsupportedRuleSyntaxIsReportedWithReason() {
        var search = SearchRule()
        search.name = "@css:.name{{result.trim()}}" // embedded JS, not yet implemented

        let report = CapabilityScanner.scan(makeSource(search: search))
        let issue = report.issues.first { $0.field == "ruleSearch.name" }
        XCTAssertNotNil(issue)
        XCTAssertTrue(issue!.reason.contains("not yet implemented"))
    }

    func testListRulePrefixIsStrippedBeforeChecking() {
        // "-:" (reversed AllInOne) must not be mistaken for a malformed rule.
        var toc = TocRule()
        toc.chapterList = "-:<li><a[^\"]+\"([^\"]*)\">([^<]*)"
        toc.chapterName = "$2"
        toc.chapterUrl = "$1"

        let report = CapabilityScanner.scan(makeSource(toc: toc))
        XCTAssertTrue(report.issues.isEmpty, "expected no issues, got: \(report.issues)")
    }

    func testScanMultipleSourcesReturnsOneReportEach() {
        let reports = CapabilityScanner.scan([makeSource(), makeSource(type: 2)])
        XCTAssertEqual(reports.count, 2)
    }
}
