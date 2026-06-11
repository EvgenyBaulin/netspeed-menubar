import AppKit
import SwiftUI

/// Popover content: three chart cards (Download, Upload, Ping) stacked on the
/// popover's system material, plus a header with the connection type, a VPN
/// badge, Details…, settings gear, and Quit.
struct PopoverView: View {
    @ObservedObject var monitor: NetMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var speedTester: SpeedTester
    let onOpenSettings: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        let now = Date()
        let window = settings.chartWindow.seconds
        let xDomain = now.addingTimeInterval(-window) ... now

        VStack(spacing: 10) {
            header

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
                subtitle: pingSubtitle,
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

            speedTestRow
        }
        .padding(12)
        .frame(width: 340)
    }

    private var speedTestRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "speedometer")
                .font(.caption)
                .foregroundStyle(.secondary)
            if speedTester.isRunning {
                ProgressView()
                    .controlSize(.small)
                Text("\(speedTester.phase?.label ?? L("Testing…"))… \(MbpsFormatter.string(speedTester.progressMbps))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else if let result = speedTester.lastResult {
                Text("↓ \(MbpsFormatter.string(result.downloadMbps))   ↑ \(MbpsFormatter.string(result.uploadMbps))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                // A failed re-test must not hide the previous valid result.
                Text(speedTester.lastFailed
                    ? L("Test failed")
                    : result.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if speedTester.lastFailed {
                Text(L("Test failed"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L("Speed Test"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                speedTester.run()
            } label: {
                Image(systemName: "play.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(speedTester.isRunning)
            .help(L("Run Test"))
            .accessibilityLabel(L("Run Test"))
        }
        .padding(.horizontal, 2)
    }

    private var pingSubtitle: String {
        let jitterText = "\(L("Jitter")) \(PingFormatter.string(monitor.jitter))"
        let lossText = "\(L("Loss")) \(PercentFormatter.string(monitor.packetLoss))"
        return "\(jitterText) · \(lossText)"
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: monitor.connection.symbolName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(monitor.connection.displayName)
                .font(.headline)
                .foregroundStyle(.primary)
            if monitor.vpnActive {
                Label(L("VPN"), systemImage: "lock.shield")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .help(L("VPN Active"))
                    .accessibilityLabel(L("VPN Active"))
            }
            Spacer()
            Button(L("Details…"), action: onOpenDetails)
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("Settings…"))
            .accessibilityLabel(L("Settings"))
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("Quit NetSpeed"))
            .accessibilityLabel(L("Quit"))
        }
        .padding(.horizontal, 2)
    }
}
