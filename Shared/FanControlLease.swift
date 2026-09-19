import Foundation

/// Serialized by the helper's controller queue. Record ownership before a
/// hardware write so even a partially failed write is covered by recovery.
struct FanControlLease {
    static let duration: TimeInterval = 15
    private struct Entry {
        let owner: UUID
        var expiresAt: TimeInterval
    }
    private var entries: [Int: Entry] = [:]

    var fanIDs: [Int] { entries.keys.sorted() }

    func canControl(_ fanID: Int, owner: UUID) -> Bool {
        entries[fanID] == nil || entries[fanID]?.owner == owner
    }

    mutating func acquire(_ fanID: Int, owner: UUID, now: TimeInterval) -> Bool {
        guard canControl(fanID, owner: owner) else { return false }
        entries[fanID] = Entry(owner: owner, expiresAt: now + Self.duration)
        return true
    }

    mutating func renewed(owner: UUID, now: TimeInterval) -> Bool {
        var renewed = false
        for id in fanIDs where entries[id]?.owner == owner {
            guard let entry = entries[id], entry.expiresAt > now else { continue }
            entries[id]?.expiresAt = now + Self.duration
            renewed = true
        }
        return renewed
    }

    mutating func release(_ fanID: Int) { entries[fanID] = nil }

    mutating func expire(owner: UUID) {
        for id in fanIDs where entries[id]?.owner == owner { entries[id]?.expiresAt = 0 }
    }

    /// Keep failed restores due, so a transient SMC failure is retried.
    mutating func restoreExpired(now: TimeInterval, restore: (Int) throws -> Void) -> [Int] {
        var failed: [Int] = []
        for id in fanIDs where (entries[id]?.expiresAt ?? .infinity) <= now {
            do {
                try restore(id)
                entries[id] = nil
            } catch {
                failed.append(id)
            }
        }
        return failed
    }
}
