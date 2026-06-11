import Foundation

private func formatNumber(_ value: Double, fractionDigits: Int) -> String {
    value.formatted(.number.precision(.fractionLength(fractionDigits)))
}

enum ByteRateFormatter {
    /// Formats bytes/s in the given unit, locale-aware (decimal comma in RU).
    /// Raw values are always bytes/s; bits = bytes × 8 (decimal multiples),
    /// bytes use binary multiples.
    static func string(_ bytesPerSecond: Double, unit: SpeedUnit = .auto) -> String {
        let v = max(bytesPerSecond, 0)
        switch unit {
        case .auto:
            return autoString(v)
        case .mbytePerSec:
            return fixed(v / 1_048_576, suffix: L("MB/s"))
        case .kbytePerSec:
            return fixed(v / 1024, suffix: L("KB/s"))
        case .mbitPerSec:
            return fixed(v * 8 / 1_000_000, suffix: L("Mbit/s"))
        case .kbitPerSec:
            return fixed(v * 8 / 1000, suffix: L("Kbit/s"))
        }
    }

    private static func autoString(_ v: Double) -> String {
        var value = v
        var unitIndex = 0
        let units = [L("B/s"), L("KB/s"), L("MB/s"), L("GB/s")]
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        let digits = unitIndex == 0 ? 0 : (value < 100 ? 1 : 0)
        return "\(formatNumber(value, fractionDigits: digits)) \(units[unitIndex])"
    }

    private static func fixed(_ value: Double, suffix: String) -> String {
        let digits = value < 100 ? 1 : 0
        return "\(formatNumber(value, fractionDigits: digits)) \(suffix)"
    }
}

enum PingFormatter {
    /// RTT in ms, locale-aware; sub-10 ms values keep one decimal so small
    /// latencies don't collapse to "0 ms". nil → "—".
    static func string(_ milliseconds: Double?) -> String {
        guard let milliseconds else { return "—" }
        let digits = milliseconds < 10 ? 1 : 0
        return "\(formatNumber(max(milliseconds, 0), fractionDigits: digits)) \(L("ms"))"
    }
}

enum MbpsFormatter {
    static func string(_ mbps: Double?) -> String {
        guard let mbps, mbps.isFinite else { return "—" }
        let digits = mbps < 100 ? 1 : 0
        return "\(formatNumber(max(mbps, 0), fractionDigits: digits)) \(L("Mbit/s"))"
    }
}

enum PercentFormatter {
    static func string(_ percent: Double) -> String {
        let digits: Int = percent > 0 && percent < 10 ? 1 : 0
        // CLDR places the percent sign per locale ("12.5%" en, "12,5 %" ru).
        return (percent / 100).formatted(.percent.precision(.fractionLength(digits)))
    }
}

enum ChartScale {
    /// Rounds a maximum up to a "nice" value (1/2/5 × 10ⁿ) for a stable Y axis.
    static func niceMax(_ maxValue: Double) -> Double {
        guard maxValue > 0, maxValue.isFinite else { return 1 }
        let magnitude = pow(10, floor(log10(maxValue)))
        let normalized = maxValue / magnitude
        let nice: Double
        if normalized <= 1 { nice = 1 } else if normalized <= 2 { nice = 2 } else if normalized <= 5 { nice = 5 } else { nice = 10 }
        return nice * magnitude
    }
}
