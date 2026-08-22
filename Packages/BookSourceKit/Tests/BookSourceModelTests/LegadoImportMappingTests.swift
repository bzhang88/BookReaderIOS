import XCTest
@testable import BookSourceModel

final class LegadoImportMappingTests: XCTestCase {
    func testReplaceRuleImportDecodesRealLegadoShape() throws {
        let json = """
        {
            "id": 1699999999000,
            "name": "去广告",
            "group": "通用",
            "pattern": "广告内容",
            "replacement": "",
            "scope": "https://example.com",
            "scopeTitle": false,
            "scopeContent": true,
            "isEnabled": true,
            "isRegex": false,
            "order": 0
        }
        """
        let imported = try JSONDecoder().decode(LegadoReplaceRuleImport.self, from: Data(json.utf8))
        let rule = imported.toReplaceRule()
        XCTAssertEqual(rule.id, "1699999999000")
        XCTAssertEqual(rule.name, "去广告")
        XCTAssertEqual(rule.group, "通用")
        XCTAssertEqual(rule.pattern, "广告内容")
        XCTAssertEqual(rule.scope, "https://example.com")
        XCTAssertEqual(rule.scopeTitle, false)
        XCTAssertEqual(rule.scopeContent, true)
        XCTAssertEqual(rule.isRegex, false)
        XCTAssertTrue(rule.enabled)
    }

    func testReplaceRuleImportMissingOptionalsDefaultSensibly() throws {
        let json = #"{"id": 1, "name": "简单规则", "pattern": "x"}"#
        let imported = try JSONDecoder().decode(LegadoReplaceRuleImport.self, from: Data(json.utf8))
        let rule = imported.toReplaceRule()
        XCTAssertEqual(rule.replacement, "")
        XCTAssertTrue(rule.isRegex)
        XCTAssertTrue(rule.enabled)
        XCTAssertNil(rule.group)
        XCTAssertNil(rule.scope)
        XCTAssertNil(rule.excludeScope)
        XCTAssertFalse(rule.scopeTitle)
        XCTAssertTrue(rule.scopeContent)
        XCTAssertEqual(rule.order, 0)
    }

    func testTxtTocRuleImportDecodesRealLegadoShape() throws {
        let json = """
        {
            "id": 42,
            "name": "标准章节",
            "rule": "^第.+章",
            "replacement": "",
            "example": "第一章 开始",
            "serialNumber": -1,
            "enable": true
        }
        """
        let imported = try JSONDecoder().decode(LegadoTxtTocRuleImport.self, from: Data(json.utf8))
        let rule = imported.toTxtSplitRule()
        XCTAssertEqual(rule.id, "42")
        XCTAssertEqual(rule.name, "标准章节")
        XCTAssertEqual(rule.pattern, "^第.+章")
        XCTAssertTrue(rule.enabled)
    }

    func testTxtTocRuleImportMissingEnableDefaultsToTrue() throws {
        let json = #"{"id": 1, "name": "规则", "rule": "x"}"#
        let imported = try JSONDecoder().decode(LegadoTxtTocRuleImport.self, from: Data(json.utf8))
        XCTAssertTrue(imported.toTxtSplitRule().enabled)
    }
}
