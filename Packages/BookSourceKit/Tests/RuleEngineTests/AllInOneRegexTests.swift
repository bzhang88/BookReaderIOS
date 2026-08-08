import XCTest
@testable import RuleEngine

final class AllInOneRegexTests: XCTestCase {
    func testExtractsOneRowPerMatchWithWholeMatchAtIndexZero() throws {
        let text = "<li><a href=\"/c/1\">Chapter 1</a></li><li><a href=\"/c/2\">Chapter 2</a></li>"
        let rows = try AllInOneRegex.extractRows(
            pattern: "<li><a[^\"]+\"([^\"]*)\">([^<]*)", from: text
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0][1], "/c/1")
        XCTAssertEqual(rows[0][2], "Chapter 1")
        XCTAssertEqual(rows[1][1], "/c/2")
        XCTAssertEqual(rows[1][2], "Chapter 2")
        // index 0 is the whole match, not just the captures.
        XCTAssertTrue(rows[0][0].contains("Chapter 1"))
    }

    func testNoMatchesReturnsEmpty() throws {
        let rows = try AllInOneRegex.extractRows(pattern: "nomatch", from: "hello world")
        XCTAssertEqual(rows.count, 0)
    }

    func testNonParticipatingGroupBecomesEmptyString() throws {
        let rows = try AllInOneRegex.extractRows(pattern: "(a)|(b)", from: "b")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0][1], "") // group 1 (a) didn't participate
        XCTAssertEqual(rows[0][2], "b")
    }

    func testChainedAmpAmpThrowsNotYetImplemented() {
        XCTAssertThrowsError(try AllInOneRegex.extractRows(pattern: "a&&b", from: "text")) { error in
            guard case .notYetImplemented = error as? RuleEngineError else {
                return XCTFail("expected .notYetImplemented, got \(error)")
            }
        }
    }
}
