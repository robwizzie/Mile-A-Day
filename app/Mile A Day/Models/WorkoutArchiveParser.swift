import Foundation
import HealthKit

/// One workout recovered from a platform's own data export, ready to be written
/// into Apple Health.
///
/// Pure value type — parsing never touches HealthKit, the network, or disk
/// state, so the whole format layer can be reasoned about (and the preview
/// rendered) before anything is written anywhere.
struct ImportableWorkout: Identifiable, Hashable {
    /// Stable key, `"<platform>:<activityId>"`. This is what makes re-importing
    /// the same archive a no-op, so it must be derived from the export and never
    /// from anything generated at import time.
    let id: String
    let name: String
    let activityType: ImportedActivityType
    let start: Date
    let end: Date
    let miles: Double
    /// Only present when the export distinguishes moving from elapsed time.
    let movingSeconds: Double?
    /// `[(latitude, longitude)]`, when the archive carried a GPS trace.
    let route: [ImportedRoutePoint]

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct ImportedRoutePoint: Hashable {
    let latitude: Double
    let longitude: Double
}

enum ImportedActivityType: String, Hashable {
    case running, walking, hiking

    var hkActivityType: HKWorkoutActivityType {
        switch self {
        case .running: return .running
        case .walking: return .walking
        case .hiking: return .hiking
        }
    }

    /// Maps a platform's own type string. Only the types Mile A Day actually
    /// counts survive; everything else (rides, swims, strength) is reported as
    /// skipped rather than silently converted into miles.
    static func from(_ raw: String) -> ImportedActivityType? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.contains("hike") || t.contains("hiking") { return .hiking }
        if t.contains("walk") { return .walking }
        if t.contains("run") { return .running }
        return nil
    }
}

/// How a distance column should be read. Inferred from the file, overridable by
/// the user — see `DistanceUnit.infer`.
enum DistanceUnit: String, CaseIterable, Identifiable {
    case meters, kilometers, miles
    var id: String { rawValue }

    var label: String {
        switch self {
        case .meters: return "Meters"
        case .kilometers: return "Kilometers"
        case .miles: return "Miles"
        }
    }

    func toMiles(_ value: Double) -> Double {
        switch self {
        case .meters: return value / WorkoutArchiveParser.metersPerMile
        case .kilometers: return (value * 1000) / WorkoutArchiveParser.metersPerMile
        case .miles: return value
        }
    }

    /// Infer from the whole file rather than any single row.
    ///
    /// A run or walk has a median around 3–10 in km or miles and 3000–10000 in
    /// meters, so the median separates those by orders of magnitude and one
    /// weird activity can't skew it.
    ///
    /// Kilometers vs MILES is genuinely not separable this way — the same runs
    /// read 5.0 and 3.1 — which is exactly why the import preview lets the user
    /// override this instead of trusting it.
    static func infer(from values: [Double]) -> DistanceUnit {
        let positive = values.filter { $0 > 0 }.sorted()
        guard !positive.isEmpty else { return .meters }
        let median = positive[positive.count / 2]
        return median > 300 ? .meters : .kilometers
    }
}

struct ArchiveParseResult {
    var workouts: [ImportableWorkout]
    /// Rows that were unusable or not a running/walking/hiking activity. Shown
    /// in the preview so an import that silently dropped half a file is visible.
    var skipped: Int
    var detectedUnit: DistanceUnit
}

/// Parses the data exports users can download from their own fitness platform.
///
/// This exists because **connecting an app is forward-only**: flipping on
/// Strava's or Garmin's Apple Health switch sends workouts from that moment on
/// and never backfills. The only lawful way to recover years of history is the
/// user's own export — no API can do it (Strava's agreement bars the social
/// surfaces; Garmin's program is closed to new signups).
enum WorkoutArchiveParser {
    static let metersPerMile = 1609.344

    // MARK: - Strava activities.csv

    /// The primary import path.
    ///
    /// `activities.csv` lists EVERY activity regardless of whether the file
    /// beside it is GPX, FIT or TCX — so it alone rebuilds a complete history
    /// and streak, including the FIT activities this parser can't otherwise read.
    static func parseStravaCSV(
        _ text: String,
        unitOverride: DistanceUnit? = nil
    ) -> ArchiveParseResult {
        let lines = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else {
            return ArchiveParseResult(workouts: [], skipped: 0, detectedUnit: .meters)
        }

        let header = parseCSVRow(lines[0])
        let columns = headerIndices(header)

        let idIdx = firstIndex(columns, Aliases.id)
        let dateIdx = firstIndex(columns, Aliases.date)
        let nameIdx = firstIndex(columns, Aliases.name)
        let typeIdx = firstIndex(columns, Aliases.type)
        // LAST occurrence, deliberately: Strava repeats `Distance`, `Elapsed
        // Time` and `Moving Time`. The first copy is the summary block, whose
        // units follow the athlete's display preference; the later copy is the
        // raw API block — always meters and seconds.
        let distIdx = lastIndex(columns, Aliases.distance)
        let elapsedIdx = lastIndex(columns, Aliases.elapsed)
        let movingIdx = lastIndex(columns, Aliases.moving)

        struct RawRow {
            let id: String, name: String
            let type: ImportedActivityType
            let start: Date
            let elapsed: Double, moving: Double?
            let rawDistance: Double
        }

        var raw: [RawRow] = []
        var skipped = 0

        for line in lines.dropFirst() {
            let f = parseCSVRow(line)

            // Each row succeeds or fails ALONE. A single malformed line in a
            // 4,000-row archive must never abort someone's whole history.
            guard
                let start = parseCSVDate(field(f, dateIdx)),
                let distance = number(field(f, distIdx)), distance > 0,
                let elapsed = number(field(f, elapsedIdx)), elapsed > 0,
                let type = ImportedActivityType.from(field(f, typeIdx) ?? "")
            else {
                skipped += 1
                continue
            }

            raw.append(
                RawRow(
                    id: (field(f, idIdx) ?? "").trimmingCharacters(in: .whitespaces),
                    name: (field(f, nameIdx) ?? "").trimmingCharacters(in: .whitespaces),
                    type: type,
                    start: start,
                    elapsed: elapsed,
                    moving: number(field(f, movingIdx)),
                    rawDistance: distance
                )
            )
        }

        let unit = unitOverride ?? DistanceUnit.infer(from: raw.map { $0.rawDistance })

        let workouts = raw.map { row in
            ImportableWorkout(
                id: "strava:\(row.id.isEmpty ? ISO8601DateFormatter().string(from: row.start) : row.id)",
                name: row.name,
                activityType: row.type,
                start: row.start,
                end: row.start.addingTimeInterval(row.elapsed),
                miles: unit.toMiles(row.rawDistance),
                movingSeconds: row.moving,
                route: []
            )
        }

        return ArchiveParseResult(workouts: workouts, skipped: skipped, detectedUnit: unit)
    }

    // MARK: - CSV primitives

    /// RFC4180-ish: quoted fields, embedded commas and newlines-as-separators
    /// already handled by the caller, doubled quotes as a literal quote.
    static func parseCSVRow(_ line: String) -> [String] {
        var out: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                out.append(field)
                field = ""
            } else {
                field.append(c)
            }
            i += 1
        }
        out.append(field)
        return out
    }

    private enum Aliases {
        static let id = ["activity id", "id"]
        static let date = ["activity date", "date", "start time"]
        static let name = ["activity name", "name"]
        static let type = ["activity type", "type", "sport"]
        static let elapsed = ["elapsed time", "elapsed time (s)", "total time"]
        static let moving = ["moving time", "moving time (s)"]
        static let distance = ["distance", "distance (m)", "distance (km)"]
    }

    /// Every index a header name appears at, in order. Matching by NAME rather
    /// than position matters: Strava's column set has drifted over the years and
    /// a fixed index silently reads the wrong field on an older or newer export.
    private static func headerIndices(_ header: [String]) -> [String: [Int]] {
        var map: [String: [Int]] = [:]
        for (i, rawName) in header.enumerated() {
            let key = rawName.trimmingCharacters(in: .whitespaces).lowercased()
            map[key, default: []].append(i)
        }
        return map
    }

    private static func firstIndex(_ map: [String: [Int]], _ keys: [String]) -> Int? {
        for k in keys {
            if let hit = map[k]?.first { return hit }
        }
        return nil
    }

    private static func lastIndex(_ map: [String: [Int]], _ keys: [String]) -> Int? {
        for k in keys {
            if let hit = map[k]?.last { return hit }
        }
        return nil
    }

    private static func field(_ row: [String], _ index: Int?) -> String? {
        guard let index, index >= 0, index < row.count else { return nil }
        return row[index]
    }

    private static func number(_ value: String?) -> Double? {
        guard let value else { return nil }
        let cleaned = value
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    // MARK: - Dates

    /// Strava writes `Activity Date` in **UTC with no offset marker**.
    ///
    /// Parsing it in the device's timezone is not a cosmetic error in a streak
    /// app: a 9 PM run read five hours late lands on the following day, moving
    /// which day it satisfies and inventing or breaking a streak. So the
    /// formatters are pinned to UTC, and to `en_US_POSIX` — a fixed format
    /// string against a device locale is the classic way date parsing fails on
    /// someone else's phone.
    private static let csvFormatters: [DateFormatter] = {
        ["MMM d, yyyy, h:mm:ss a", "MMM d, yyyy, HH:mm:ss", "yyyy-MM-dd HH:mm:ss"]
            .map { format in
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(identifier: "UTC")
                f.dateFormat = format
                return f
            }
    }()

    private static let isoFormatters: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [plain, withFraction]
    }()

    static func parseCSVDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        for f in isoFormatters {
            if let d = f.date(from: trimmed) { return d }
        }
        for f in csvFormatters {
            if let d = f.date(from: trimmed) { return d }
        }
        return nil
    }

    static func parseISODate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        for f in isoFormatters {
            if let d = f.date(from: trimmed) { return d }
        }
        return nil
    }

    // MARK: - GPX / TCX

    /// Both are XML and both are per-activity, so each file yields at most one
    /// workout. Their value over the CSV is the GPS trace — that's what puts a
    /// route map on an imported run.
    ///
    /// `activityId` should be the file's stem. In a Strava archive that is the
    /// same number as the CSV's `Activity ID` (`activities/1001.gpx`), so a
    /// user who imports both the CSV and the track files gets ONE workout per
    /// activity rather than two — the import key matches.
    static func parseGPX(_ text: String, activityId: String) -> ImportableWorkout? {
        let doc = XMLTrackParser(mode: .gpx)
        guard doc.parse(text), doc.points.count >= 2,
            let start = doc.times.first, let end = doc.times.last, end > start
        else { return nil }

        return ImportableWorkout(
            id: "strava:\(activityId)",
            name: doc.name,
            activityType: ImportedActivityType.from(doc.activityLabel) ?? .running,
            start: start,
            end: end,
            // GPX carries no total distance, so it comes from the trace itself.
            miles: haversineMiles(doc.points),
            movingSeconds: nil,
            route: doc.points
        )
    }

    static func parseTCX(_ text: String, activityId: String) -> ImportableWorkout? {
        let doc = XMLTrackParser(mode: .tcx)
        guard doc.parse(text), let start = doc.tcxStart ?? doc.times.first else { return nil }

        let seconds = doc.tcxTotalSeconds > 0
            ? doc.tcxTotalSeconds
            : (doc.times.last.map { $0.timeIntervalSince(start) } ?? 0)
        guard seconds > 0 else { return nil }

        // Prefer the device's own distance; fall back to the trace.
        let miles = doc.tcxTotalMeters > 0
            ? doc.tcxTotalMeters / metersPerMile
            : haversineMiles(doc.points)
        guard miles > 0 else { return nil }

        return ImportableWorkout(
            id: "strava:\(activityId)",
            name: doc.name,
            activityType: ImportedActivityType.from(doc.activityLabel) ?? .running,
            start: start,
            end: start.addingTimeInterval(seconds),
            miles: miles,
            movingSeconds: nil,
            route: doc.points
        )
    }

    /// Great-circle length of a trace, in miles. Written out rather than pulled
    /// from CoreLocation so this file stays a pure parser with no framework
    /// state behind it.
    static func haversineMiles(_ points: [ImportedRoutePoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        let earthRadiusMeters = 6_371_000.0
        var meters = 0.0

        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            let lat1 = a.latitude * .pi / 180
            let lat2 = b.latitude * .pi / 180
            let dLat = (b.latitude - a.latitude) * .pi / 180
            let dLon = (b.longitude - a.longitude) * .pi / 180
            let h =
                sin(dLat / 2) * sin(dLat / 2)
                + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
            meters += 2 * earthRadiusMeters * atan2(sqrt(h), sqrt(1 - h))
        }
        return meters / metersPerMile
    }
}

/// One `XMLParser` delegate covering both GPX and TCX — they differ only in
/// element names, and a shared walker keeps the two extraction rules beside
/// each other where they can't drift.
private final class XMLTrackParser: NSObject, XMLParserDelegate {
    enum Mode { case gpx, tcx }

    private let mode: Mode
    init(mode: Mode) { self.mode = mode }

    private(set) var points: [ImportedRoutePoint] = []
    private(set) var times: [Date] = []
    private(set) var name = ""
    private(set) var activityLabel = ""
    private(set) var tcxTotalMeters: Double = 0
    private(set) var tcxTotalSeconds: TimeInterval = 0
    private(set) var tcxStart: Date?

    private var text = ""
    private var inTrackPoint = false
    private var pendingLat: Double?
    private var pendingLon: Double?
    /// GPX puts a `<time>` in `<metadata>` too — only the ones inside a
    /// trackpoint describe the activity, so the metadata stamp is ignored.
    private var inMetadata = false

    func parse(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String,
        namespaceURI: String?, qualifiedName: String?,
        attributes attributeDict: [String: String]
    ) {
        text = ""
        switch elementName {
        case "metadata":
            inMetadata = true
        case "trkpt":
            inTrackPoint = true
            pendingLat = Double(attributeDict["lat"] ?? "")
            pendingLon = Double(attributeDict["lon"] ?? "")
        case "Trackpoint":
            inTrackPoint = true
            pendingLat = nil
            pendingLon = nil
        case "Activity":
            if activityLabel.isEmpty { activityLabel = attributeDict["Sport"] ?? "" }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String,
        namespaceURI: String?, qualifiedName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "metadata":
            inMetadata = false
        case "name", "Name":
            if name.isEmpty { name = value }
        case "type":
            if activityLabel.isEmpty { activityLabel = value }
        case "time", "Time":
            if inTrackPoint || (mode == .tcx && !value.isEmpty) {
                if let d = WorkoutArchiveParser.parseISODate(value), !inMetadata {
                    times.append(d)
                }
            }
        case "LatitudeDegrees":
            pendingLat = Double(value)
        case "LongitudeDegrees":
            pendingLon = Double(value)
        case "DistanceMeters":
            // Lap totals accumulate; trackpoint-level values are cumulative
            // per lap and would double-count, so only laps contribute.
            if !inTrackPoint, let d = Double(value) { tcxTotalMeters += d }
        case "TotalTimeSeconds":
            if let d = Double(value) { tcxTotalSeconds += d }
        case "Id":
            if tcxStart == nil { tcxStart = WorkoutArchiveParser.parseISODate(value) }
        case "trkpt", "Trackpoint":
            if let lat = pendingLat, let lon = pendingLon {
                points.append(ImportedRoutePoint(latitude: lat, longitude: lon))
            }
            inTrackPoint = false
            pendingLat = nil
            pendingLon = nil
        default:
            break
        }
        text = ""
    }
}
