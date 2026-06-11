import Foundation

/// Per-process traffic rates, approximated by sampling `nettop` cumulative
/// byte counters and diffing consecutive snapshots.
///
/// Honest limitation: there is no clean public API for per-app traffic
/// without a NetworkExtension content filter, so this is an approximation
/// via `nettop`; some system traffic may not be attributed. No privilege
/// escalation is used or required.
@MainActor
final class AppTrafficMonitor: ObservableObject {
    struct Entry: Identifiable, Sendable {
        let id: String // "name.pid" from nettop
        let name: String
        let rxRate: Double // bytes/s
        let txRate: Double // bytes/s
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var available = true
    @Published private(set) var collecting = false

    nonisolated static let interval: TimeInterval = 5

    private var timer: Timer?
    private var quickTimer: Timer?
    private var previous: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousTime: TimeInterval?
    private var sampling = false
    private var watchers = 0
    private var quickRefreshPending = false

    /// Sampling runs only while at least one view is watching.
    func startWatching() {
        watchers += 1
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        collecting = true
        quickRefreshPending = true
        sample()
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
        quickTimer?.invalidate()
        quickTimer = nil
        previous = [:]
        previousTime = nil
        entries = []
        collecting = false
        quickRefreshPending = false
    }

    private func sample() {
        guard !sampling else { return }
        sampling = true
        Task.detached(priority: .utility) { [weak self] in
            let snapshot = Nettop.snapshot()
            await MainActor.run { self?.finish(snapshot) }
        }
    }

    private func finish(_ snapshot: [String: (rx: UInt64, tx: UInt64)]?) {
        sampling = false
        // A snapshot can land after the last watcher left; discard it so a
        // stale baseline doesn't skew the first refresh next time.
        guard watchers > 0 else { return }
        guard let snapshot else {
            available = false
            return
        }
        available = true
        let now = ProcessInfo.processInfo.systemUptime
        defer {
            previous = snapshot
            previousTime = now
        }
        guard let previousTime, !previous.isEmpty else {
            // Baseline established; refresh quickly once so the table isn't
            // empty for a full interval after opening the section.
            if quickRefreshPending {
                quickRefreshPending = false
                let quick = Timer(timeInterval: 1.5, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sample() }
                }
                RunLoop.main.add(quick, forMode: .common)
                quickTimer = quick
            }
            return
        }
        let dt = max(now - previousTime, 0.5)

        collecting = false
        entries = snapshot
            .compactMap { key, counts -> Entry? in
                guard let before = previous[key] else { return nil } // new process: need 2 samples
                let deltaRx = counts.rx >= before.rx ? counts.rx - before.rx : 0
                let deltaTx = counts.tx >= before.tx ? counts.tx - before.tx : 0
                guard deltaRx > 0 || deltaTx > 0 else { return nil }
                let name = key.contains(".")
                    ? key.split(separator: ".").dropLast().joined(separator: ".")
                    : key
                return Entry(id: key, name: name, rxRate: Double(deltaRx) / dt, txRate: Double(deltaTx) / dt)
            }
            .sorted { $0.rxRate + $0.txRate > $1.rxRate + $1.txRate }
            .prefix(40)
            .map { $0 }
    }
}

private enum Nettop {
    /// One `nettop` logging sample: cumulative bytes in/out per process.
    /// Blocking — call off the main thread. Returns nil if nettop fails.
    static func snapshot() -> [String: (rx: UInt64, tx: UInt64)]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-x", "-L", "1", "-J", "bytes_in,bytes_out"]
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
              let output = String(data: data, encoding: .utf8) else { return nil }

        // Format: header ",bytes_in,bytes_out," then "name.pid,123,456," rows.
        // Process names may contain dots/commas, so parse from the right.
        var result: [String: (rx: UInt64, tx: UInt64)] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 4,
                  let rx = UInt64(fields[fields.count - 3]),
                  let tx = UInt64(fields[fields.count - 2]) else { continue }
            let key = fields[0 ..< fields.count - 3].joined(separator: ",")
            guard !key.isEmpty else { continue }
            result[key] = (rx, tx)
        }
        return result
    }
}
