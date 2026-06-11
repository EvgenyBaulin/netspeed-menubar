import Foundation

enum Pinger {
    /// Runs `/sbin/ping -c 1 -t 2 <host>` and returns the round-trip time in
    /// milliseconds, or `nil` on timeout/error. Blocking — call off the main
    /// thread.
    static func ping(host: String) -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-t", "2", host]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
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
