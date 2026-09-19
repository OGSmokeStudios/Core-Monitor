import XCTest
@testable import Core_Monitor

@MainActor
final class BatteryDetailFormatterTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    func testChargingRuntimeUsesPowerAdapterLanguage() {
        var info = BatteryInfo()
        info.hasBattery = true
        info.isCharging = true
        info.isPluggedIn = true
        info.timeRemainingMinutes = 95
        info.source = "AC Power"

        XCTAssertEqual(BatteryDetailFormatter.powerStateDescription(for: info, locale: english), "Charging")
        XCTAssertEqual(BatteryDetailFormatter.sourceDescription(for: info, locale: english), "Power Adapter")
        XCTAssertEqual(BatteryDetailFormatter.runtimeDescription(for: info, locale: english), "1h 35m until full")
    }

    func testBatteryRuntimeUsesRemainingLanguage() {
        var info = BatteryInfo()
        info.hasBattery = true
        info.isCharging = false
        info.isPluggedIn = false
        info.timeRemainingMinutes = 42
        info.source = "Battery Power"

        XCTAssertEqual(BatteryDetailFormatter.powerStateDescription(for: info, locale: english), "Battery Power")
        XCTAssertEqual(BatteryDetailFormatter.sourceDescription(for: info, locale: english), "Internal Battery")
        XCTAssertEqual(BatteryDetailFormatter.runtimeDescription(for: info, locale: english), "42m remaining")
    }

    func testFormatterUsesStablePrecisionForElectricalValues() {
        XCTAssertEqual(BatteryDetailFormatter.temperatureDescription(31.26, locale: english), "31.3 °C")
        // Check precision without assuming a rounding rule at an exact midpoint.
        XCTAssertEqual(BatteryDetailFormatter.voltageDescription(12.346, locale: english), "12.35 V")
        XCTAssertEqual(BatteryDetailFormatter.amperageDescription(-1.234, locale: english), "-1.23 A")
    }

    func testElectricalValuesFollowExplicitLocale() {
        let locale = Locale(identifier: "de_DE")
        XCTAssertEqual(BatteryDetailFormatter.temperatureDescription(31.26, locale: locale), "31,3 °C")
        XCTAssertEqual(BatteryDetailFormatter.voltageDescription(12.346, locale: locale), "12,35 V")
        XCTAssertEqual(BatteryDetailFormatter.amperageDescription(-1.234, locale: locale), "-1,23 A")
    }

    func testBatteryLabelsAndRuntimeFollowSelectedLanguage() throws {
        let locale = Locale(identifier: "sv_SE")
        var info = BatteryInfo()
        info.hasBattery = true
        info.timeRemainingMinutes = 42
        XCTAssertEqual(BatteryDetailFormatter.sourceDescription(for: info, locale: locale), "Internt batteri")
        let runtime = try XCTUnwrap(BatteryDetailFormatter.runtimeDescription(for: info, locale: locale))
        XCTAssertTrue(runtime.hasSuffix(" kvar"), runtime)
        info.isCharging = true
        info.timeRemainingMinutes = 0
        XCTAssertEqual(BatteryDetailFormatter.runtimeDescription(for: info, locale: locale), "Snart klart")
    }
}
