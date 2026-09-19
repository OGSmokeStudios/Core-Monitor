import XCTest
@testable import Core_Monitor

@MainActor
final class FanReadingTests: XCTestCase {
    func testFallbackFindsBothFansWithoutFNum() {
        let keys: Set<String> = ["F0Ac", "F0Mn", "F0Mx", "F1Ac", "F1Mn", "F1Mx"]

        XCTAssertEqual(SMCFanDetection.fallbackCount(keyExists: keys.contains), 2)
    }

    func testFallbackHandlesSingleFanAndNoFans() {
        XCTAssertEqual(SMCFanDetection.fallbackCount { $0 == "F0Ac" }, 1)
        XCTAssertEqual(SMCFanDetection.fallbackCount { _ in false }, 0)
    }

    func testFallbackKeepsScanningPastMissingFanIDs() {
        let keys: Set<String> = ["F0Ac", "F3Ac"]

        XCTAssertEqual(SMCFanDetection.fallbackCount(keyExists: keys.contains), 4)
    }

    func testFallbackUsesBoundaryKeysWhenActualRPMIsUnavailable() {
        let keys: Set<String> = ["F0Mn", "F1Mx"]

        XCTAssertEqual(SMCFanDetection.fallbackCount(keyExists: keys.contains), 2)
    }

    func testFanLabelShowsZeroForStoppedFans() {
        for speeds in [[0], [0, 0], [-1, 0]] {
            let label = SingleMenuBarItemController.fanStatusLabel(speeds: speeds, maximumRPM: 5_000)

            XCTAssertEqual(label.text, "0", "Speeds: \(speeds)")
            XCTAssertEqual(label.tone, .normal)
        }
    }

    func testFanLabelShowsUnavailableOnlyWithoutValidReadings() {
        for speeds in [[], [-1], [-1, -1]] {
            let label = SingleMenuBarItemController.fanStatusLabel(speeds: speeds, maximumRPM: 5_000)

            XCTAssertEqual(label.text, "—")
            XCTAssertEqual(label.tone, .secondary)
        }
    }

    func testFanLabelKeepsHighestValidSpeedAndUtilizationTone() {
        let label = SingleMenuBarItemController.fanStatusLabel(speeds: [-1, 0, 2_000, 4_500], maximumRPM: 5_000)

        XCTAssertEqual(label.text, "4.5k")
        XCTAssertEqual(label.tone, .critical)
    }
}
