import XCTest
import BookSourceModel
@testable import WebBookOrchestrator

final class TagGroupRuleApplierTests: XCTestCase {
    func testNoRulesReturnsNil() {
        let group = TagGroupRuleApplier.matchGroup([], name: "斗破苍穹", author: "天蚕土豆", intro: nil)
        XCTAssertNil(group)
    }

    func testMatchesAgainstName() {
        let rule = TagGroupRule(groupName: "玄幻", pattern: "斗破")
        let group = TagGroupRuleApplier.matchGroup([rule], name: "斗破苍穹", author: nil, intro: nil)
        XCTAssertEqual(group, "玄幻")
    }

    func testMatchesAgainstAuthor() {
        let rule = TagGroupRule(groupName: "土豆作品", pattern: "天蚕土豆")
        let group = TagGroupRuleApplier.matchGroup([rule], name: "斗破苍穹", author: "天蚕土豆", intro: nil)
        XCTAssertEqual(group, "土豆作品")
    }

    func testMatchesAgainstIntro() {
        let rule = TagGroupRule(groupName: "游戏", pattern: "网游|系统流")
        let group = TagGroupRuleApplier.matchGroup([rule], name: "无名之作", author: nil, intro: "一个关于系统流的故事")
        XCTAssertEqual(group, "游戏")
    }

    func testFirstEnabledMatchWins() {
        let rules = [
            TagGroupRule(groupName: "A", pattern: "斗破"),
            TagGroupRule(groupName: "B", pattern: "苍穹")
        ]
        let group = TagGroupRuleApplier.matchGroup(rules, name: "斗破苍穹", author: nil, intro: nil)
        XCTAssertEqual(group, "A")
    }

    func testDisabledRuleIsSkipped() {
        let rules = [
            TagGroupRule(groupName: "A", pattern: "斗破", enabled: false),
            TagGroupRule(groupName: "B", pattern: "苍穹")
        ]
        let group = TagGroupRuleApplier.matchGroup(rules, name: "斗破苍穹", author: nil, intro: nil)
        XCTAssertEqual(group, "B")
    }

    func testNoMatchReturnsNil() {
        let rule = TagGroupRule(groupName: "玄幻", pattern: "都市")
        let group = TagGroupRuleApplier.matchGroup([rule], name: "斗破苍穹", author: "天蚕土豆", intro: nil)
        XCTAssertNil(group)
    }

    func testMalformedRegexIsSkipped() {
        let rules = [
            TagGroupRule(groupName: "Broken", pattern: "(unclosed"),
            TagGroupRule(groupName: "B", pattern: "斗破")
        ]
        let group = TagGroupRuleApplier.matchGroup(rules, name: "斗破苍穹", author: nil, intro: nil)
        XCTAssertEqual(group, "B")
    }
}
