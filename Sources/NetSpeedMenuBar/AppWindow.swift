import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case network
    case speedTest
    case apps
    case usage
    case log
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .network: return L("Network")
        case .speedTest: return L("Speed Test")
        case .apps: return L("Apps")
        case .usage: return L("Usage")
        case .log: return L("Log")
        case .settings: return L("Settings")
        }
    }

    var symbolName: String {
        switch self {
        case .network: return "network"
        case .speedTest: return "speedometer"
        case .apps: return "app.badge"
        case .usage: return "arrow.up.arrow.down"
        case .log: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class WindowState: ObservableObject {
    @Published var section: AppSection? = .network
}

/// The application window: sidebar sections Network / Apps / Usage / Log /
/// Settings, opened from the panel ("Details…", gear) or the right-click menu.
struct AppWindowView: View {
    @ObservedObject var monitor: NetMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var state: WindowState
    @ObservedObject var appTraffic: AppTrafficMonitor
    @ObservedObject var speedTester: SpeedTester

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $state.section) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            switch state.section ?? .network {
            case .network:
                NetworkSectionView(monitor: monitor, settings: settings)
            case .speedTest:
                SpeedTestSectionView(tester: speedTester, settings: settings)
            case .apps:
                AppsSectionView(appTraffic: appTraffic)
            case .usage:
                UsageSectionView(usage: monitor.usage)
            case .log:
                LogSectionView(log: monitor.connectivityLog)
            case .settings:
                SettingsView(settings: settings)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
    }
}

// MARK: - Speed Test

/// Active channel-capacity measurement. The passive monitor shows actual
/// traffic; available bandwidth requires loading the connection.
struct SpeedTestSectionView: View {
    @ObservedObject var tester: SpeedTester
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section(L("Last test")) {
                if let result = tester.lastResult {
                    LabeledContent(L("Download")) {
                        Text(MbpsFormatter.string(result.downloadMbps))
                            .monospacedDigit()
                    }
                    LabeledContent(L("Upload")) {
                        Text(MbpsFormatter.string(result.uploadMbps))
                            .monospacedDigit()
                    }
                    LabeledContent(L("Ping")) {
                        Text(PingFormatter.string(result.pingMs))
                            .monospacedDigit()
                    }
                    Text(result.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L("No data yet"))
                        .foregroundStyle(.secondary)
                }
                if tester.lastFailed {
                    Text(L("Test failed"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    tester.run()
                } label: {
                    if tester.isRunning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L("Testing…"))
                        }
                    } else {
                        Text(L("Run Test"))
                    }
                }
                .disabled(tester.isRunning)

                Picker(L("Auto test"), selection: $settings.speedTestInterval) {
                    ForEach(SpeedTestInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                Text(L("Each test transfers tens of megabytes of data."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(L("The menu bar shows actual current traffic; channel capacity is measured by loading the connection, like any speed test."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.speedTestInterval) {
            tester.applyAutoInterval(settings.speedTestInterval)
        }
    }
}

// MARK: - Network

/// Physical carrier and VPN tunnel shown separately, so the real connection
/// stays visible even while a VPN routes all traffic — plus the same three
/// interactive charts as the panel (shared ChartCard: hover/drag inspection).
struct NetworkSectionView: View {
    @ObservedObject var monitor: NetMonitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        let now = Date()
        let window = settings.chartWindow.seconds
        let xDomain = now.addingTimeInterval(-window) ... now

        ScrollView {
            VStack(spacing: 10) {
                infoCard(title: L("Physical Connection")) {
                    HStack {
                        Label(monitor.connection.displayName, systemImage: monitor.connection.symbolName)
                        Spacer()
                        if let interface = monitor.physicalInterface {
                            Text(interface)
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                infoCard(title: L("VPN Tunnel")) {
                    if monitor.vpnActive {
                        HStack {
                            Label(
                                monitor.vpnServiceNames.isEmpty
                                    ? L("VPN Active")
                                    : monitor.vpnServiceNames.joined(separator: ", "),
                                systemImage: "lock.shield"
                            )
                            Spacer()
                            if let tunnel = monitor.vpnInterface {
                                Text(tunnel)
                                    .font(.callout)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text(L("Not active"))
                            .foregroundStyle(.secondary)
                    }
                }

                ChartCard(
                    title: L("Download"),
                    valueText: ByteRateFormatter.string(monitor.downSpeed, unit: settings.downloadUnit),
                    segments: ChartData.prepare(
                        monitor.downHistory,
                        window: window,
                        now: now,
                        expectedInterval: NetMonitor.speedInterval
                    ),
                    xDomain: xDomain,
                    tint: .blue,
                    axisLabel: { ByteRateFormatter.string($0, unit: settings.downloadUnit) }
                )
                ChartCard(
                    title: L("Upload"),
                    valueText: ByteRateFormatter.string(monitor.upSpeed, unit: settings.uploadUnit),
                    segments: ChartData.prepare(
                        monitor.upHistory,
                        window: window,
                        now: now,
                        expectedInterval: NetMonitor.speedInterval
                    ),
                    xDomain: xDomain,
                    tint: .green,
                    axisLabel: { ByteRateFormatter.string($0, unit: settings.uploadUnit) }
                )
                ChartCard(
                    title: L("Ping"),
                    valueText: PingFormatter.string(monitor.ping),
                    segments: ChartData.prepare(
                        monitor.pingHistory,
                        window: window,
                        now: now,
                        expectedInterval: NetMonitor.pingInterval
                    ),
                    xDomain: xDomain,
                    tint: .orange,
                    axisLabel: { PingFormatter.string($0) }
                )
            }
            .padding(12)
        }
    }

    private func infoCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Apps

/// Per-process traffic via nettop sampling — an approximation; see the
/// footer note and README for the honest limitation.
struct AppsSectionView: View {
    @ObservedObject var appTraffic: AppTrafficMonitor

    var body: some View {
        VStack(spacing: 0) {
            Table(appTraffic.entries) {
                TableColumn(L("Process")) { entry in
                    Text(entry.name)
                        .lineLimit(1)
                }
                TableColumn("↓") { entry in
                    Text(ByteRateFormatter.string(entry.rxRate))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 95)
                TableColumn("↑") { entry in
                    Text(ByteRateFormatter.string(entry.txRate))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 95)
            }
            .overlay {
                if !appTraffic.available {
                    Text(L("Couldn't read per-app traffic (nettop)."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if appTraffic.entries.isEmpty {
                    if appTraffic.collecting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L("Collecting data…"))
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(L("No data yet"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            Text(L("Per-app traffic is an approximation based on nettop; some system traffic may be unattributed."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .onAppear { appTraffic.startWatching() }
        .onDisappear { appTraffic.stopWatching() }
    }
}

// MARK: - Usage

struct UsageSectionView: View {
    @ObservedObject var usage: UsageTracker

    var body: some View {
        Form {
            Section(L("Session")) {
                usageRows(usage.session)
            }
            Section(L("Today")) {
                usageRows(usage.today)
            }
            Section(L("This Month")) {
                usageRows(usage.month)
            }
            Section {
                Button(L("Reset"), role: .destructive) {
                    usage.reset()
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func usageRows(_ bucket: UsageTracker.Bucket) -> some View {
        LabeledContent(L("Received")) {
            Text(Int64(clamping: bucket.received).formatted(.byteCount(style: .binary)))
                .monospacedDigit()
        }
        LabeledContent(L("Sent")) {
            Text(Int64(clamping: bucket.sent).formatted(.byteCount(style: .binary)))
                .monospacedDigit()
        }
    }
}

// MARK: - Log

struct LogSectionView: View {
    @ObservedObject var log: ConnectivityLog

    var body: some View {
        Group {
            if log.events.isEmpty {
                Text(L("No events"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(log.events) { event in
                    HStack(alignment: .firstTextBaseline) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(L("Connection lost"))
                                    .font(.callout.weight(.medium))
                                Text(event.start.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "wifi.slash")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(durationText(event))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func durationText(_ event: OutageEvent) -> String {
        guard let end = event.end else { return L("ongoing") }
        let seconds = max(end.timeIntervalSince(event.start), 0)
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)
        )
    }
}
