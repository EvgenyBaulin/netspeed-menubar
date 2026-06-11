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
    @Published private(set) var physicalInterface: String?
    @Published private(set) var vpnActive = false
    @Published private(set) var vpnServiceNames: [String] = []
    @Published private(set) var vpnInterface: String?
    @Published private(set) var downHistory: [Sample] = []
    @Published private(set) var upHistory: [Sample] = []
    @Published private(set) var pingHistory: [Sample] = []

    let settings: AppSettings
    let usage = UsageTracker()
    let connectivityLog = ConnectivityLog()

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
    private var pingCycles: [[(host: String, ok: Bool)]] = []

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
        usage.save()
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

        // Counters are 32-bit and wrap; clamp negative deltas to zero.
        let deltaRx = counters.received >= last.received ? counters.received - last.received : 0
        let deltaTx = counters.sent >= last.sent ? counters.sent - last.sent : 0
        let dt = max(now - lastTime, 0.001)

        downSpeed = Double(deltaRx) / dt
        upSpeed = Double(deltaTx) / dt
        usage.add(received: deltaRx, sent: deltaTx)

        speedSeq += 1
        let stamp = Date()
        push(Sample(id: speedSeq, time: stamp, value: downSpeed), into: &downHistory, limit: speedHistoryLimit)
        push(Sample(id: speedSeq, time: stamp, value: upSpeed), into: &upHistory, limit: speedHistoryLimit)
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
        let addresses = settings.pingHosts.map(\.address)
        let hosts = addresses.isEmpty ? [AppSettings.defaultPingHost] : addresses
        pingInFlight = true
        Task.detached(priority: .utility) { [weak self] in
            // All hosts in parallel; one slow host costs one cycle, not N.
            let results = await withTaskGroup(of: (String, Double?).self) { group in
                for host in hosts {
                    group.addTask { (host, await Pinger.ping(host: host)) }
                }
                var collected: [(String, Double?)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            await MainActor.run { self?.finishPing(results) }
        }
    }

    private func finishPing(_ results: [(String, Double?)]) {
        pingInFlight = false

        let successes = results.compactMap(\.1)
        pingCycles.append(results.map { (host: $0.0, ok: $0.1 != nil) })
        if pingCycles.count > pingStatsWindow {
            pingCycles.removeFirst(pingCycles.count - pingStatsWindow)
        }
        recomputePacketLoss()

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

    /// Loss is computed only over hosts that answered at least once in the
    /// stats window — a host that is down (or doesn't answer ICMP at all)
    /// would otherwise read as permanent fake loss. All hosts silent → 100%.
    private func recomputePacketLoss() {
        var perHost: [String: (sent: Int, ok: Int)] = [:]
        for cycle in pingCycles {
            for sample in cycle {
                perHost[sample.host, default: (0, 0)].sent += 1
                if sample.ok {
                    perHost[sample.host, default: (0, 0)].ok += 1
                }
            }
        }
        let reachable = perHost.values.filter { $0.ok > 0 }
        if reachable.isEmpty {
            packetLoss = perHost.isEmpty ? 0 : 100
        } else {
            let sent = reachable.reduce(0) { $0 + $1.sent }
            let ok = reachable.reduce(0) { $0 + $1.ok }
            packetLoss = sent > 0 ? 100 * Double(sent - ok) / Double(sent) : 0
        }
    }

    // MARK: - Connection type & VPN

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let fallback = NetMonitor.classify(path)
            // The default-route interface: a tunnel here means a VPN is
            // actually routing traffic (idle utun* interfaces always exist).
            let routeInterface = path.availableInterfaces.first?.name
            let tunnel = routeInterface.flatMap { NetworkInfo.isTunnelName($0) ? $0 : nil }
            // Physical carrier, independent of the default route, so Wi-Fi /
            // Ethernet stays visible while a VPN holds the route.
            let physical = NetworkInfo.activePhysical()
            let vpnServices = NetworkInfo.connectedVPNServices()

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.connectivityLog.update(satisfied: satisfied)
                self.vpnInterface = tunnel
                self.vpnServiceNames = vpnServices
                self.vpnActive = tunnel != nil || !vpnServices.isEmpty
                if satisfied {
                    self.connection = physical?.type ?? fallback
                    self.physicalInterface = physical?.bsdName
                } else {
                    self.connection = .offline
                    self.physicalInterface = nil
                }
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
