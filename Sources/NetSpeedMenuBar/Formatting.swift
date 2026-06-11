import Foundation

enum ByteRateFormatter {
    /// Formats bytes/s as `0 B/s` → `999 KB/s` → `12.4 MB/s` → `1.2 GB/s`.
    static func string(_ bytesPerSecond: Double) -> String {
        var value = max(bytesPerSecond, 0)
        var unitIndex = 0
        let units = ["B", "KB", "MB", "GB"]
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        let number = unitIndex == 0
            ? String(Int(value))
            : String(format: value < 100 ? "%.1f" : "%.0f", value)
        return "\(number) \(units[unitIndex])/s"
    }
}

enum PingFormatter {
    static func string(_ milliseconds: Double?) -> String {
        guard let milliseconds else { return "—" }
        return String(format: "%.0f ms", milliseconds)
    }
}

enum ChartScale {
    /// Rounds a maximum up to a "nice" value (1/2/5 × 10ⁿ) for a stable Y axis.
    static func niceMax(_ maxValue: Double) -> Double {
        guard maxValue > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(maxValue)))
        let normalized = maxValue / magnitude
        let nice: Double
        if normalized <= 1 { nice = 1 } else if normalized <= 2 { nice = 2 } else if normalized <= 5 { nice = 5 } else { nice = 10 }
        return nice * magnitude
    }
}
