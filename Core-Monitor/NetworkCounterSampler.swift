import Darwin
import Foundation

struct NetworkCounter {
    let sent: UInt64
    let received: UInt64
}

struct NetworkCounterTracker {
    private var previous: [UInt16: NetworkCounter] = [:]
    private var previousTime: TimeInterval?

    mutating func sample(_ counters: [UInt16: NetworkCounter], at time: TimeInterval) -> (sent: Double, received: Double) {
        defer {
            previous = counters
            previousTime = time
        }
        guard let previousTime, time > previousTime else { return (0, 0) }
        var sent: Double = 0
        var received: Double = 0
        for (id, value) in counters {
            guard let old = previous[id] else { continue }
            // A newly created/reset interface needs its own baseline. Its
            // lifetime counters must not be charged to this sampling interval.
            if value.sent >= old.sent { sent += Double(value.sent - old.sent) }
            if value.received >= old.received { received += Double(value.received - old.received) }
        }
        let elapsed = time - previousTime
        return (sent / elapsed, received / elapsed)
    }
}

enum NetworkCounterReader {
    /// NET_RT_IFLIST2 supplies 64-bit counters; getifaddrs' if_data truncates
    /// byte counts to 32 bits and can wrap repeatedly during a background sample.
    static func read() -> [UInt16: NetworkCounter]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        for _ in 0..<3 {
            var length = 0
            guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0 else { return nil }
            var data = [UInt8](repeating: 0, count: length)
            let result = data.withUnsafeMutableBytes { buffer in
                sysctl(&mib, u_int(mib.count), buffer.baseAddress, &length, nil, 0)
            }
            if result != 0 {
                if errno == ENOMEM { continue }
                return nil
            }
            guard length <= data.count else { continue }
            return data.withUnsafeBytes { buffer in
                decode(UnsafeRawBufferPointer(rebasing: buffer.prefix(length)))
            }
        }
        return nil
    }

    static func decode(_ buffer: UnsafeRawBufferPointer) -> [UInt16: NetworkCounter]? {
        var counters: [UInt16: NetworkCounter] = [:]
        var offset = 0
        while offset < buffer.count {
            guard buffer.count - offset >= 4 else { return nil }
            let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            guard length >= 4, length <= buffer.count - offset else { return nil }
            let messageType = buffer[offset + 3]
            if messageType == RTM_IFINFO2 {
                guard length >= MemoryLayout<if_msghdr2>.size else { return nil }
                let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                if header.ifm_flags & IFF_LOOPBACK == 0 {
                    counters[header.ifm_index] = NetworkCounter(
                        sent: header.ifm_data.ifi_obytes,
                        received: header.ifm_data.ifi_ibytes
                    )
                }
            }
            offset += length
        }
        return counters
    }
}
