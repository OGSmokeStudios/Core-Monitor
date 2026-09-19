import Foundation

enum SMCFanDetection {
    /// Return the span of discovered fan IDs, so callers also visit later fans
    /// when an earlier fan's keys are unavailable.
    nonisolated static func fallbackCount(keyExists: (String) -> Bool) -> Int {
        var count = 0
        for fanID in 0..<12 {
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
