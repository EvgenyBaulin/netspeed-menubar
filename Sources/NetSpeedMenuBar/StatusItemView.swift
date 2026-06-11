import SwiftUI

/// Menu-bar label with three user-selectable layouts (Full / Compact /
/// Icon only) and two content sources: live traffic (passive counters) or
/// channel capacity (latest periodic speed-test result). Ping is always the
/// live measurement.
struct StatusItemView: View {
    @ObservedObject var monitor: NetMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var speedTester: SpeedTester

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
                    line(arrow: "↓", text: downText, size: 9)
                    line(arrow: "↑", text: upText, size: 9)
                }
                .frame(minWidth: 58, alignment: .leading)

                Text(PingFormatter.string(monitor.ping))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            case .compact:
                HStack(spacing: 6) {
                    line(arrow: "↓", text: downText, size: 11)
                    line(arrow: "↑", text: upText, size: 11)
                }
            case .iconOnly:
                EmptyView()
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
    }

    private var downText: String {
        switch settings.barContent {
        case .traffic:
            return ByteRateFormatter.string(monitor.downSpeed)
        case .capacity:
            return MbpsFormatter.string(speedTester.lastResult?.downloadMbps)
        }
    }

    private var upText: String {
        switch settings.barContent {
        case .traffic:
            return ByteRateFormatter.string(monitor.upSpeed)
        case .capacity:
            return MbpsFormatter.string(speedTester.lastResult?.uploadMbps)
        }
    }

    private func line(arrow: String, text: String, size: CGFloat) -> some View {
        Text("\(arrow) \(text)")
            .font(.system(size: size, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
    }
}
