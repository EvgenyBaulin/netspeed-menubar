import SwiftUI

/// Compact menu-bar label: connection icon, stacked ↓/↑ speeds, and ping
/// vertically centered between the two speed lines.
struct StatusItemView: View {
    @ObservedObject var monitor: NetMonitor

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: monitor.connection.symbolName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 0) {
                speedLine(arrow: "↓", bytesPerSecond: monitor.downSpeed)
                speedLine(arrow: "↑", bytesPerSecond: monitor.upSpeed)
            }
            .frame(minWidth: 58, alignment: .leading)

            Text(PingFormatter.string(monitor.ping))
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .fixedSize()
    }

    private func speedLine(arrow: String, bytesPerSecond: Double) -> some View {
        Text("\(arrow) \(ByteRateFormatter.string(bytesPerSecond))")
            .font(.system(size: 9, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
    }
}
