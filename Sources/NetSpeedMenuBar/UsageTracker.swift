import Foundation

/// Cumulative received/sent byte counters for the current session, day, and
/// month, fed from the same interface-counter deltas as the speed display.
/// Day/month aggregates persist in UserDefaults and roll over automatically.
@MainActor
final class UsageTracker: ObservableObject {
    struct Bucket: Sendable {
        var received: UInt64 = 0
        var sent: UInt64 = 0
    }

    @Published private(set) var session = Bucket()
    @Published private(set) var today = Bucket()
    @Published private(set) var month = Bucket()

    private enum Keys {
        static let todayKey = "usage.today.key"
        static let todayRx = "usage.today.rx"
        static let todayTx = "usage.today.tx"
        static let monthKey = "usage.month.key"
        static let monthRx = "usage.month.rx"
        static let monthTx = "usage.month.tx"
    }

    private let defaults = UserDefaults.standard
    private var todayKey: String
    private var monthKey: String
    private var unsavedTicks = 0

    init() {
        let (day, month) = Self.currentKeys()
        todayKey = day
        monthKey = month
        if defaults.string(forKey: Keys.todayKey) == day {
            today = Bucket(
                received: UInt64(max(0, defaults.integer(forKey: Keys.todayRx))),
                sent: UInt64(max(0, defaults.integer(forKey: Keys.todayTx)))
            )
        }
        if defaults.string(forKey: Keys.monthKey) == month {
            self.month = Bucket(
                received: UInt64(max(0, defaults.integer(forKey: Keys.monthRx))),
                sent: UInt64(max(0, defaults.integer(forKey: Keys.monthTx)))
            )
        }
    }

    func add(received: UInt64, sent: UInt64) {
        rolloverIfNeeded()
        session.received &+= received
        session.sent &+= sent
        today.received &+= received
        today.sent &+= sent
        month.received &+= received
        month.sent &+= sent
        unsavedTicks += 1
        if unsavedTicks >= 15 { save() }
    }

    func reset() {
        session = Bucket()
        today = Bucket()
        month = Bucket()
        save()
    }

    func save() {
        defaults.set(todayKey, forKey: Keys.todayKey)
        defaults.set(Int(clamping: today.received), forKey: Keys.todayRx)
        defaults.set(Int(clamping: today.sent), forKey: Keys.todayTx)
        defaults.set(monthKey, forKey: Keys.monthKey)
        defaults.set(Int(clamping: month.received), forKey: Keys.monthRx)
        defaults.set(Int(clamping: month.sent), forKey: Keys.monthTx)
        unsavedTicks = 0
    }

    private func rolloverIfNeeded() {
        let (day, month) = Self.currentKeys()
        if day != todayKey {
            todayKey = day
            today = Bucket()
        }
        if month != monthKey {
            monthKey = month
            self.month = Bucket()
        }
    }

    private static func currentKeys() -> (day: String, month: String) {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let year = parts.year ?? 0
        let monthNumber = parts.month ?? 0
        let day = parts.day ?? 0
        return (
            String(format: "%04d-%02d-%02d", year, monthNumber, day),
            String(format: "%04d-%02d", year, monthNumber)
        )
    }
}
