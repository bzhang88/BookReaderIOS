import XCTest
@testable import BookSourceModel

final class HighlightRuleTests: XCTestCase {
    func testResolvedDefaultsMatchOriginalHardcodedStyle() {
        let rule = HighlightRule(name: "Name", pattern: "张三")
        XCTAssertNil(rule.colorHex)
        XCTAssertTrue(rule.resolvedIsBold)
        XCTAssertFalse(rule.resolvedIsUnderlined)
    }

    func testResolvedValuesReflectExplicitOverrides() {
        let rule = HighlightRule(name: "Name", pattern: "张三", colorHex: "#00FF00", isBold: false, isUnderlined: true)
        XCTAssertEqual(rule.colorHex, "#00FF00")
        XCTAssertFalse(rule.resolvedIsBold)
        XCTAssertTrue(rule.resolvedIsUnderlined)
    }

    /// Migration-safety case: `colorHex`/`isBold`/`isUnderlined` didn't exist before this styling
    /// feature was added -- guards that decoding an old `highlight_rules.json` (missing all three
    /// keys) doesn't throw, and that the resolved style still matches what the reader always did.
    func testDecodesPreExistingRuleJSONMissingStyleFields() throws {
        let json = """
        {"id": "abc", "name": "Name", "pattern": "张三", "enabled": true}
        """
        let rule = try JSONDecoder().decode(HighlightRule.self, from: Data(json.utf8))
        XCTAssertNil(rule.colorHex)
        XCTAssertTrue(rule.resolvedIsBold)
        XCTAssertFalse(rule.resolvedIsUnderlined)
    }
}
