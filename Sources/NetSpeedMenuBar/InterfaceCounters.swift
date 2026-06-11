import Darwin
import Foundation

/// Cumulative byte counters summed over all non-loopback interfaces,
/// read from the kernel via `getifaddrs` (`AF_LINK` entries carry `if_data`).
struct InterfaceCounters: Sendable {
    let received: UInt64
    let sent: UInt64

    static func read() -> InterfaceCounters {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else {
            return InterfaceCounters(received: 0, sent: 0)
        }
        defer { freeifaddrs(first) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor = first
        while let pointer = cursor {
            let interface = pointer.pointee
            cursor = interface.ifa_next

            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let rawData = interface.ifa_data
            else { continue }

            let name = String(cString: interface.ifa_name)
            guard !name.hasPrefix("lo") else { continue }

            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            received &+= UInt64(data.ifi_ibytes)
            sent &+= UInt64(data.ifi_obytes)
        }
        return InterfaceCounters(received: received, sent: sent)
    }
}
