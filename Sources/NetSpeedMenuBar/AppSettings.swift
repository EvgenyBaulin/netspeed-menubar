import Foundation
import ServiceManagement

enum SpeedUnit: String, CaseIterable, Identifiable, Sendable {
    case auto
    case mbitPerSec
    case mbytePerSec
    case kbitPerSec
    case kbytePerSec

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return L("Auto")
        case .mbitPerSec: return L("Mbit/s")
        case .mbytePerSec: return L("MB/s")
        case .kbitPerSec: return L("Kbit/s")
        case .kbytePerSec: return L("KB/s")
        }
    }
}

enum ChartWindow: Int, CaseIterable, Identifiable, Sendable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case oneHour = 3600

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .oneMinute: return L("1 min")
        case .fiveMinutes: return L("5 min")
        case .fifteenMinutes: return L("15 min")
        case .oneHour: return L("1 hour")
        }
    }
}

enum BarMode: String, CaseIterable, Identifiable, Sendable {
    case full
    case compact
    case iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: return L("Full")
        case .compact: return L("Compact")
        case .iconOnly: return L("Icon Only")
        }
    }
}

enum SpeedTestInterval: Int, CaseIterable, Identifiable, Sendable {
    case off = 0
    case minutes15 = 15
    case minutes30 = 30
    case hour1 = 60
    case hours3 = 180

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: return L("Off")
        case .minutes15: return L("Every 15 min")
        case .minutes30: return L("Every 30 min")
        case .hour1: return L("Every hour")
        case .hours3: return L("Every 3 hours")
        }
    }
}

enum BarContent: String, CaseIterable, Identifiable, Sendable {
    case traffic
    case capacity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .traffic: return L("Current traffic")
        case .capacity: return L("Channel capacity (speed test)")
        }
    }
}

/// A ping target with a user-editable label.
struct PingHost: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var address: String
    var label: String

    init(id: UUID = UUID(), address: String, label: String = "") {
        self.id = id
        self.address = address
        self.label = label
    }
}

/// Persistent user preferences (UserDefaults-backed) plus launch-at-login
/// state, which lives in SMAppService rather than defaults.
@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let downloadUnit = "downloadUnit"
        static let uploadUnit = "uploadUnit"
        static let chartWindow = "chartWindowSeconds"
        static let pingHostsLegacy = "pingHosts" // v2: [String]
        static let pingHosts = "pingHostsV2" // v3+: [PingHost]
        static let barMode = "barMode"
        static let barContent = "barContent"
        static let speedTestInterval = "speedTestIntervalMinutes"
        static let language = "appLanguage"
    }

    static let defaultPingHost = "1.1.1.1"

    /// Well-known anycast resolvers — stable, geographically distributed
    /// ping targets.
    static func defaultHosts() -> [PingHost] {
        [
            PingHost(address: "1.1.1.1", label: "Cloudflare DNS"),
            PingHost(address: "8.8.8.8", label: "Google DNS"),
            PingHost(address: "9.9.9.9", label: "Quad9 DNS"),
            PingHost(address: "208.67.222.222", label: "OpenDNS"),
            PingHost(address: "94.140.14.14", label: "AdGuard DNS"),
            PingHost(address: "77.88.8.8", label: "Yandex DNS"),
            PingHost(address: "4.2.2.2", label: "Level 3 (Lumen)"),
            PingHost(address: "64.6.64.6", label: "UltraDNS Public"),
            PingHost(address: "185.228.168.9", label: "CleanBrowsing DNS"),
            PingHost(address: "76.76.2.0", label: "Control D DNS"),
        ]
    }

    private let defaults = UserDefaults.standard

    @Published var downloadUnit: SpeedUnit {
        didSet { defaults.set(downloadUnit.rawValue, forKey: Keys.downloadUnit) }
    }
    @Published var uploadUnit: SpeedUnit {
        didSet { defaults.set(uploadUnit.rawValue, forKey: Keys.uploadUnit) }
    }
    @Published var chartWindow: ChartWindow {
        didSet { defaults.set(chartWindow.rawValue, forKey: Keys.chartWindow) }
    }
    @Published var barMode: BarMode {
        didSet { defaults.set(barMode.rawValue, forKey: Keys.barMode) }
    }
    @Published var barContent: BarContent {
        didSet { defaults.set(barContent.rawValue, forKey: Keys.barContent) }
    }
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            LocalizationState.shared.language = language
        }
    }
    @Published var speedTestInterval: SpeedTestInterval {
        didSet { defaults.set(speedTestInterval.rawValue, forKey: Keys.speedTestInterval) }
    }
    @Published var pingHosts: [PingHost] {
        didSet {
            if let data = try? JSONEncoder().encode(pingHosts) {
                defaults.set(data, forKey: Keys.pingHosts)
            }
        }
    }
    @Published private(set) var launchAtLogin = false
    // Only the OS-provided detail is stored; the localized prefix is built at
    // render time so it follows live language switches.
    @Published private(set) var launchAtLoginErrorDetail: String?

    init() {
        downloadUnit = SpeedUnit(rawValue: defaults.string(forKey: Keys.downloadUnit) ?? "") ?? .auto
        uploadUnit = SpeedUnit(rawValue: defaults.string(forKey: Keys.uploadUnit) ?? "") ?? .auto
        chartWindow = ChartWindow(rawValue: defaults.integer(forKey: Keys.chartWindow)) ?? .fiveMinutes
        barMode = BarMode(rawValue: defaults.string(forKey: Keys.barMode) ?? "") ?? .full
        barContent = BarContent(rawValue: defaults.string(forKey: Keys.barContent) ?? "") ?? .traffic
        speedTestInterval = SpeedTestInterval(rawValue: defaults.integer(forKey: Keys.speedTestInterval)) ?? .off
        let storedLanguage = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        language = storedLanguage
        LocalizationState.shared.language = storedLanguage

        if let data = defaults.data(forKey: Keys.pingHosts),
           let hosts = try? JSONDecoder().decode([PingHost].self, from: data),
           !hosts.isEmpty {
            pingHosts = hosts
        } else {
            // First run (or migration from the v2 plain-string list): seed the
            // labeled defaults and keep any custom hosts the user had added.
            var seeded = Self.defaultHosts()
            if let legacy = defaults.data(forKey: Keys.pingHostsLegacy),
               let addresses = try? JSONDecoder().decode([String].self, from: legacy) {
                for address in addresses
                where !seeded.contains(where: { $0.address == address }) {
                    seeded.append(PingHost(address: address))
                }
            }
            pingHosts = seeded
            if let data = try? JSONEncoder().encode(seeded) {
                defaults.set(data, forKey: Keys.pingHosts)
            }
        }
        refreshLaunchAtLogin()
    }

    // MARK: - Launch at Login (SMAppService)

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginErrorDetail = nil
        } catch {
            launchAtLoginErrorDetail = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    // MARK: - Host validation

    nonisolated static func isValidHost(_ raw: String) -> Bool {
        let host = raw.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, host.count <= 253 else { return false }

        // IPv4
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        if octets.count == 4, octets.allSatisfy({ !$0.isEmpty && UInt8($0) != nil }) {
            return true
        }
        // IPv6 (loose)
        if host.contains(":") {
            return host.allSatisfy { $0.isHexDigit || $0 == ":" }
        }
        // Hostname: dot-separated labels of [A-Za-z0-9-], not starting/ending with '-'
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return false }
        return labels.allSatisfy { label in
            guard !label.isEmpty, label.count <= 63,
                  !label.hasPrefix("-"), !label.hasSuffix("-") else { return false }
            return label.allSatisfy { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "-" }
        }
    }
}
