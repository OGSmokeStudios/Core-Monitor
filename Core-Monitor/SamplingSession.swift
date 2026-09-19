import Foundation

/// Main-thread lifecycle gate for work completed on a background queue.
struct SamplingSession {
    private var generation: UInt64 = 0
    private var active = false
    private var inFlight = false

    mutating func start() {
        generation &+= 1
        active = true
        inFlight = false
    }

    mutating func stop() {
        generation &+= 1
        active = false
        inFlight = false
    }

    mutating func begin() -> UInt64? {
        guard active, !inFlight else { return nil }
        inFlight = true
        return generation
    }

    mutating func complete(_ ticket: UInt64) -> Bool {
        guard active, inFlight, ticket == generation else { return false }
        inFlight = false
        return true
    }
}
