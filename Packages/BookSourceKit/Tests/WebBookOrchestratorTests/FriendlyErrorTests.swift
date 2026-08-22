import XCTest
import NetworkClient
import RuleEngine
@testable import WebBookOrchestrator

final class FriendlyErrorTests: XCTestCase {
    func testWebDAVInvalidBaseURL() {
        XCTAssertEqual(
            FriendlyError.message(for: WebDAVClientError.invalidBaseURL("")),
            "WebDAV 地址格式不对，请检查服务器地址"
        )
    }

    func testWebDAVAuthFailureStatusCodes() {
        XCTAssertEqual(FriendlyError.message(for: WebDAVClientError.unexpectedStatus(401)), "WebDAV 账号或密码不正确")
        XCTAssertEqual(FriendlyError.message(for: WebDAVClientError.unexpectedStatus(403)), "WebDAV 账号或密码不正确")
    }

    func testWebDAVNotFoundStatusCode() {
        XCTAssertEqual(FriendlyError.message(for: WebDAVClientError.unexpectedStatus(404)), "WebDAV 路径不存在，请检查备份目录设置")
    }

    func testWebDAVOtherStatusCodeIncludesTheCode() {
        XCTAssertEqual(FriendlyError.message(for: WebDAVClientError.unexpectedStatus(500)), "WebDAV 请求失败（状态码 500）")
    }

    func testRuleEngineErrorsStillReadAsBookSourceSpecific() {
        XCTAssertTrue(FriendlyError.message(for: RuleEngineError.unsupportedFeature(.webJs)).contains("书源"))
    }

    func testGenericNetworkErrorsNoLongerMentionBookSource() {
        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertFalse(FriendlyError.message(for: timeout).contains("书源"))
        let unreachable = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        XCTAssertFalse(FriendlyError.message(for: unreachable).contains("书源"))
    }

    func testNoConnectionMessage() {
        let noConnection = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(FriendlyError.message(for: noConnection), "没有网络连接")
    }
}
