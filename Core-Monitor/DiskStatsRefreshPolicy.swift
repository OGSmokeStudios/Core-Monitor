import Foundation

enum DiskStatsRefreshPolicy {
    static let minimumRefreshInterval: TimeInterval = 30

    static func shouldRefresh(
        lastUpdatedAt: Date?,
        now: Date,
        minimumInterval: TimeInterval = minimumRefreshInterval
    ) -> Bool {
        guard let lastUpdatedAt else { return true }
        return now.timeIntervalSince(lastUpdatedAt) >= minimumInterval
    }
}

/// Owned by the sampling queue. Failed reads preserve both the last good
/// reading and its timestamp, allowing another attempt on the next sample.
struct DiskStatsCache {
    private(set) var stats = DiskStats()
    private(set) var lastUpdatedAt: Date?

    mutating func read(now: Date, load: () throws -> DiskStats?) -> DiskStats {
        guard DiskStatsRefreshPolicy.shouldRefresh(lastUpdatedAt: lastUpdatedAt, now: now),
              let refreshed = try? load() else {
            return stats
        }
        stats = refreshed
        lastUpdatedAt = now
        return stats
    }
}
