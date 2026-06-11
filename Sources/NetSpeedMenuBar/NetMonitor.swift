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
        case .wifi: return "Wi-Fi"
        case .hotspot: return "Personal Hotspot"
        case .wired: return "Ethernet"
        case .offline: return "Offline"
        }
    }
}

struct Sample: Identifiable, Sendable {
    let id: Int
    let value: Double
}

@MainActor
final class NetMonitor: ObservableObject {
    nonisolated static let pingHost = "1.1.1.1"

    @Published private(set) var downSpeed: Double = 0 // bytes per second
    @Published private(set) var upSpeed: Double = 0 // bytes per second
    @Published private(set) var ping: Double? // milliseconds; nil when unavailable
    @Published private(set) var connection: ConnectionType = .offline
    @Published private(set) var downHistory: [Sample] = []
    @Published private(set) var upHistory: [Sample] = []
    @Published private(set) var pingHistory: [Sample] = []

    private let historyLimit = 60
    private var speedTimer: Timer?
    private var pingTimer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var lastCounters: InterfaceCounters?
    private var lastSampleTime: TimeInterval?
    private var speedSeq = 0
    private var pingSeq = 0
    private var pingInFlight = false

    func start() {
        guard speedTimer == nil else { return }

        lastCounters = InterfaceCounters.read()
        lastSampleTime = ProcessInfo.processInfo.systemUptime

        let speedTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleSpeed() }
        }
        RunLoop.main.add(speedTimer, forMode: .common)
        self.speedTimer = speedTimer

        let pingTimer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
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
        push(Sample(id: speedSeq, value: down), into: &downHistory)
        push(Sample(id: speedSeq, value: up), into: &upHistory)
    }

    private func push(_ sample: Sample, into history: inout [Sample]) {
        history.append(sample)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }

    // MARK: - Ping

    private func samplePing() {
        guard !pingInFlight else { return }
        pingInFlight = true
        Task.detached(priority: .utility) { [weak self] in
            let rtt = Pinger.ping(host: NetMonitor.pingHost)
            await MainActor.run { self?.finishPing(rtt) }
        }
    }

    private func finishPing(_ rtt: Double?) {
        pingInFlight = false
        ping = rtt
        if let rtt {
            pingSeq += 1
            push(Sample(id: pingSeq, value: rtt), into: &pingHistory)
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
    private nonisolated static func isPersonalHotspotPort(bsdName: String) -> Bool {
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
