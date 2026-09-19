import XCTest
@testable import Core_Monitor

@MainActor
final class DiskStatsRefreshPolicyTests: XCTestCase {
    func testRefreshesImmediatelyWhenNoPreviousSampleExists() {
        XCTAssertTrue(
            DiskStatsRefreshPolicy.shouldRefresh(
                lastUpdatedAt: nil,
                now: Date(timeIntervalSince1970: 100)
            )
        )
    }

    func testSkipsRefreshesInsideMinimumInterval() {
        XCTAssertFalse(
            DiskStatsRefreshPolicy.shouldRefresh(
                lastUpdatedAt: Date(timeIntervalSince1970: 100),
                now: Date(timeIntervalSince1970: 129)
            )
        )
    }

    func testRefreshesAgainOnceMinimumIntervalExpires() {
        XCTAssertTrue(
            DiskStatsRefreshPolicy.shouldRefresh(
                lastUpdatedAt: Date(timeIntervalSince1970: 100),
                now: Date(timeIntervalSince1970: 130)
            )
        )
    }

    func testCacheKeepsLastSuccessfulReadingWhenLoadThrowsAndRetriesNextSample() {
        enum ReadFailure: Error { case unavailable }
        var cache = DiskStatsCache()
        let originalDate = Date(timeIntervalSince1970: 100)
        let original = DiskStats(totalGB: 500, usedGB: 300, freeGB: 180, purgeableGB: 20, usagePercent: 60)
        _ = cache.read(now: originalDate) { original }

        let failed = cache.read(now: originalDate.addingTimeInterval(30)) { throw ReadFailure.unavailable }

        XCTAssertEqual(failed.totalGB, 500)
        XCTAssertEqual(failed.usedGB, 300)
        XCTAssertEqual(failed.freeGB, 180)
        XCTAssertEqual(failed.purgeableGB, 20)
        XCTAssertEqual(failed.usagePercent, 60)
        XCTAssertEqual(cache.lastUpdatedAt, originalDate)

        let retryDate = originalDate.addingTimeInterval(31)
        let recovered = cache.read(now: retryDate) { DiskStats(totalGB: 500, usedGB: 350, usagePercent: 70) }

        XCTAssertEqual(recovered.usedGB, 350)
        XCTAssertEqual(cache.lastUpdatedAt, retryDate)
    }

    func testIncompleteReadPreservesCacheAndDoesNotDelayRetry() {
        var cache = DiskStatsCache()
        let originalDate = Date(timeIntervalSince1970: 100)
        _ = cache.read(now: originalDate) { DiskStats(totalGB: 500, usedGB: 300) }

        let failed = cache.read(now: originalDate.addingTimeInterval(30)) { nil }

        XCTAssertEqual(failed.usedGB, 300)
        XCTAssertEqual(cache.lastUpdatedAt, originalDate)
    }

    func testFirstFailedReadLeavesCacheEligibleForImmediateRetry() {
        var cache = DiskStatsCache()
        let now = Date(timeIntervalSince1970: 100)
        let failed = cache.read(now: now) { nil }

        XCTAssertEqual(failed.totalGB, 0)
        XCTAssertNil(cache.lastUpdatedAt)

        let recovered = cache.read(now: now.addingTimeInterval(1)) { DiskStats(totalGB: 500) }
        XCTAssertEqual(recovered.totalGB, 500)
    }

    func testSuccessfulReadStillThrottlesSubsequentLoads() {
        var cache = DiskStatsCache()
        let now = Date(timeIntervalSince1970: 100)
        _ = cache.read(now: now) { DiskStats(totalGB: 500) }

        let cached = cache.read(now: now.addingTimeInterval(29)) {
            XCTFail("A successful sample must keep the normal refresh interval.")
            return nil
        }

        XCTAssertEqual(cached.totalGB, 500)
        XCTAssertEqual(cache.lastUpdatedAt, now)
    }
}
