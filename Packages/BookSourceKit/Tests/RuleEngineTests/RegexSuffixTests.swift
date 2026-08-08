import XCTest
@testable import RuleEngine

final class RegexSuffixTests: XCTestCase {
    func testNoSuffix() {
        let (remainder, suffix) = RegexSuffixParser.extract(from: "class.name@text")
        XCTAssertEqual(remainder, "class.name@text")
        XCTAssertNil(suffix)
    }

    func testPurifyWithReplacement() {
        let (remainder, suffix) = RegexSuffixParser.extract(from: "class.name@text##foo##bar")
        XCTAssertEqual(remainder, "class.name@text")
        XCTAssertEqual(suffix?.pattern, "foo")
        XCTAssertEqual(suffix?.replacement, "bar")
        XCTAssertEqual(suffix?.onlyOne, false)
    }

    func testPurifyWithoutReplacementDefaultsEmpty() {
        let (remainder, suffix) = RegexSuffixParser.extract(from: "class.name@text##foo")
        XCTAssertEqual(remainder, "class.name@text")
        XCTAssertEqual(suffix?.pattern, "foo")
        XCTAssertEqual(suffix?.replacement, "")
        XCTAssertEqual(suffix?.onlyOne, false)
    }

    func testOnlyOneMode() {
        let (remainder, suffix) = RegexSuffixParser.extract(from: "##:book_name\"[^\"]+\"([^\"]+)\"##$1###")
        XCTAssertEqual(remainder, "")
        XCTAssertEqual(suffix?.onlyOne, true)
        XCTAssertEqual(suffix?.replacement, "$1")
    }

    func testApplyPurifyGlobalReplace() {
        let suffix = RegexSuffix(pattern: "ad\\d", replacement: "", onlyOne: false)
        let result = RegexSuffixParser.apply(suffix, to: "textad1moretextad2end")
        XCTAssertEqual(result, "textmoretextend")
    }

    func testApplyPurifyWithCaptureGroupTemplate() {
        let suffix = RegexSuffix(pattern: "\\[(\\d+)\\]", replacement: "($1)", onlyOne: false)
        let result = RegexSuffixParser.apply(suffix, to: "chapter[1] and [22]")
        XCTAssertEqual(result, "chapter(1) and (22)")
    }

    func testApplyOnlyOneNarrowsThenReplacesWithinMatch() {
        // OnlyOne isolates the *first* match, then replaces within that isolated substring only --
        // everything outside the first match (the leading prefix, and the second AAA...BBB) is dropped.
        let suffix = RegexSuffix(pattern: "AAA(\\d+)BBB", replacement: "[$1]", onlyOne: true)
        let input = "prefix AAA123BBB suffix AAA999BBB"
        let result = RegexSuffixParser.apply(suffix, to: input)
        XCTAssertEqual(result, "[123]")
    }

    func testApplyOnlyOneNoMatchReturnsEmptyString() {
        let suffix = RegexSuffix(pattern: "nomatch", replacement: "x", onlyOne: true)
        XCTAssertEqual(RegexSuffixParser.apply(suffix, to: "hello world"), "")
    }
}
