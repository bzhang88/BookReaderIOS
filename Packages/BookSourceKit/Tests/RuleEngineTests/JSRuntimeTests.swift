import XCTest
@testable import RuleEngine

final class JSRuntimeTests: XCTestCase {
    func testUnavailablePlatformThrowsNotYetImplemented() throws {
        #if canImport(JavaScriptCore)
        throw XCTSkip("JavaScriptCore is available on this platform; see testBasicEvaluationOnApplePlatforms instead")
        #else
        XCTAssertFalse(JSRuntime.isAvailable)
        XCTAssertThrowsError(try JSRuntime.evaluate("1+1", bindings: [:])) { error in
            guard case .notYetImplemented = error as? RuleEngineError else {
                return XCTFail("expected .notYetImplemented, got \(error)")
            }
        }
        #endif
    }

    #if canImport(JavaScriptCore)
    func testBasicEvaluationOnApplePlatforms() throws {
        XCTAssertTrue(JSRuntime.isAvailable)
        let result = try JSRuntime.evaluate("key + '-' + page", bindings: ["key": "novel", "page": "1"])
        XCTAssertEqual(result, "novel-1")
    }
    #endif
}
