import Foundation

/// Active channel-capacity measurement (a speed test). The passive monitor in
/// the menu bar shows actual current traffic; available bandwidth can only be
/// measured by loading the connection, which is what this does — on demand or
/// on a configurable interval. Uses Cloudflare's public speed-test endpoints
/// over plain URLSession; each run transfers tens of megabytes.
@MainActor
final class SpeedTester: ObservableObject {
    struct Result: Codable, Sendable {
        let date: Date
        let downloadMbps: Double?
        let uploadMbps: Double?
        let pingMs: Double?
    }

    @Published private(set) var isRunning = false
    @Published private(set) var lastResult: Result?
    @Published private(set) var lastFailed = false

    weak var monitor: NetMonitor?

    private let defaults = UserDefaults.standard
    private let storageKey = "speedTest.lastResult"
    private var autoTimer: Timer?

    init() {
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(Result.self, from: data) {
            lastResult = stored
        }
    }

    func applyAutoInterval(_ interval: SpeedTestInterval) {
        autoTimer?.invalidate()
        autoTimer = nil
        guard interval != .off else { return }
        let timer = Timer(timeInterval: TimeInterval(interval.rawValue * 60), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.run() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoTimer = timer
    }

    func stopAuto() {
        autoTimer?.invalidate()
        autoTimer = nil
    }

    func run() {
        guard !isRunning else { return }
        isRunning = true
        lastFailed = false
        // Capture latency before the probes saturate the link — under load it
        // would measure bufferbloat, not the idle ping.
        let idlePing = monitor?.ping
        Task { [weak self] in
            let download = await SpeedProbe.download(cap: 8)
            let upload = await SpeedProbe.upload(cap: 8)
            guard let self else { return }
            self.isRunning = false
            guard download != nil || upload != nil else {
                self.lastFailed = true
                return
            }
            let result = Result(
                date: Date(),
                downloadMbps: download,
                uploadMbps: upload,
                pingMs: idlePing
            )
            self.lastResult = result
            if let data = try? JSONEncoder().encode(result) {
                self.defaults.set(data, forKey: self.storageKey)
            }
        }
    }
}

enum SpeedProbe {
    // Public Cloudflare speed-test endpoints (the same ones speed.cloudflare.com uses).
    private static let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=1000000000")!
    private static let uploadURL = URL(string: "https://speed.cloudflare.com/__up")!
    private static let uploadPayloadSize = 200_000_000 // the cap, not the payload, ends the probe

    struct Measurement: Sendable {
        let bytes: Int64
        let seconds: Double
    }

    /// Measures download throughput in Mbit/s with a delegate-counted data
    /// task (byte-wise AsyncBytes iteration is CPU-bound and would cap the
    /// instrument itself at roughly 100–150 MB/s). Timing starts at the first
    /// received chunk so connection setup doesn't dilute the result; the
    /// delegate cancels the task once `cap` seconds of data have been timed.
    static func download(cap: TimeInterval) async -> Double? {
        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 15 // idle timeout; wall clock is bounded below
        let delegate = DownloadProbeDelegate(cap: cap)
        let task = URLSession.shared.dataTask(with: request)
        task.delegate = delegate

        // Hard bound even if no data ever arrives (the delegate's own cap
        // check only runs when chunks are delivered).
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(cap + 5))
            task.cancel()
        }
        defer { watchdog.cancel() }

        let measurement = await delegate.measure(with: task)
        guard let measurement, measurement.seconds > 0.3, measurement.bytes >= 65_536 else {
            return nil
        }
        return Double(measurement.bytes) * 8 / measurement.seconds / 1_000_000
    }

    /// Measures upload throughput in Mbit/s from the slope of
    /// `didSendBodyData` progress between an anchor placed after the initial
    /// socket-buffer burst and the last callback — this excludes connection
    /// setup, the post-upload response wait, and most of the buffer-fill
    /// distortion. The payload is large enough that the time cap, not the
    /// payload size, normally ends the test.
    static func upload(cap: TimeInterval) async -> Double? {
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        uploadRequest.timeoutInterval = cap + 10
        let request = uploadRequest
        let payload = Data(count: uploadPayloadSize)
        let delegate = UploadProbeDelegate()

        enum Outcome: Sendable {
            case finished(Measurement?)
            case timeout
        }

        let measurement: Measurement? = await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                // Cancellation at the cap is the normal way the test ends;
                // the measurement lives in the delegate either way.
                _ = try? await URLSession.shared.upload(for: request, from: payload, delegate: delegate)
                return .finished(delegate.measurement)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(cap))
                return .timeout
            }

            var result: Measurement?
            for await outcome in group {
                switch outcome {
                case .finished(let value):
                    result = value
                    group.cancelAll()
                    return result
                case .timeout:
                    group.cancelAll() // cancels the upload; it then reports
                }
            }
            return result
        }

        guard let measurement, measurement.seconds > 1, measurement.bytes > 262_144 else {
            return nil
        }
        return Double(measurement.bytes) * 8 / measurement.seconds / 1_000_000
    }
}

/// Counts received chunk sizes and cancels the task once `cap` seconds have
/// elapsed since the first chunk. Resumes the awaiting continuation from
/// `didCompleteWithError` (cancellation at the cap counts as success).
private final class DownloadProbeDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let clock = ContinuousClock()
    private let cap: TimeInterval
    private var firstChunkAt: ContinuousClock.Instant?
    private var bytes: Int64 = 0
    private var continuation: CheckedContinuation<SpeedProbe.Measurement?, Never>?

    init(cap: TimeInterval) {
        self.cap = cap
    }

    func measure(with task: URLSessionDataTask) async -> SpeedProbe.Measurement? {
        await withCheckedContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let ok = (response as? HTTPURLResponse)?.statusCode == 200
        completionHandler(ok ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let elapsed: Double = lock.withLock {
            if firstChunkAt == nil { firstChunkAt = clock.now }
            bytes += Int64(data.count)
            return Self.seconds(of: clock.now - firstChunkAt!)
        }
        if elapsed >= cap {
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (resumer, measurement): (CheckedContinuation<SpeedProbe.Measurement?, Never>?, SpeedProbe.Measurement?) = lock.withLock {
            let resumer = continuation
            continuation = nil
            guard let firstChunkAt else { return (resumer, nil) }
            return (resumer, SpeedProbe.Measurement(
                bytes: bytes,
                seconds: Self.seconds(of: clock.now - firstChunkAt)
            ))
        }
        resumer?.resume(returning: measurement)
    }

    static func seconds(of duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

/// Records upload progress and exposes the throughput window between an
/// anchor (third progress callback, past the initial socket-buffer burst)
/// and the most recent callback.
private final class UploadProbeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let clock = ContinuousClock()
    private var callbackCount = 0
    private var anchorAt: ContinuousClock.Instant?
    private var anchorBytes: Int64 = 0
    private var lastAt: ContinuousClock.Instant?
    private var lastBytes: Int64 = 0

    var measurement: SpeedProbe.Measurement? {
        lock.withLock {
            guard let anchorAt, let lastAt, lastBytes > anchorBytes else { return nil }
            return SpeedProbe.Measurement(
                bytes: lastBytes - anchorBytes,
                seconds: DownloadProbeDelegate.seconds(of: lastAt - anchorAt)
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        lock.withLock {
            callbackCount += 1
            let now = clock.now
            if anchorAt == nil, callbackCount >= 3 {
                anchorAt = now
                anchorBytes = totalBytesSent
            }
            lastAt = now
            lastBytes = totalBytesSent
        }
    }
}
