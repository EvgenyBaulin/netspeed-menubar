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

/// Persistent user preferences (UserDefaults-backed) plus launch-at-login
/// state, which lives in SMAppService rather than defaults.
@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let downloadUnit = "downloadUnit"
        static let uploadUnit = "uploadUnit"
        static let chartWindow = "chartWindowSeconds"
        static let pingHosts = "pingHosts"
        static let barMode = "barMode"
    }

    static let defaultPingHost = "1.1.1.1"

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
    @Published var pingHosts: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(pingHosts) {
                defaults.set(data, forKey: Keys.pingHosts)
            }
        }
    }
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginError: String?

    init() {
        downloadUnit = SpeedUnit(rawValue: defaults.string(forKey: Keys.downloadUnit) ?? "") ?? .auto
        uploadUnit = SpeedUnit(rawValue: defaults.string(forKey: Keys.uploadUnit) ?? "") ?? .auto
        chartWindow = ChartWindow(rawValue: defaults.integer(forKey: Keys.chartWindow)) ?? .fiveMinutes
        barMode = BarMode(rawValue: defaults.string(forKey: Keys.barMode) ?? "") ?? .full
        if let data = defaults.data(forKey: Keys.pingHosts),
           let hosts = try? JSONDecoder().decode([String].self, from: data),
           !hosts.isEmpty {
            pingHosts = hosts
        } else {
            pingHosts = [Self.defaultPingHost]
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
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "\(L("Couldn't change Launch at Login")): \(error.localizedDescription)"
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
