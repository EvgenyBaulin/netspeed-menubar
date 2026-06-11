import AppKit
import SwiftUI

/// Popover content: three chart cards (Download, Upload, Ping) stacked on the
/// popover's system material, plus a header with the connection type and Quit.
struct PopoverView: View {
    @ObservedObject var monitor: NetMonitor

    var body: some View {
        VStack(spacing: 10) {
            header

            ChartCard(
                title: "Download",
                valueText: ByteRateFormatter.string(monitor.downSpeed),
                samples: monitor.downHistory,
                tint: .blue,
                axisLabel: { ByteRateFormatter.string($0) }
            )
            ChartCard(
                title: "Upload",
                valueText: ByteRateFormatter.string(monitor.upSpeed),
                samples: monitor.upHistory,
                tint: .green,
                axisLabel: { ByteRateFormatter.string($0) }
            )
            ChartCard(
                title: "Ping",
                valueText: PingFormatter.string(monitor.ping),
                samples: monitor.pingHistory,
                tint: .orange,
                axisLabel: { String(format: "%.0f ms", $0) }
            )
        }
        .padding(12)
        .frame(width: 340)
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
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit NetSpeed")
        }
        .padding(.horizontal, 2)
    }
}
