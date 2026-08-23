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

    /// Migration-safety case for `group`/`targetScope`, same reasoning as the style-fields test above.
    func testDecodesPreExistingRuleJSONMissingGroupAndScopeFields() throws {
        let json = """
        {"id": "abc", "name": "Name", "pattern": "张三", "enabled": true}
        """
        let rule = try JSONDecoder().decode(HighlightRule.self, from: Data(json.utf8))
        XCTAssertNil(rule.group)
        XCTAssertEqual(rule.resolvedTargetScope, .all)
    }

    func testResolvedTargetScopeDefaultsToAll() {
        let rule = HighlightRule(name: "Name", pattern: "张三")
        XCTAssertEqual(rule.resolvedTargetScope, .all)
        XCTAssertTrue(rule.applies(toTitle: true))
        XCTAssertTrue(rule.applies(toTitle: false))
    }

    func testTargetScopeTitleOnlyAppliesToTitle() {
        let rule = HighlightRule(name: "Name", pattern: "张三", targetScope: .title)
        XCTAssertTrue(rule.applies(toTitle: true))
        XCTAssertFalse(rule.applies(toTitle: false))
    }

    func testTargetScopeBodyOnlyAppliesToBody() {
        let rule = HighlightRule(name: "Name", pattern: "张三", targetScope: .body)
        XCTAssertFalse(rule.applies(toTitle: true))
        XCTAssertTrue(rule.applies(toTitle: false))
    }

    /// An out-of-range raw value (e.g. a future version wrote a scope this build doesn't know about)
    /// must degrade to `.all` rather than crash or silently exclude the rule everywhere.
    func testUnrecognizedRawTargetScopeFallsBackToAll() throws {
        let json = """
        {"id": "abc", "name": "Name", "pattern": "张三", "enabled": true, "targetScope": 99}
        """
        let rule = try JSONDecoder().decode(HighlightRule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.resolvedTargetScope, .all)
    }
}
