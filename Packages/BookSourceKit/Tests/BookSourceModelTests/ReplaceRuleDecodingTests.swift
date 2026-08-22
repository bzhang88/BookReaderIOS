import XCTest
@testable import BookSourceModel

final class ReplaceRuleDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> ReplaceRule {
        try JSONDecoder().decode(ReplaceRule.self, from: Data(json.utf8))
    }

    func testDecodesCurrentScopeKey() throws {
        let json = #"{"id": "1", "name": "R", "pattern": "x", "scope": "https://example.com"}"#
        let rule = try decode(json)
        XCTAssertEqual(rule.scope, "https://example.com")
    }

    /// The real migration-safety case: `scope` used to be named `scopeSourceUrl` -- data written
    /// under that name (either this app's own earlier persisted `replace_rules.json`, or a
    /// `LegadoReplaceRuleImport`-derived rule saved before this rename) must still decode with its
    /// value intact, not silently lose it.
    func testFallsBackToLegacyScopeSourceUrlKeyWhenScopeIsAbsent() throws {
        let json = #"{"id": "1", "name": "R", "pattern": "x", "scopeSourceUrl": "https://legacy.example.com"}"#
        let rule = try decode(json)
        XCTAssertEqual(rule.scope, "https://legacy.example.com")
    }

    /// If a future write somehow produced both keys, the current one wins -- it's the one this
    /// app's own `encode(to:)` actually writes going forward.
    func testCurrentScopeKeyTakesPriorityOverLegacyKeyWhenBothPresent() throws {
        let json = #"{"id": "1", "name": "R", "pattern": "x", "scope": "new", "scopeSourceUrl": "old"}"#
        let rule = try decode(json)
        XCTAssertEqual(rule.scope, "new")
    }

    func testMissingOptionalFieldsDefaultSensibly() throws {
        let json = #"{"id": "1", "name": "R", "pattern": "x"}"#
        let rule = try decode(json)
        XCTAssertNil(rule.group)
        XCTAssertNil(rule.scope)
        XCTAssertNil(rule.excludeScope)
        XCTAssertFalse(rule.scopeTitle)
        XCTAssertTrue(rule.scopeContent)
        XCTAssertEqual(rule.order, 0)
        XCTAssertTrue(rule.enabled)
    }

    /// `encode(to:)` is hand-written (required once `init(from:)` is custom and `CodingKeys` has a
    /// legacy-only case -- see the type's own doc comment) -- this guards it actually round-trips
    /// every field, including onto the *current* `scope` key specifically (not the legacy one).
    func testRoundTripsThroughEncodeAndDecode() throws {
        let original = ReplaceRule(
            name: "R", group: "分组", pattern: "x", replacement: "y", isRegex: false,
            scope: "书名,https://example.com", excludeScope: "排除",
            scopeTitle: true, scopeContent: false, order: 5, enabled: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReplaceRule.self, from: data)
        XCTAssertEqual(decoded, original)

        // The encoded JSON itself uses "scope", not the legacy "scopeSourceUrl" key.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["scope"] as? String, "书名,https://example.com")
        XCTAssertNil(object?["scopeSourceUrl"])
    }
}
