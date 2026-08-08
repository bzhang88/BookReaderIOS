import XCTest
@testable import RuleEngine

final class RegexRowTemplateTests: XCTestCase {
    func testBareReferenceSubstitutesWholeGroup() {
        let row = ["whole match", "group one", "group two"]
        XCTAssertEqual(RegexRowTemplate.substitute("$2", row: row), "group two")
        XCTAssertEqual(RegexRowTemplate.substitute("$0", row: row), "whole match")
    }

    func testEmbeddedReferenceInLiteralText() {
        let row = ["whole", "42"]
        XCTAssertEqual(RegexRowTemplate.substitute("id-$1-end", row: row), "id-42-end")
    }

    func testMultipleReferencesInOneTemplate() {
        let row = ["whole", "a", "b"]
        XCTAssertEqual(RegexRowTemplate.substitute("$1/$2", row: row), "a/b")
    }

    func testOutOfRangeIndexDegradesToEmptyRatherThanCrashing() {
        let row = ["whole", "only-group"]
        XCTAssertEqual(RegexRowTemplate.substitute("$5", row: row), "")
    }

    func testNoReferenceReturnsTemplateUnchanged() {
        XCTAssertEqual(RegexRowTemplate.substitute("no references here", row: ["x"]), "no references here")
    }
}
