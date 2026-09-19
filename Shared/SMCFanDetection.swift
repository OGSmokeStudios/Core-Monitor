import Foundation

enum SMCFanDetection {
    // The SMC key format reserves one decimal character for the fan ID.
    nonisolated static let maximumFanCount = 10

    nonisolated static func supports(fanID: Int) -> Bool {
        (0..<maximumFanCount).contains(fanID)
    }

    nonisolated static func validatedCount(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value > 0,
              value <= Double(maximumFanCount), value.rounded(.towardZero) == value else { return nil }
        return Int(value)
    }

    /// Return the span of discovered fan IDs, so callers also visit later fans
    /// when an earlier fan's keys are unavailable.
    nonisolated static func fallbackCount(keyExists: (String) -> Bool) -> Int {
        var count = 0
        for fanID in 0..<maximumFanCount {
            let actualKey = String(format: "F%dAc", fanID)
            let minKey = String(format: "F%dMn", fanID)
            let maxKey = String(format: "F%dMx", fanID)
            if keyExists(actualKey) || keyExists(minKey) || keyExists(maxKey) {
                count = fanID + 1
            }
        }
        return count
    }
}
