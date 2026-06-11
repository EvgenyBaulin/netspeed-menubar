import SwiftUI

/// Menu-bar label with three user-selectable layouts:
/// Full — connection icon, stacked ↓/↑ speeds, ping centered between them;
/// Compact — icon plus one line of ↓/↑;
/// Icon only — just the connection icon.
struct StatusItemView: View {
    @ObservedObject var monitor: NetMonitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: monitor.connection.symbolName)
                .font(.system(size: settings.barMode == .iconOnly ? 14 : 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 16)
                .accessibilityLabel(monitor.connection.displayName)

            switch settings.barMode {
            case .full:
                VStack(alignment: .leading, spacing: 0) {
                    speedLine(arrow: "↓", bytesPerSecond: monitor.downSpeed, size: 9)
                    speedLine(arrow: "↑", bytesPerSecond: monitor.upSpeed, size: 9)
                }
                .frame(minWidth: 58, alignment: .leading)

                Text(PingFormatter.string(monitor.ping))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            case .compact:
                HStack(spacing: 6) {
                    speedLine(arrow: "↓", bytesPerSecond: monitor.downSpeed, size: 11)
                    speedLine(arrow: "↑", bytesPerSecond: monitor.upSpeed, size: 11)
                }
            case .iconOnly:
                EmptyView()
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
    }

    private func speedLine(arrow: String, bytesPerSecond: Double, size: CGFloat) -> some View {
        Text("\(arrow) \(ByteRateFormatter.string(bytesPerSecond))")
            .font(.system(size: size, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
    }
}
