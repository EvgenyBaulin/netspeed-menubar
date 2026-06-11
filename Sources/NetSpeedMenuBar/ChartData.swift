import Foundation

/// A run of consecutive samples with no measurement gaps. Failed samples are
/// simply absent from history; a time gap larger than ~3 sampling intervals
/// splits the line so outages render as real gaps, not bridged segments.
struct ChartSegment: Identifiable, Sendable {
    let id: Int
    let samples: [Sample]
}

enum ChartData {
    /// Filters history to the visible time window, splits it into gap-free
    /// segments, and downsamples long windows (bucket means) so charts stay
    /// smooth at one hour of 1-second samples.
    static func prepare(
        _ history: [Sample],
        window: TimeInterval,
        now: Date,
        expectedInterval: TimeInterval,
        maxPoints: Int = 240
    ) -> [ChartSegment] {
        let cutoff = now.addingTimeInterval(-window)
        guard let start = history.firstIndex(where: { $0.time >= cutoff }) else { return [] }
        let recent = history[start...]

        var runs: [[Sample]] = []
        var current: [Sample] = []
        for sample in recent {
            if let last = current.last,
               sample.time.timeIntervalSince(last.time) > expectedInterval * 3 {
                runs.append(current)
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty { runs.append(current) }

        let total = recent.count
        if total > maxPoints {
            let bucket = Int((Double(total) / Double(maxPoints)).rounded(.up))
            runs = runs.map { downsample($0, bucket: bucket) }
        }
        return runs.enumerated().map { ChartSegment(id: $0.offset, samples: $0.element) }
    }

    private static func downsample(_ samples: [Sample], bucket: Int) -> [Sample] {
        guard bucket > 1, samples.count > bucket else { return samples }
        var out: [Sample] = []
        out.reserveCapacity(samples.count / bucket + 1)
        var index = 0
        while index < samples.count {
            let chunk = samples[index ..< min(index + bucket, samples.count)]
            let mean = chunk.reduce(0) { $0 + $1.value } / Double(chunk.count)
            let mid = chunk[chunk.startIndex + chunk.count / 2]
            out.append(Sample(id: mid.id, time: mid.time, value: mean))
            index += bucket
        }
        return out
    }
}
