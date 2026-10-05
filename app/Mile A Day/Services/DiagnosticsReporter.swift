import Foundation
import MetricKit
import UIKit

/// Crash / hang reporting through MetricKit — the app ships no third-party
/// crash SDK, so this is the only witness to a crash in the field.
///
/// iOS hands us an `MXDiagnosticPayload` on the launch AFTER the crash (up to
/// a day later) and an `MXMetricPayload` about once a day. Both are trimmed
/// here, appended to a small queue file in Caches, and uploaded to
/// `POST /diagnostics/metrickit` fire-and-forget. The queue is what makes it
/// retry-safe: nothing is dropped until the server has answered 2xx (or
/// refused the batch as malformed), and every item carries its own `id` so a
/// retry after a lost response is stored once. Items older than
/// `maxAge` or retried `maxAttempts` times are discarded, so a server that
/// never accepts them can't grow the file forever.
///
/// Contents are only what MetricKit itself reports — exception codes, the
/// call-stack tree (binary names + offsets), app/OS version, device model.
/// No location, no health data, no user content.
///
/// Nothing user-facing may depend on any of this: every failure is silent.
///
/// `@unchecked Sendable`: all mutable state (`isFlushing`, `lastFlushAt`, the
/// queue file) is touched only on the serial `io` queue; `started` only from
/// `start()` on the main thread at launch.
final class DiagnosticsReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = DiagnosticsReporter()

    // Server caps (diagnosticsService.ts): 25 items / request, 64KB / item,
    // 2MB / body. Stay well under all three.
    private static let batchSize = 20
    private static let maxItemBytes = 60 * 1024
    private static let maxBatchBytes = 1_200_000
    private static let maxQueued = 40
    private static let maxAge: TimeInterval = 14 * 24 * 3600
    private static let maxAttempts = 8
    private static let minFlushInterval: TimeInterval = 10 * 60
    private static let maxStackDepth = 64
    private static let maxSiblings = 3

    /// Serialises every read/write of the queue file and the flush flag.
    private let io = DispatchQueue(label: "run.mileaday.diagnostics", qos: .utility)
    private var isFlushing = false
    private var lastFlushAt: Date?
    private var started = false

    private override init() { super.init() }

    /// Called once from `AppDelegate.didFinishLaunching`. Cheap: registering
    /// the subscriber is synchronous and the flush is deferred off-main.
    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        // Give launch its moment first — the upload is never urgent.
        io.asyncAfter(deadline: .now() + 20) { [weak self] in self?.flushLocked(force: true) }
    }

    @objc private func appWillEnterForeground() {
        io.async { [weak self] in self?.flushLocked(force: false) }
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let items = payloads.flatMap(Self.items(from:))
        enqueue(items)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        let items = payloads.compactMap(Self.item(fromMetrics:))
        enqueue(items)
    }

    // MARK: - Building items

    private static let diagnosticKinds: [(key: String, kind: String)] = [
        ("crashDiagnostics", "crash"),
        ("hangDiagnostics", "hang"),
        ("cpuExceptionDiagnostics", "cpu_exception"),
        ("diskWriteExceptionDiagnostics", "disk_write_exception"),
    ]

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func items(from payload: MXDiagnosticPayload) -> [[String: Any]] {
        guard let root = try? JSONSerialization.jsonObject(with: payload.jsonRepresentation()) as? [String: Any] else {
            return []
        }
        let occurred = isoFormatter.string(from: payload.timeStampEnd)
        var out: [[String: Any]] = []
        for (key, kind) in diagnosticKinds {
            guard let list = root[key] as? [[String: Any]] else { continue }
            for diagnostic in list {
                guard let trimmed = trimDiagnostic(diagnostic) else { continue }
                out.append(newItem(kind: kind, occurredAt: occurred, diagnostic: trimmed))
            }
        }
        return out
    }

    /// The daily summary: hang-time and launch histograms, scroll hitch
    /// ratio, and exit counts (how often the app was killed, and why).
    private static func item(fromMetrics payload: MXMetricPayload) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: payload.jsonRepresentation()) as? [String: Any] else {
            return nil
        }
        let keep = [
            "timeStampBegin", "timeStampEnd", "appVersion", "metaData",
            "applicationResponsivenessMetrics", "animationMetrics",
            "applicationExitMetrics", "applicationLaunchMetrics",
        ]
        var summary = root.filter { keep.contains($0.key) }
        if byteCount(summary) > maxItemBytes {
            // Launch histograms are the bulky part; the rest is a few numbers.
            summary.removeValue(forKey: "applicationLaunchMetrics")
        }
        guard !summary.isEmpty, byteCount(summary) <= maxItemBytes else { return nil }
        return newItem(
            kind: "metrics",
            occurredAt: isoFormatter.string(from: payload.timeStampEnd),
            diagnostic: summary
        )
    }

    private static func newItem(kind: String, occurredAt: String, diagnostic: [String: Any]) -> [String: Any] {
        [
            "id": UUID().uuidString,
            "kind": kind,
            "occurred_at": occurredAt,
            "diagnostic": diagnostic,
            "queued_at": Date().timeIntervalSince1970,
            "attempts": 0,
        ]
    }

    /// Mirrors the server's trim (which runs again regardless): metadata plus
    /// the ATTRIBUTED thread's stack only, depth- and sibling-capped. A crash
    /// tree carries every thread and is most of a payload's size.
    private static func trimDiagnostic(_ raw: [String: Any]) -> [String: Any]? {
        var out: [String: Any] = [:]
        if let meta = raw["diagnosticMetaData"] as? [String: Any] {
            var m = meta
            m.removeValue(forKey: "regionFormat")
            out["diagnosticMetaData"] = m
        }
        for (depth, siblings) in [(maxStackDepth, maxSiblings), (24, 1)] {
            var candidate = out
            if let tree = raw["callStackTree"] as? [String: Any] {
                candidate["callStackTree"] = trimTree(tree, depth: depth, siblings: siblings)
            }
            if byteCount(candidate) <= maxItemBytes { return candidate }
        }
        out["truncated"] = true
        return byteCount(out) <= maxItemBytes ? out : nil
    }

    private static func trimTree(_ tree: [String: Any], depth: Int, siblings: Int) -> [String: Any] {
        let stacks = (tree["callStacks"] as? [[String: Any]]) ?? []
        let attributed = stacks.filter { ($0["threadAttributed"] as? Bool) == true }
        let chosen = Array((attributed.isEmpty ? stacks : attributed).prefix(2))
        return [
            "callStackPerThread": (tree["callStackPerThread"] as? Bool) ?? false,
            "callStacks": chosen.map { stack -> [String: Any] in
                [
                    "threadAttributed": (stack["threadAttributed"] as? Bool) ?? false,
                    "callStackRootFrames": trimFrames(stack["callStackRootFrames"], depth: depth, siblings: siblings),
                ]
            },
        ]
    }

    private static func trimFrames(_ value: Any?, depth: Int, siblings: Int) -> [[String: Any]] {
        guard depth > 0, let frames = value as? [[String: Any]] else { return [] }
        let sorted = frames.sorted {
            (($0["sampleCount"] as? NSNumber)?.intValue ?? 0) > (($1["sampleCount"] as? NSNumber)?.intValue ?? 0)
        }
        return sorted.prefix(siblings).map { frame in
            var f: [String: Any] = [:]
            for key in ["binaryName", "binaryUUID", "offsetIntoBinaryTextSegment", "address", "sampleCount"] {
                if let v = frame[key] { f[key] = v }
            }
            let sub = trimFrames(frame["subFrames"], depth: depth - 1, siblings: siblings)
            if !sub.isEmpty { f["subFrames"] = sub }
            return f
        }
    }

    private static func byteCount(_ object: Any) -> Int {
        (try? JSONSerialization.data(withJSONObject: object).count) ?? Int.max
    }

    // MARK: - Queue

    private static var queueURL: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return caches.appendingPathComponent("MADDiagnostics", isDirectory: true)
            .appendingPathComponent("queue.json")
    }

    private func enqueue(_ items: [[String: Any]]) {
        guard !items.isEmpty else { return }
        io.async { [weak self] in
            guard let self else { return }
            var queue = self.loadQueue()
            queue.append(contentsOf: items)
            self.saveQueue(queue)
            // New payloads skip the throttle: they are what we're here for.
            self.flushLocked(force: true)
        }
    }

    /// Must run on `io`.
    private func loadQueue() -> [[String: Any]] {
        guard let url = Self.queueURL,
              let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return list
    }

    /// Must run on `io`. Drops expired / exhausted items and keeps the newest
    /// `maxQueued`, so the file stays small whatever happens upstream.
    private func saveQueue(_ queue: [[String: Any]]) {
        guard let url = Self.queueURL else { return }
        let now = Date().timeIntervalSince1970
        let live = queue.filter { item in
            let queuedAt = (item["queued_at"] as? NSNumber)?.doubleValue ?? 0
            let attempts = (item["attempts"] as? NSNumber)?.intValue ?? 0
            return now - queuedAt < Self.maxAge && attempts < Self.maxAttempts
        }
        let kept = Array(live.suffix(Self.maxQueued))
        do {
            if kept.isEmpty {
                try? FileManager.default.removeItem(at: url)
                return
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: kept)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[Diagnostics] could not persist queue: \(error.localizedDescription)")
        }
    }

    // MARK: - Upload

    private struct UploadResult: Decodable {
        let stored: Int?
        let duplicates: Int?
        let capped: Int?
        let rejected: Int?
    }

    private static var envelope: [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return [
            "app_version": info["CFBundleShortVersionString"] as? String ?? "",
            "build": info["CFBundleVersion"] as? String ?? "",
            "os_version": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "device_model": model,
        ]
    }

    /// Must run on `io`. Sends one batch; on success, chains to the next.
    private func flushLocked(force: Bool) {
        guard !isFlushing else { return }
        if !force, let last = lastFlushAt, Date().timeIntervalSince(last) < Self.minFlushInterval { return }
        // Never call APIClient without tokens: its no-token path signs the
        // user out, which is not a price a crash report gets to charge.
        guard TokenStore.hasTokens else { return }

        let queue = loadQueue()
        guard !queue.isEmpty else { return }

        var batch: [[String: Any]] = []
        var bytes = 0
        for item in queue {
            guard batch.count < Self.batchSize else { break }
            let wire = item.filter { ["id", "kind", "occurred_at", "diagnostic"].contains($0.key) }
            let size = Self.byteCount(wire)
            if !batch.isEmpty && bytes + size > Self.maxBatchBytes { break }
            batch.append(wire)
            bytes += size
        }
        var body = Self.envelope
        body["items"] = batch
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        let sentIds = Set(batch.compactMap { $0["id"] as? String })

        isFlushing = true
        lastFlushAt = Date()
        Task.detached(priority: .utility) { [weak self] in
            var settled = false
            do {
                _ = try await APIClient.fancyFetch(
                    endpoint: "/diagnostics/metrickit",
                    method: .POST,
                    body: data,
                    responseType: UploadResult.self
                )
                settled = true
            } catch APIError.badRequest {
                // The server will refuse this batch every time; retrying
                // only spends the user's data.
                settled = true
            } catch {
                print("[Diagnostics] upload deferred: \(error.localizedDescription)")
            }
            self?.io.async {
                guard let self else { return }
                self.isFlushing = false
                var queue = self.loadQueue()
                if settled {
                    queue.removeAll { sentIds.contains(($0["id"] as? String) ?? "") }
                } else {
                    queue = queue.map { item in
                        guard sentIds.contains((item["id"] as? String) ?? "") else { return item }
                        var bumped = item
                        bumped["attempts"] = ((item["attempts"] as? NSNumber)?.intValue ?? 0) + 1
                        return bumped
                    }
                }
                self.saveQueue(queue)
                if settled, !queue.isEmpty { self.flushLocked(force: true) }
            }
        }
    }
}
