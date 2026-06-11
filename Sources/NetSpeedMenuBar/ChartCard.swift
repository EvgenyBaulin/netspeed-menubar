import Charts
import SwiftUI

/// One titled chart on a Liquid Glass material card: header with the current
/// value, a smoothed line over history, and a soft gradient fill underneath.
struct ChartCard: View {
    let title: String
    let valueText: String
    let samples: [Sample]
    let tint: Color
    let axisLabel: (Double) -> String

    private var yMax: Double {
        ChartScale.niceMax(samples.map(\.value).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            Chart(samples) { sample in
                AreaMark(
                    x: .value("Time", sample.id),
                    y: .value(title, sample.value)
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
                    x: .value("Time", sample.id),
                    y: .value(title, sample.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .chartXAxis(.hidden)
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
