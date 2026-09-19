import Darwin
import XCTest
@testable import Core_Monitor

@MainActor
final class RuntimeSafetyTests: XCTestCase {
    func testStoppedSessionDiscardsLateResult() throws {
        var session = SamplingSession()
        XCTAssertNil(session.begin())
        session.start()
        let old = try XCTUnwrap(session.begin())
        session.stop()
        XCTAssertFalse(session.complete(old))
        XCTAssertNil(session.begin())
    }

    func testOldCompletionCannotClearNewSessionsInFlightSample() throws {
        var session = SamplingSession()
        session.start()
        let old = try XCTUnwrap(session.begin())
        session.stop()
        session.start()
        let current = try XCTUnwrap(session.begin())
        XCTAssertFalse(session.complete(old))
        XCTAssertNil(session.begin())
        XCTAssertTrue(session.complete(current))
        XCTAssertNotNil(session.begin())
    }

    func testDuplicateCompletionIsRejected() throws {
        var session = SamplingSession()
        session.start()
        let ticket = try XCTUnwrap(session.begin())
        XCTAssertTrue(session.complete(ticket))
        XCTAssertFalse(session.complete(ticket))
        let next = try XCTUnwrap(session.begin())
        XCTAssertFalse(session.complete(ticket))
        XCTAssertTrue(session.complete(next))
    }

    func testNetworkCountsMoreThanOne32BitWrapBetweenSamples() {
        var tracker = NetworkCounterTracker()
        _ = tracker.sample([1: NetworkCounter(sent: 100, received: 200)], at: 1)
        let bytes: UInt64 = 3 * (UInt64(UInt32.max) + 1)
        let rates = tracker.sample([1: NetworkCounter(sent: 100 + bytes, received: 200 + bytes)], at: 31)
        XCTAssertEqual(rates.sent, Double(bytes) / 30, accuracy: 0.001)
        XCTAssertEqual(rates.received, Double(bytes) / 30, accuracy: 0.001)
    }

    func testInterfaceRemovalAdditionAndResetDoNotCorruptOtherRates() {
        var tracker = NetworkCounterTracker()
        _ = tracker.sample([
            1: NetworkCounter(sent: 100, received: 100),
            2: NetworkCounter(sent: 1_000, received: 1_000)
        ], at: 1)
        let added = tracker.sample([
            1: NetworkCounter(sent: 200, received: 300),
            3: NetworkCounter(sent: 90_000, received: 80_000)
        ], at: 2)
        XCTAssertEqual(added.sent, 100)
        XCTAssertEqual(added.received, 200)
        let reset = tracker.sample([
            1: NetworkCounter(sent: 1, received: 1),
            3: NetworkCounter(sent: 90_500, received: 80_600)
        ], at: 3)
        XCTAssertEqual(reset.sent, 500)
        XCTAssertEqual(reset.received, 600)
    }

    func testNetworkDecoderReads64BitCountersAndExcludesLoopback() throws {
        var network = if_msghdr2()
        network.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
        network.ifm_type = UInt8(RTM_IFINFO2)
        network.ifm_index = 2
        network.ifm_data.ifi_obytes = UInt64(UInt32.max) + 100
        network.ifm_data.ifi_ibytes = UInt64(UInt32.max) + 200
        var loopback = network
        loopback.ifm_index = 1
        loopback.ifm_flags = IFF_LOOPBACK
        var bytes = withUnsafeBytes(of: &network) { Array($0) }
        bytes += withUnsafeBytes(of: &loopback) { Array($0) }
        let counters = try XCTUnwrap(bytes.withUnsafeBytes(NetworkCounterReader.decode))
        XCTAssertEqual(counters.count, 1)
        XCTAssertEqual(counters[2]?.sent, UInt64(UInt32.max) + 100)
        XCTAssertEqual(counters[2]?.received, UInt64(UInt32.max) + 200)
    }

    func testNetworkDecoderRejectsTruncatedAndZeroLengthMessages() {
        let samples: [[UInt8]] = [[0], [0, 0, 0, 0], [20, 0, 0, UInt8(RTM_IFINFO2)]]
        for bytes in samples {
            XCTAssertNil(bytes.withUnsafeBytes(NetworkCounterReader.decode))
        }
    }

    func testOnlySingleDigitFanIDsAndValidCountsAreAccepted() {
        XCTAssertTrue(SMCFanDetection.supports(fanID: 0))
        XCTAssertTrue(SMCFanDetection.supports(fanID: 9))
        for id in [-1, 10, 11, Int.max] { XCTAssertFalse(SMCFanDetection.supports(fanID: id)) }
        for value in [Double.nan, .infinity, -1, 0, 1.5, 11] {
            XCTAssertNil(SMCFanDetection.validatedCount(value))
        }
        XCTAssertEqual(SMCFanDetection.validatedCount(2), 2)
        var keys: [String] = []
        XCTAssertEqual(SMCFanDetection.fallbackCount { keys.append($0); return false }, 0)
        XCTAssertTrue(keys.allSatisfy { $0.utf8.count == 4 })
    }

    func testCrashExpirationRestoresEveryOwnedFan() {
        var lease = FanControlLease()
        let owner = UUID()
        XCTAssertTrue(lease.acquire(0, owner: owner, now: 0))
        XCTAssertTrue(lease.acquire(1, owner: owner, now: 0))
        var restored: [Int] = []
        _ = lease.restoreExpired(now: FanControlLease.duration - 1) { restored.append($0) }
        XCTAssertTrue(restored.isEmpty)
        _ = lease.restoreExpired(now: FanControlLease.duration) { restored.append($0) }
        XCTAssertEqual(restored, [0, 1])
        XCTAssertTrue(lease.fanIDs.isEmpty)
    }

    func testHeartbeatKeepsUnchangedTargetsLeased() {
        var lease = FanControlLease()
        let owner = UUID()
        _ = lease.acquire(0, owner: owner, now: 0)
        XCTAssertTrue(lease.renewed(owner: owner, now: 10))
        var restored: [Int] = []
        _ = lease.restoreExpired(now: 15) { restored.append($0) }
        XCTAssertTrue(restored.isEmpty)
        _ = lease.restoreExpired(now: 25) { restored.append($0) }
        XCTAssertEqual(restored, [0])
    }

    func testDisconnectRestoresOnlyThatClientsFansAndRetriesFailures() {
        enum Failure: Error { case unavailable }
        var lease = FanControlLease()
        let first = UUID(), second = UUID()
        _ = lease.acquire(0, owner: first, now: 0)
        _ = lease.acquire(1, owner: second, now: 0)
        XCTAssertFalse(lease.acquire(0, owner: second, now: 1))
        lease.expire(owner: first)
        XCTAssertEqual(lease.restoreExpired(now: 2) { _ in throw Failure.unavailable }, [0])
        XCTAssertEqual(lease.fanIDs, [0, 1])
        var restored: [Int] = []
        _ = lease.restoreExpired(now: 3) { restored.append($0) }
        XCTAssertEqual(restored, [0])
        XCTAssertEqual(lease.fanIDs, [1])
        XCTAssertFalse(lease.renewed(owner: first, now: 3))
    }

    func testExpiredLeaseCannotBeRevivedByLateHeartbeat() {
        var lease = FanControlLease()
        let owner = UUID()
        _ = lease.acquire(0, owner: owner, now: 0)
        XCTAssertFalse(lease.renewed(owner: owner, now: 16))
        var restored: [Int] = []
        _ = lease.restoreExpired(now: 16) { restored.append($0) }
        XCTAssertEqual(restored, [0])
    }

    func testRepeatedAlertsReuseIdentityWhileDifferentRulesStaySeparate() {
        let first = AlertManager.notificationIdentifier(for: .cpuTemperature)
        XCTAssertEqual(first, AlertManager.notificationIdentifier(for: .cpuTemperature))
        XCTAssertNotEqual(first, AlertManager.notificationIdentifier(for: .fanTooLowUnderHeat))
        let identifiers = AlertRuleKind.allCases.map(AlertManager.notificationIdentifier)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }
}
