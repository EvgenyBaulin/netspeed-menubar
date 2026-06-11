import AppKit
import Foundation
import Network
import SystemConfiguration

enum ConnectionType: Sendable {
    case wifi
    case hotspot
    case wired
    case offline

    var symbolName: String {
        switch self {
        case .wifi:
            return "wifi"
        case .hotspot:
            return "personalhotspot"
        case .wired:
            // Fall back to a generic icon if the symbol is missing.
            let preferred = "cable.connector"
            let exists = NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil
            return exists ? preferred : "network"
        case .offline:
            return "wifi.slash"
        }
    }

    var displayName: String {
        switch self {
        case .wifi: return L("Wi-Fi")
        case .hotspot: return L("Personal Hotspot")
        case .wired: return L("Ethernet")
        case .offline: return L("Offline")
        }
    }
}

struct Sample: Identifiable, Sendable {
    let id: Int
    let time: Date
    let value: Double
}

@MainActor
final class NetMonitor: ObservableObject {
    @Published private(set) var downSpeed: Double = 0 // bytes per second
    @Published private(set) var upSpeed: Double = 0 // bytes per second
    @Published private(set) var ping: Double? // milliseconds; nil when unavailable
    @Published private(set) var jitter: Double? // ms, mean |Δ| of recent RTTs
    @Published private(set) var packetLoss: Double = 0 // percent over recent cycles
    @Published private(set) var connection: ConnectionType = .offline
    @Published private(set) var downHistory: [Sample] = []
    @Published private(set) var upHistory: [Sample] = []
    @Published private(set) var pingHistory: [Sample] = []

    let settings: AppSettings

    // Buffers always hold the largest selectable window (1 hour), so shrinking
    // and re-growing the chart window never discards fresh data.
    nonisolated static let speedInterval: TimeInterval = 1
    nonisolated static let pingInterval: TimeInterval = 3
    private let speedHistoryLimit = 3600
    private let pingHistoryLimit = 1200
    private let pingStatsWindow = 20 // recent ping cycles used for jitter/loss

    private var speedTimer: Timer?
    private var pingTimer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var lastCounters: InterfaceCounters?
    private var lastSampleTime: TimeInterval?
    private var speedSeq = 0
    private var pingSeq = 0
    private var pingInFlight = false
    private var pingAttempts: [(sent: Int, ok: Int)] = []

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        guard speedTimer == nil else { return }

        lastCounters = InterfaceCounters.read()
        lastSampleTime = ProcessInfo.processInfo.systemUptime

        let speedTimer = Timer(timeInterval: Self.speedInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleSpeed() }
        }
        RunLoop.main.add(speedTimer, forMode: .common)
        self.speedTimer = speedTimer

        let pingTimer = Timer(timeInterval: Self.pingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.samplePing() }
        }
        RunLoop.main.add(pingTimer, forMode: .common)
        self.pingTimer = pingTimer
        samplePing()

        startPathMonitor()
    }

    func stop() {
        speedTimer?.invalidate()
        speedTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    // MARK: - Speed

    private func sampleSpeed() {
        let now = ProcessInfo.processInfo.systemUptime
        let counters = InterfaceCounters.read()
        defer {
            lastCounters = counters
            lastSampleTime = now
        }
        guard let last = lastCounters, let lastTime = lastSampleTime else { return }

        let dt = max(now - lastTime, 0.001)
        // Counters are 32-bit and wrap; clamp negative deltas to zero.
        let down = counters.received >= last.received
            ? Double(counters.received - last.received) / dt : 0
        let up = counters.sent >= last.sent
            ? Double(counters.sent - last.sent) / dt : 0

        downSpeed = down
        upSpeed = up
        speedSeq += 1
        let stamp = Date()
        push(Sample(id: speedSeq, time: stamp, value: down), into: &downHistory, limit: speedHistoryLimit)
        push(Sample(id: speedSeq, time: stamp, value: up), into: &upHistory, limit: speedHistoryLimit)
    }

    private func push(_ sample: Sample, into history: inout [Sample], limit: Int) {
        history.append(sample)
        if history.count > limit {
            history.removeFirst(history.count - limit)
        }
    }

    // MARK: - Ping

    private func samplePing() {
        guard !pingInFlight else { return }
        let hosts = settings.pingHosts.isEmpty ? [AppSettings.defaultPingHost] : settings.pingHosts
        pingInFlight = true
        Task.detached(priority: .utility) { [weak self] in
            // All hosts in parallel; one slow host costs one cycle, not N.
            let results = await withTaskGroup(of: Double?.self) { group in
                for host in hosts {
                    group.addTask { Pinger.ping(host: host) }
                }
                var collected: [Double?] = []
                for await result in group { collected.append(result) }
                return collected
            }
            await MainActor.run { self?.finishPing(results) }
        }
    }

    private func finishPing(_ results: [Double?]) {
        pingInFlight = false

        let successes = results.compactMap(\.self)
        pingAttempts.append((sent: results.count, ok: successes.count))
        if pingAttempts.count > pingStatsWindow {
            pingAttempts.removeFirst(pingAttempts.count - pingStatsWindow)
        }
        let sent = pingAttempts.reduce(0) { $0 + $1.sent }
        let ok = pingAttempts.reduce(0) { $0 + $1.ok }
        packetLoss = sent > 0 ? 100 * Double(sent - ok) / Double(sent) : 0

        guard !successes.isEmpty else {
            // Failed cycle = a gap in the data: no sample, no sentinel value.
            ping = nil
            jitter = nil
            return
        }
        let average = successes.reduce(0, +) / Double(successes.count)
        ping = average
        pingSeq += 1
        push(Sample(id: pingSeq, time: Date(), value: average), into: &pingHistory, limit: pingHistoryLimit)

        let recent = pingHistory.suffix(pingStatsWindow).map(\.value)
        if recent.count >= 2 {
            let diffs = zip(recent.dropFirst(), recent).map { abs($0 - $1) }
            jitter = diffs.reduce(0, +) / Double(diffs.count)
        } else {
            jitter = nil
        }
    }

    // MARK: - Connection type

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let type = NetMonitor.classify(path)
            Task { @MainActor [weak self] in
                self?.connection = type
            }
        }
        monitor.start(queue: DispatchQueue(label: "netspeed.pathmonitor"))
        pathMonitor = monitor
    }

    private nonisolated static func classify(_ path: NWPath) -> ConnectionType {
        guard path.status == .satisfied else { return .offline }
        if path.usesInterfaceType(.wifi) {
            // Honest limitation: a Personal Hotspot joined over Wi-Fi is
            // indistinguishable from a regular Wi-Fi network without private
            // APIs, so it is reported as Wi-Fi.
            return .wifi
        }
        if path.usesInterfaceType(.wiredEthernet) {
            let bsdName = path.availableInterfaces.first { $0.type == .wiredEthernet }?.name
            if let bsdName, isPersonalHotspotPort(bsdName: bsdName) {
                return .hotspot
            }
            return .wired
        }
        return .wired
    }

    /// USB tethering to an iPhone/iPad shows up as a wired Ethernet hardware
    /// port whose localized name is "iPhone USB" / "iPad USB". This is the
    /// only reliable, public-API way to detect Personal Hotspot (cable only).
    nonisolated static func isPersonalHotspotPort(bsdName: String) -> Bool {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return false
        }
        for interface in interfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  bsd == bsdName,
                  let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            else { continue }
            return display.localizedCaseInsensitiveContains("iPhone")
                || display.localizedCaseInsensitiveContains("iPad")
        }
        return false
    }
}
