import Charts
import SwiftUI

/// One titled chart on a Liquid Glass material card: header with the current
/// value (and optional subtitle), a smoothed line over history with a soft
/// gradient fill, time-based X axis covering the selected window, real gaps
/// where measurements are missing, and a hover/drag lollipop showing the
/// exact value and timestamp.
struct ChartCard: View {
    let title: String
    let valueText: String
    var subtitle: String?
    let segments: [ChartSegment]
    let xDomain: ClosedRange<Date>
    let tint: Color
    let axisLabel: (Double) -> String

    @State private var hoverSample: Sample?

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

            chart
                .frame(height: 76)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var chart: some View {
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

            if let hover = hoverSample {
                RuleMark(x: .value("Time", hover.time))
                    .foregroundStyle(.tertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top,
                        spacing: 2,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(axisLabel(hover.value))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                            Text(hover.time.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                PointMark(
                    x: .value("Time", hover.time),
                    y: .value(title, hover.value)
                )
                .foregroundStyle(tint)
                .symbolSize(40)
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
        .onChange(of: xDomain) {
            // The domain scrolls every second; drop the lollipop once its
            // sample leaves the visible window instead of letting it drift.
            if let hover = hoverSample, !xDomain.contains(hover.time) {
                hoverSample = nil
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            updateHover(at: location, proxy: proxy, geo: geo)
                        case .ended:
                            hoverSample = nil
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { updateHover(at: $0.location, proxy: proxy, geo: geo) }
                            .onEnded { _ in hoverSample = nil }
                    )
            }
        }
    }

    private func updateHover(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let anchor = proxy.plotFrame else {
            hoverSample = nil
            return
        }
        let frame = geo[anchor]
        let x = location.x - frame.origin.x
        guard x >= 0, x <= frame.width, let date: Date = proxy.value(atX: x) else {
            hoverSample = nil
            return
        }
        let samples = segments.flatMap(\.samples)
        hoverSample = samples.min {
            abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date))
        }
    }
}
