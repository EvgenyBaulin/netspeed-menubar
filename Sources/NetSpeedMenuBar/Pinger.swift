import Foundation

enum Pinger {
    /// Pings `host` once and returns the round-trip time in milliseconds, or
    /// `nil` on timeout/error. Blocking — call off the main thread.
    ///
    /// IPv4 targets use `/sbin/ping -c 1 -t 2`; IPv6 literals go to
    /// `/sbin/ping6`, which has no overall-deadline flag (its `-t` is an
    /// ICMPv6 node-information query), so the deadline is enforced by
    /// terminating the process externally.
    static func ping(host: String) -> Double? {
        let isIPv6 = host.contains(":")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: isIPv6 ? "/sbin/ping6" : "/sbin/ping")
        process.arguments = isIPv6 ? ["-c", "1", host] : ["-c", "1", "-t", "2", host]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        if isIPv6 {
            // PID reuse within 2.5s is not a realistic concern on macOS.
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
                kill(pid, SIGTERM)
            }
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8),
              let timeRange = output.range(of: "time=")
        else { return nil }

        let tail = output[timeRange.upperBound...]
        let number = tail.prefix { $0.isNumber || $0 == "." }
        return Double(number)
    }
}
