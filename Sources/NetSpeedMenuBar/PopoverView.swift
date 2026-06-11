import AppKit
import SwiftUI

/// Popover content: three chart cards (Download, Upload, Ping) stacked on the
/// popover's system material, plus a header with the connection type, a
/// settings gear, and Quit.
struct PopoverView: View {
    @ObservedObject var monitor: NetMonitor
    @ObservedObject var settings: AppSettings
    let onOpenSettings: () -> Void

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
        }
        .padding(12)
        .frame(width: 340)
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
            Spacer()
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
                Label(L("Quit"), systemImage: "power")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("Quit NetSpeed"))
        }
        .padding(.horizontal, 2)
    }
}
