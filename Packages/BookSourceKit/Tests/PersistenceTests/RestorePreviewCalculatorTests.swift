import XCTest
@testable import Persistence

final class RestorePreviewCalculatorTests: XCTestCase {
    func testUpsertStyleSplitsIntoInsertAndUpdate() {
        let diff = RestorePreviewCalculator.diff(
            remoteIds: ["a", "b", "c"], localIds: ["b", "c"], style: .upsert
        )
        XCTAssertEqual(diff, RestoreDiff(willInsert: 1, willUpdate: 2, willSkip: 0))
    }

    func testUpsertStyleWithNoOverlapIsAllInserts() {
        let diff = RestorePreviewCalculator.diff(
            remoteIds: ["a", "b"], localIds: [], style: .upsert
        )
        XCTAssertEqual(diff, RestoreDiff(willInsert: 2, willUpdate: 0, willSkip: 0))
    }

    func testAppendDedupStyleSplitsIntoInsertAndSkip() {
        let diff = RestorePreviewCalculator.diff(
            remoteIds: ["a", "b", "c"], localIds: ["b", "c"], style: .appendDedup
        )
        XCTAssertEqual(diff, RestoreDiff(willInsert: 1, willUpdate: 0, willSkip: 2))
    }

    func testEmptyRemoteIsAllZero() {
        let diff = RestorePreviewCalculator.diff(remoteIds: [], localIds: ["a"], style: .upsert)
        XCTAssertEqual(diff, RestoreDiff(willInsert: 0, willUpdate: 0, willSkip: 0))
    }
}
