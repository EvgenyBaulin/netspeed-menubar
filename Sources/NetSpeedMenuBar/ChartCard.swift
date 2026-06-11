import Charts
import SwiftUI

/// One titled chart on a Liquid Glass material card: header with the current
/// value (and optional subtitle), a smoothed line over history with a soft
/// gradient fill, time-based X axis covering the selected window, and real
/// gaps where measurements are missing.
struct ChartCard: View {
    let title: String
    let valueText: String
    var subtitle: String?
    let segments: [ChartSegment]
    let xDomain: ClosedRange<Date>
    let tint: Color
    let axisLabel: (Double) -> String

    private var yMax: Double {
        ChartScale.niceMax(segments.flatMap(\.samples).map(\.value).max() ?? 0)
    }

    private var xAxisFormat: Date.FormatStyle {
        let window = xDomain.upperBound.timeIntervalSince(xDomain.lowerBound)
        return window <= 120
            ? .dateTime.minute().second()
            : .dateTime.hour().minute()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Text(valueText)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            Chart {
                ForEach(segments) { segment in
                    ForEach(segment.samples) { sample in
                        AreaMark(
                            x: .value("Time", sample.time),
                            y: .value(title, sample.value),
                            series: .value("Segment", segment.id),
                            stacking: .unstacked
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [tint.opacity(0.25), tint.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", sample.time),
                            y: .value(title, sample.value),
                            series: .value("Segment", segment.id)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }
                }
            }
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine()
                        .foregroundStyle(.quaternary)
                    AxisValueLabel(format: xAxisFormat)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                        .foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(axisLabel(number))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYScale(domain: 0 ... yMax)
            .frame(height: 76)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
