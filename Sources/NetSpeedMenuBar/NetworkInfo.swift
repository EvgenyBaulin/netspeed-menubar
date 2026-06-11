import Darwin
import Foundation
import SystemConfiguration

/// Physical-carrier and VPN information, determined independently of which
/// interface holds the default route — so the real connection (Wi-Fi or
/// Ethernet) stays visible even while a VPN tunnel routes all traffic.
enum NetworkInfo {
    struct Physical: Sendable {
        let bsdName: String
        let type: ConnectionType
    }

    /// The active hardware interface (`en*` with a routable IP, up & running).
    /// Returns the lowest-numbered candidate — typically the primary port.
    static func activePhysical() -> Physical? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return nil }
        defer { freeifaddrs(first) }

        var candidates: [String] = []
        var cursor = first
        while let pointer = cursor {
            let interface = pointer.pointee
            cursor = interface.ifa_next

            guard let address = interface.ifa_addr else { continue }
            let family = address.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            let flags = interface.ifa_flags
            guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_RUNNING) != 0 else { continue }

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") else { continue }

            // Skip link-local addresses: an interface that only has one is
            // not actually connected anywhere.
            if family == UInt8(AF_INET) {
                let sin = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee
                let host = UInt32(bigEndian: sin.sin_addr.s_addr)
                if host >> 16 == 0xA9FE { continue } // 169.254.0.0/16
            } else {
                let sin6 = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in6.self).pointee
                let leading = withUnsafeBytes(of: sin6.sin6_addr) { ($0[0], $0[1]) }
                if leading.0 == 0xFE, leading.1 & 0xC0 == 0x80 { continue } // fe80::/10
            }

            if !candidates.contains(name) { candidates.append(name) }
        }

        // "en0" before "en1" before "en24" — order by number, not lexicographically.
        guard let name = candidates.min(by: { ($0.count, $0) < ($1.count, $1) }) else {
            return nil
        }
        return Physical(bsdName: name, type: classifyHardware(bsdName: name))
    }

    /// Wi-Fi vs Ethernet vs USB-tethered hotspot, from the hardware port.
    static func classifyHardware(bsdName: String) -> ConnectionType {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return .wired
        }
        for interface in interfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  bsd == bsdName else { continue }
            if let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
               type == kSCNetworkInterfaceTypeIEEE80211 as String {
                return .wifi
            }
            if NetMonitor.isPersonalHotspotPort(bsdName: bsdName) {
                return .hotspot
            }
            return .wired
        }
        return .wired
    }

    /// Names of VPN services that `scutil --nc list` reports as Connected.
    /// Covers personal-VPN/NE-based configurations; tunnels that bypass the
    /// network-connection store are still caught by the route check
    /// (default-route interface = utun*/ppp*/ipsec*). Blocking — call off
    /// the main thread.
    static func connectedVPNServices() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--nc", "list"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return [] }

        return output.split(separator: "\n").compactMap { line in
            guard line.contains("(Connected)") else { return nil }
            let quoted = line.split(separator: "\"")
            guard quoted.count >= 2 else { return nil }
            return String(quoted[1])
        }
    }

    /// True if the interface name is a tunnel (utun/ppp/ipsec).
    static func isTunnelName(_ name: String) -> Bool {
        name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec")
    }
}
