import XCTest
@testable import NetworkClient

final class RequestTimeoutTests: XCTestCase {
    func testOperationFinishingBeforeDeadlineReturnsItsResult() async throws {
        let result = try await withRequestTimeout(seconds: 1) {
            "done"
        }
        XCTAssertEqual(result, "done")
    }

    func testOperationThatNeverFinishesThrowsRequestTimeoutError() async {
        do {
            _ = try await withRequestTimeout(seconds: 0.2) {
                // Simulates a hung connection: an operation that never returns on its own.
                try await Task.sleep(nanoseconds: 60_000_000_000)
                return "unreachable"
            }
            XCTFail("expected withRequestTimeout to throw")
        } catch {
            XCTAssertEqual(error as? RequestTimeoutError, RequestTimeoutError())
        }
    }

    func testOperationErrorPropagatesWhenFasterThanTimeout() async {
        struct SomeError: Error, Equatable {}
        do {
            _ = try await withRequestTimeout(seconds: 5) {
                throw SomeError()
            }
            XCTFail("expected the operation's own error to propagate")
        } catch {
            XCTAssertEqual(error as? SomeError, SomeError())
        }
    }
}
