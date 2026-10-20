import SwiftUI
import CoreLocation
import UIKit

// MARK: - Post stickers
//
// Everything a poster can put ON their photo. The original run-stats sticker
// (`RunStatsStickerView`) is one kind; Flamey, the route trace and the
// single-number stickers are the others. They are all baked into the
// uploaded picture by the same `PostCanvas` the editor draws, so nothing here
// may depend on a view lifecycle (ImageRenderer drives none): fixed sizes,
// no AsyncImage, every figure `still: true`.

/// One of Flamey's stickers: a still mood, an arm pose, and a tag.
///
/// Drawn twice over: in the user's OWN look (`.flamey`, the Flamey they
/// dressed in the Closet, whatever the dashboard style) and as the basic,
/// undressed Flamey (`.basicFlamey`), the sticker-pack version everybody
/// knows. Both are the real figure (`FlameyDressedFigure`), never art.
///
/// Raw values are persisted (`StickerMemory`): add cases, never rename.
enum FlameySticker: String, CaseIterable, Identifiable {
    case mileDone, onFire, highFive, letsGo, tooEasy, noDaysOff, closeCall, riseAndRun, fiveMore, justFlamey
    var id: String { rawValue }

    /// The picker tile's label.
    var title: String {
        switch self {
        case .mileDone: return "Mile done"
        case .onFire: return "On fire"
        case .highFive: return "High five"
        case .letsGo: return "Let's go"
        case .tooEasy: return "Too easy"
        case .noDaysOff: return "No days off"
        case .closeCall: return "Close call"
        case .riseAndRun: return "Rise & run"
        case .fiveMore: return "5 more min"
        case .justFlamey: return "Just him"
        }
    }

    /// Only moods whose still frame reads well — shades, the party hat, the
    /// sweat drop, the nightcap. Never his speech bubble: a bubble baked into
    /// a picture reads as a caption nobody wrote.
    var mood: FlameMood.Kind? {
        switch self {
        case .mileDone, .highFive, .tooEasy: return .done
        case .onFire: return .party
        case .letsGo: return .halfway
        case .noDaysOff: return .going
        case .closeCall: return .nervous
        case .riseAndRun: return .sleepy
        case .fiveMore: return .bedtime
        case .justFlamey: return nil
        }
    }

    /// How he holds his arms; nil = the mood's own pose.
    var arms: FlameArmPose? {
        switch self {
        case .highFive, .noDaysOff: return .highFive
        case .letsGo, .tooEasy: return .cheer
        case .fiveMore: return .tucked
        default: return nil
        }
    }

    func tag(streak: Int?) -> String? {
        switch self {
        case .mileDone: return "MILE DONE"
        case .onFire:
            if let streak, streak > 0 { return "DAY \(streak)" }
            return "ON FIRE"
        case .highFive: return "UP TOP!"
        case .letsGo: return "LET'S GO!"
        case .tooEasy: return "TOO EASY"
        case .noDaysOff: return "NO DAYS OFF"
        case .closeCall: return "THAT WAS CLOSE"
        case .riseAndRun: return "RISE & RUN"
        case .fiveMore: return "5 MORE MINUTES"
        case .justFlamey: return nil
        }
    }

    /// Words the picker's search matches besides the title.
    var keywords: String {
        "flamey flame mascot \(title) \(tag(streak: nil) ?? "")".lowercased()
    }
}

/// Text stickers: a word or two on a pill, the Instagram "badge" kind.
/// Raw values are persisted (`StickerMemory`): add cases, never rename.
enum FunBadge: String, CaseIterable, Identifiable {
    case dayCount, clock, buddies, noDaysOff, rainOrShine, touchedGrass, streakMode, mileADay
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dayCount: return "Day count"
        case .clock: return "Time of day"
        case .buddies: return "Crew"
        case .noDaysOff: return "No days off"
        case .rainOrShine: return "Rain or shine"
        case .touchedGrass: return "Touched grass"
        case .streakMode: return "Streak mode"
        case .mileADay: return "Mile a Day"
        }
    }

    var icon: String {
        switch self {
        case .dayCount, .streakMode: return "flame.fill"
        case .clock: return "clock.fill"
        case .buddies: return "person.2.fill"
        case .noDaysOff: return "bolt.fill"
        case .rainOrShine: return "cloud.sun.rain.fill"
        case .touchedGrass: return "leaf.fill"
        case .mileADay: return "figure.walk"
        }
    }

    /// The words on the pill. `captured` is what was frozen when the sticker
    /// was added (the time, the crew, the day number), so a bake a minute
    /// later can't print something different from what was on screen.
    func text(captured: String?) -> String {
        if let captured, !captured.isEmpty { return captured }
        switch self {
        case .dayCount: return "DAY ONE"
        case .clock: return "MILE O'CLOCK"
        case .buddies: return "BUDDY WALK"
        case .noDaysOff: return "NO DAYS OFF"
        case .rainOrShine: return "RAIN OR SHINE"
        case .touchedGrass: return "TOUCHED GRASS ✓"
        case .streakMode: return "STREAK MODE"
        case .mileADay: return "MILE A DAY"
        }
    }

    var keywords: String { "text badge \(title) \(text(captured: nil))".lowercased() }
}

/// How the route sticker draws the walk's trace.
/// Raw values are persisted (`StickerMemory`): add cases, never rename.
enum RouteStickerStyle: String, CaseIterable, Identifiable {
    case line, glow, markers, flamey, card
    case stats, gradient, bold, trail, badge
    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: return "Line"
        case .glow: return "Glow"
        case .markers: return DistanceUnits.current == .miles ? "Miles" : "Km"
        case .flamey: return "Flamey"
        case .card: return "Card"
        case .stats: return "Stats"
        case .gradient: return "Sunset"
        case .bold: return "Bold"
        case .trail: return "Trail"
        case .badge: return "Badge"
        }
    }
}

extension CaseIterable where Self: Equatable {
    /// The next case, wrapping — what a tap-to-cycle steps through.
    var cycled: Self {
        let all = Array(Self.allCases)
        guard let i = all.firstIndex(of: self) else { return self }
        return all[(i + 1) % all.count]
    }
}

/// What a sticker IS. Most kinds can be added as often as you like, the way
/// Instagram's can; `isSingleton` kinds (the stats card, the route, each
/// number) hold one per photo, and adding one again restyles the one there.
enum PostStickerKind: Hashable {
    /// The run-stats sticker, styled by the composer's `StickerConfig`.
    case stats
    /// Flamey in the user's own Closet look.
    case flamey(FlameySticker)
    /// The basic, undressed Flamey: the sticker-pack set.
    case basicFlamey(FlameySticker)
    case route(RouteStickerStyle)
    /// One big number, Strava-style: "3.12 mi", "28:41", "42 day streak".
    case number(RunStatKind)
    case badge(FunBadge)
    /// The poster's own words (`PlacedSticker.text`), Instagram's "Aa".
    case text(TextStickerStyle)
    /// One emoji, big.
    case emoji(String)
    /// One of the drawn Flamey sticker-pack images (`FlameyPackSticker`).
    case pack(FlameyPackSticker)

    enum Slot: Hashable {
        case stats, flamey, basicFlamey, route, badge, text, emoji, pack
        case number(RunStatKind)
    }

    var slot: Slot {
        switch self {
        case .stats: return .stats
        case .flamey: return .flamey
        case .basicFlamey: return .basicFlamey
        case .route: return .route
        case .number(let kind): return .number(kind)
        case .badge: return .badge
        case .text: return .text
        case .emoji: return .emoji
        case .pack: return .pack
        }
    }

    /// One per photo: adding it again restyles the one already there.
    var isSingleton: Bool {
        switch self {
        case .stats, .route, .number: return true
        case .flamey, .basicFlamey, .badge, .text, .emoji, .pack: return false
        }
    }

    /// Where a freshly added sticker lands (normalized canvas centre). Kept
    /// clear of the stats sticker's default spot near the bottom and of the
    /// FRONT & BACK inset (top-trailing by default), and re-clamped by the
    /// editor once the sticker's real size is known.
    var defaultPosition: CGPoint {
        switch self {
        case .stats: return CGPoint(x: 0.5, y: 0.82)
        case .flamey, .basicFlamey: return CGPoint(x: 0.74, y: 0.58)
        case .route: return CGPoint(x: 0.36, y: 0.46)
        case .number: return CGPoint(x: 0.34, y: 0.2)
        case .badge, .text: return CGPoint(x: 0.5, y: 0.5)
        case .emoji: return CGPoint(x: 0.7, y: 0.3)
        case .pack: return CGPoint(x: 0.72, y: 0.6)
        }
    }

    var accessibilityName: String {
        switch self {
        case .stats: return "Stats sticker"
        case .flamey(let f): return "Your Flamey sticker, \(f.title)"
        case .basicFlamey(let f): return "Flamey sticker, \(f.title)"
        case .route(let s): return "Route sticker, \(s.title)"
        case .number(let k): return "\(k.label) sticker"
        case .badge(let b): return "\(b.title) sticker"
        case .text: return "Text sticker"
        case .emoji(let e): return "\(e) sticker"
        case .pack(let p): return "Flamey sticker, \(p.title)"
        }
    }
}

/// A sticker on the photo, with its transform. Normalized centre, pinch
/// scale and twist — the same three numbers the stats sticker always had.
struct PlacedSticker: Identifiable, Equatable {
    let id = UUID()
    var kind: PostStickerKind
    var pos: CGPoint
    var scale: CGFloat = 1
    var rotation: Angle = .zero
    /// This sticker's own colour; nil = the composer's default
    /// (`StickerConfig.accent`).
    var accent: StickerAccent? = nil
    /// Which look a tap has cycled a badge to.
    var variant: Int = 0
    /// Words frozen when it was added (a badge's time, crew, day number).
    var text: String? = nil
    /// A text sticker's line width (`TextPostSticker.width`); nil = default.
    var textWidth: CGFloat? = nil

    init(kind: PostStickerKind, pos: CGPoint? = nil, scale: CGFloat = 1, rotation: Angle = .zero,
         accent: StickerAccent? = nil, variant: Int = 0, text: String? = nil, textWidth: CGFloat? = nil) {
        self.kind = kind
        self.pos = pos ?? kind.defaultPosition
        self.scale = scale
        self.rotation = rotation
        self.accent = accent
        self.variant = variant
        self.text = text
        self.textWidth = textWidth
    }

    /// The same sticker under a new identity — used when one view's stickers
    /// are copied onto the other, so the two layers never share view ids.
    func duplicated() -> PlacedSticker {
        PlacedSticker(kind: kind, pos: pos, scale: scale, rotation: rotation,
                      accent: accent, variant: variant, text: text, textWidth: textWidth)
    }
}

/// Everything a sticker needs to draw itself. Equatable so the editor's
/// `.equatable()` wrapper can skip re-rendering the art on every gesture frame.
struct StickerRenderContext: Equatable {
    let input: RunStatsInput
    let config: StickerConfig
    let route: RouteStickerTrace?
}

// MARK: - Route trace

/// The walk's trace, already projected into the sticker's own frame.
///
/// Built ONCE from the walk's coordinates (`make`), so the editor
/// never re-projects thousands of GPS samples per frame, and compared by key +
/// count so equality is O(1).
struct RouteStickerTrace: Equatable {
    let key: String
    let points: [CGPoint]
    let size: CGSize
    /// One dot per whole display unit (mile or km) along the shown line,
    /// measured from the walk's REAL start — so a trimmed start doesn't
    /// shift every marker.
    var markers: [CGPoint] = []

    static func == (a: RouteStickerTrace, b: RouteStickerTrace) -> Bool {
        a.key == b.key && a.points.count == b.points.count && a.size == b.size
            && a.markers.count == b.markers.count
    }

    /// The longest side of the trace, in points, before any pinch.
    static let longSide: CGFloat = 170
    /// Most points worth drawing at sticker size.
    private static let maxPoints = 400

    /// - Parameters:
    ///   - full: the whole route as recorded.
    ///   - kept: the stretch to draw. The composer passes the WHOLE walk: a
    ///     sticker is the walk's shape with no map under it (Strava's line),
    ///     so it says how the walk went, not where. Map surfaces keep the
    ///     server's hide-start-&-end trim; this one is the poster's own call.
    static func make(full: [CLLocationCoordinate2D], kept: ClosedRange<Int>, key: String) -> RouteStickerTrace? {
        guard kept.lowerBound >= 0, kept.upperBound < full.count else { return nil }
        let coordinates = Array(full[kept])
        guard coordinates.count >= 2 else { return nil }
        let step = max(1, coordinates.count / maxPoints)
        var sampled = stride(from: 0, to: coordinates.count, by: step).map { coordinates[$0] }
        if let last = coordinates.last, sampled.last.map({ $0.latitude != last.latitude || $0.longitude != last.longitude }) ?? true {
            sampled.append(last)
        }

        // The trace's own aspect, so the sticker hugs the shape rather than
        // floating a thin line in a square box. Same floored spans as
        // `RouteArtProjection`, clamped so an out-and-back on one street
        // still has some body.
        var minLat = sampled[0].latitude, maxLat = minLat
        var minLon = sampled[0].longitude, maxLon = minLon
        for c in sampled {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let cosMid = max(0.01, cos((minLat + maxLat) / 2 * .pi / 180))
        let spanX = max((maxLon - minLon) * cosMid, 0.0005)
        let spanY = max(maxLat - minLat, 0.0005)
        let aspect = min(max(CGFloat(spanX / spanY), 0.55), 1.8)
        let size = aspect >= 1
            ? CGSize(width: longSide, height: (longSide / aspect).rounded())
            : CGSize(width: (longSide * aspect).rounded(), height: longSide)

        let projection = RouteArtProjection(coordinates: sampled, size: size, padding: 9)
        return RouteStickerTrace(key: "\(key)|\(coordinates.count)",
                                 points: sampled.map { projection.point(for: $0) },
                                 size: size,
                                 markers: unitMarkers(full: full, kept: kept).map { projection.point(for: $0) })
    }

    /// The coordinate at each whole display unit from the start, kept only
    /// where it falls inside the shown stretch. Capped so a marathon stays
    /// a line with dots, not a string of beads.
    private static func unitMarkers(full: [CLLocationCoordinate2D], kept: ClosedRange<Int>) -> [CLLocationCoordinate2D] {
        let unitMeters = 1609.344 / DistanceUnits.current.perMile
        var out: [CLLocationCoordinate2D] = []
        var walked = 0.0
        var next = unitMeters
        for i in 1..<full.count {
            walked += meters(full[i - 1], full[i])
            while walked >= next {
                if kept.contains(i) { out.append(full[i]) }
                next += unitMeters
                if out.count >= 26 { return out }
            }
        }
        return out
    }

    private static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6_371_000.0, rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad
        let dLon = (b.longitude - a.longitude) * rad
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * rad) * cos(b.latitude * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}

/// The trace as a smooth line: a quadratic curve through each sample's
/// midpoints, so GPS jitter reads as a hand-drawn path, not a zig-zag. It
/// still starts and ends exactly on the first and last points (the dots).
private struct RouteTraceShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            for p in points.dropFirst() { path.addLine(to: p) }
            return path
        }
        for i in 1..<(points.count - 1) {
            let p = points[i], q = points[i + 1]
            path.addQuadCurve(to: CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2), control: p)
        }
        if let last = points.last { path.addLine(to: last) }
        return path
    }
}

/// The route sticker: the walk's shape, no map under it — so it says how
/// the walk WENT without saying where it was.
struct RouteTraceSticker: View {
    let trace: RouteStickerTrace
    let style: RouteStickerStyle
    let accent: Color
    /// "1.02 mi · 9:41" — the Card style's caption.
    let caption: String?
    /// The Stats and Badge styles' numbers: (label, value) for distance,
    /// time and pace, whichever the walk has.
    var stats: [(label: String, value: String)] = []
    /// The photo under it is bright: frameless lines go dark so they read.
    var onBright: Bool = false

    private var ink: Color { onBright ? Color(red: 0.08, green: 0.08, blue: 0.1) : .white }
    private var inkShadow: Color { onBright ? .white.opacity(0.5) : .black.opacity(0.55) }

    var body: some View {
        Group {
            switch style {
            case .line:
                line(color: ink, width: 5, outlined: true)
                    .shadow(color: inkShadow.opacity(0.6), radius: 3, x: 0, y: 1)
            case .markers:
                ZStack {
                    line(color: ink, width: 5)
                    ForEach(Array(trace.markers.enumerated()), id: \.offset) { index, point in
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(accent))
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                            .position(point)
                    }
                }
                .shadow(color: inkShadow, radius: 4, x: 0, y: 1)
            case .flamey:
                ZStack {
                    line(color: ink, width: 5)
                        .shadow(color: inkShadow, radius: 4, x: 0, y: 1)
                    if let end = trace.points.last {
                        // He stands on the finish, feet on the dot.
                        FlameBuddyView(health: .blazing, size: Self.finishFlameySize,
                                       phase: .blazing, coalWarmth: 1,
                                       mood: FlameMood(kind: .done, streak: 0),
                                       still: true, showsMoodBubble: false,
                                       look: FlameyFacts.ownLook(mood: .done))
                            .frame(width: Self.finishFlameySize, height: Self.finishFlameySize)
                            .position(x: end.x, y: end.y - Self.finishFlameySize * 0.42)
                    }
                }
                .frame(width: trace.size.width, height: trace.size.height)
                // Room for him to stand above the line's top edge, inside the
                // sticker's measured frame (so the editor's clamp sees him).
                .padding(.top, Self.finishFlameySize * 0.9)
                .padding(.horizontal, Self.finishFlameySize * 0.5)
            case .glow:
                ZStack {
                    line(color: accent, width: 7)
                        .shadow(color: accent.opacity(0.9), radius: 8)
                    RouteTraceShape(points: trace.points)
                        .stroke(Color.white.opacity(0.9),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: trace.size.width, height: trace.size.height)
                }
            case .stats:
                // Strava's share: the line, then the numbers under it.
                VStack(spacing: 12) {
                    line(color: ink, width: 5, outlined: true)
                    if !stats.isEmpty {
                        HStack(alignment: .top, spacing: 18) {
                            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                                VStack(spacing: 2) {
                                    Text(stat.label)
                                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                                        .tracking(0.8)
                                        .opacity(0.85)
                                    Text(stat.value)
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                        .monospacedDigit()
                                }
                                .lineLimit(1)
                            }
                        }
                        .foregroundColor(ink)
                        .shadow(color: inkShadow, radius: 4, x: 0, y: 1)
                    }
                }
            case .gradient:
                gradientLine(width: 6)
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1)
            case .bold:
                ZStack {
                    RouteTraceShape(points: trace.points)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                    RouteTraceShape(points: trace.points)
                        .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    endDots
                }
                .frame(width: trace.size.width, height: trace.size.height)
                .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 2)
            case .trail:
                // Footsteps: a dotted path from the start to the finish.
                ZStack {
                    RouteTraceShape(points: trace.points)
                        .stroke(ink, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round,
                                                        dash: [0.1, 9]))
                    endDots
                }
                .frame(width: trace.size.width, height: trace.size.height)
                .shadow(color: inkShadow, radius: 3, x: 0, y: 1)
            case .badge:
                badge
            case .card:
                VStack(spacing: 10) {
                    line(color: accent, width: 5)
                    if let caption {
                        HStack(spacing: 6) {
                            MADLogoMark(size: 15, opacity: 0.9, shadow: false)
                            Text(caption)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.42))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                )
            }
        }
        .fixedSize()
    }

    private static let finishFlameySize: CGFloat = 46

    /// A circle sticker: the route in the middle, the distance under it.
    private var badge: some View {
        let d: CGFloat = 176
        let fit = (d * 0.56) / max(trace.size.width, trace.size.height, 1)
        return ZStack {
            Circle().fill(accent)
            Circle().strokeBorder(Color.white, lineWidth: 5)
            RouteTraceShape(points: trace.points)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4.5 / fit, lineCap: .round, lineJoin: .round))
                .frame(width: trace.size.width, height: trace.size.height)
                .scaleEffect(fit)
                .offset(y: -10)
            if let distance = stats.first?.value {
                Text(distance)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: d * 0.6)
                    .offset(y: d * 0.33)
            }
        }
        .frame(width: d, height: d)
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
    }

    /// Start → finish in a sunset: the accent at the start, gold at the end.
    private func gradientLine(width: CGFloat) -> some View {
        let start = trace.points.first ?? .zero, end = trace.points.last ?? .zero
        let w = max(trace.size.width, 1), h = max(trace.size.height, 1)
        // A loop starts where it ends; run the gradient across the shape then.
        let loop = hypot(end.x - start.x, end.y - start.y) < 20
        let from = loop ? UnitPoint.topLeading : UnitPoint(x: start.x / w, y: start.y / h)
        let to = loop ? UnitPoint.bottomTrailing : UnitPoint(x: end.x / w, y: end.y / h)
        return ZStack {
            RouteTraceShape(points: trace.points)
                .stroke(LinearGradient(colors: [accent, Color(red: 1, green: 0.55, blue: 0.2),
                                                Color(red: 1, green: 0.85, blue: 0.3)],
                                       startPoint: from, endPoint: to),
                        style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            endDots
        }
        .frame(width: trace.size.width, height: trace.size.height)
    }

    /// The line with its start and finish dots. `outlined` puts a thin dark
    /// edge round it, so it holds up on any photo without a heavy shadow.
    private func line(color: Color, width: CGFloat, outlined: Bool = false) -> some View {
        ZStack {
            if outlined {
                RouteTraceShape(points: trace.points)
                    .stroke(Color.black.opacity(onBright ? 0.15 : 0.35),
                            style: StrokeStyle(lineWidth: width + 3, lineCap: .round, lineJoin: .round))
            }
            RouteTraceShape(points: trace.points)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            endDots
        }
        .frame(width: trace.size.width, height: trace.size.height)
    }

    /// The start (white, ringed) and finish (filled) dots.
    @ViewBuilder
    private var endDots: some View {
        ZStack {
            if let start = trace.points.first {
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(accent, lineWidth: 3))
                    .frame(width: 11, height: 11)
                    .position(start)
            }
            if let end = trace.points.last {
                Circle()
                    .fill(accent)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
                    .frame(width: 12, height: 12)
                    .position(end)
            }
        }
    }
}

// MARK: - Flamey

struct FlameyPostSticker: View {
    let sticker: FlameySticker
    let streak: Int?
    let accent: StickerAccent
    /// The undressed sticker-pack Flamey instead of the user's own look.
    var basic: Bool = false

    /// Figure size before his outfit is fitted (`ShareDressedFigure`).
    private static let figureSize: CGFloat = 104

    /// 10 March: no holiday, so the basic Flamey never borrows a holiday hat.
    private static let basicDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 10; c.hour = 12
        return Calendar.current.date(from: c) ?? Date()
    }()

    private var look: FlameyLook {
        let mood = sticker.mood
        if basic {
            let props = mood.map { FlameMood(kind: $0, streak: 0).props } ?? []
            return FlameyLook.resolve(owned: [], choice: .basic, date: Self.basicDate, mood: props)
        }
        return FlameyFacts.ownLook(mood: mood)
    }

    var body: some View {
        let mood = sticker.mood
        let look = self.look
        VStack(spacing: -4) {
            ShareDressedFigure(envelope: ShareFlameyEnvelope(look: look, mood: mood),
                               size: Self.figureSize, maxWidth: 170, maxHeight: 140) { d in
                FlameyDressedFigure(look: look, health: .blazing, size: d, scale: 1,
                                    arms: sticker.arms, mood: mood)
            }
            if let tag = sticker.tag(streak: streak) {
                Text(tag)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .tracking(0.6)
                    .monospacedDigit()
                    .foregroundColor(accent == .mono ? Color(red: 0.10, green: 0.05, blue: 0.06) : .white)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accent.color))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .rotationEffect(.degrees(-4))
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

// MARK: - Flamey pack

/// The drawn Flamey sticker pack, shipped as images in
/// Assets.xcassets/FlameyPack (trimmed, @3x). Raw values are the asset
/// names AND are persisted (`StickerMemory`): add cases, never rename.
enum FlameyPackSticker: String, CaseIterable, Identifiable {
    case hiii, lol, bet, loveThis = "love-this", thankYouuu = "thank-youuu", omw, gn, gm
    case nooo, letsGooo = "lets-gooo", nah, hmm, hypnotize, absoluteCinema = "absolute-cinema"
    case thisIsFine = "this-is-fine", sideEye = "side-eye", elevenFiftyEight = "1158pm", what
    case imDead = "im-dead", dealWithIt = "deal-with-it", bruh, mileDone = "mile-done"
    var id: String { rawValue }

    var assetName: String { "FlameyPack/\(rawValue)" }

    var title: String {
        switch self {
        case .hiii: return "hiii"
        case .lol: return "LMAOOO"
        case .bet: return "bet"
        case .loveThis: return "love this"
        case .thankYouuu: return "thank youuu"
        case .omw: return "omw"
        case .gn: return "gn"
        case .gm: return "gm"
        case .nooo: return "nooo"
        case .letsGooo: return "LET'S GOOO"
        case .nah: return "nah"
        case .hmm: return "hmm"
        case .hypnotize: return "you WILL get your mile in"
        case .absoluteCinema: return "absolute cinema"
        case .thisIsFine: return "this is fine"
        case .sideEye: return "side eye"
        case .elevenFiftyEight: return "11:58 PM"
        case .what: return "WHAT"
        case .imDead: return "i'm dead"
        case .dealWithIt: return "deal with it"
        case .bruh: return "bruh"
        case .mileDone: return "mile done"
        }
    }

    var keywords: String {
        let extra: String
        switch self {
        case .hiii: extra = "hi hello wave"
        case .lol: extra = "lol lmao laugh funny"
        case .gn: extra = "good night sleep tired"
        case .gm: extra = "good morning coffee"
        case .omw: extra = "on my way run fast"
        case .elevenFiftyEight: extra = "late close call midnight"
        case .hypnotize: extra = "hypnotize motivation"
        case .imDead: extra = "dead skeleton tired exhausted"
        case .dealWithIt: extra = "sunglasses cool"
        case .mileDone: extra = "done finished medal"
        default: extra = ""
        }
        return "flamey pack \(rawValue) \(title) \(extra)".lowercased()
    }
}

/// A pack sticker at a fixed natural size (longest side 150pt), from a
/// bundled image so `ImageRenderer` bakes it synchronously.
struct FlameyPackStickerView: View {
    let sticker: FlameyPackSticker
    static let longestSide: CGFloat = 150

    var body: some View {
        if let image = UIImage(named: sticker.assetName), image.size.width > 0, image.size.height > 0 {
            let k = Self.longestSide / max(image.size.width, image.size.height)
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: image.size.width * k, height: image.size.height * k)
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
                .fixedSize()
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}

// MARK: - Text

/// How the poster's own words are drawn — Instagram's text styles. A tap on
/// the photo cycles them. Raw values are persisted: add cases, never rename.
enum TextStickerStyle: String, CaseIterable, Identifiable {
    case classic, pill, neon, typewriter
    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .pill: return "Strong"
        case .neon: return "Neon"
        case .typewriter: return "Typewriter"
        }
    }
}

/// Emoji the picker offers, walk-themed first.
enum StickerEmoji {
    static let all = ["🔥", "💪", "👟", "🏃", "🚶", "🌅", "☀️", "🌧️", "❄️", "🌙",
                      "💯", "⚡️", "🎉", "🏆", "🥵", "😮‍💨", "😎", "🥳", "❤️", "🙌",
                      "🐶", "🌳", "🌊", "⛰️", "☕️", "🎧", "📍", "✨"]
}

struct TextPostSticker: View {
    let text: String
    let style: TextStickerStyle
    let accent: StickerAccent
    /// How wide a line may run before it wraps — the editor's line-width
    /// slider. nil = `defaultWidth`.
    var width: CGFloat? = nil

    static let widthRange: ClosedRange<CGFloat> = 90...320
    static let defaultWidth: CGFloat = 260
    static let lineLimit = 6

    /// The ink that reads on the accent fill (mono is white).
    private var onAccent: Color { accent == .mono ? Color(red: 0.08, green: 0.06, blue: 0.08) : .white }

    var body: some View {
        let words = text.isEmpty ? " " : text
        let w = Self.lineWidth(for: words, style: style, limit: width)
        Group {
            switch style {
            case .classic:
                wrapped(words, width: w)
                    .foregroundColor(accent.color)
                    .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 2)
            case .pill:
                wrapped(words, width: w)
                    .foregroundColor(onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent.color))
            case .neon:
                wrapped(words, width: w)
                    .foregroundColor(.white)
                    .shadow(color: accent.color, radius: 2)
                    .shadow(color: accent.color, radius: 8)
                    .shadow(color: accent.color.opacity(0.8), radius: 16)
            case .typewriter:
                wrapped(words, width: w)
                    .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.08))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Rectangle().fill(Color.white))
                    .overlay(Rectangle().fill(accent.color).frame(height: 3), alignment: .bottom)
            }
        }
        .fixedSize()
        .padding(6)
        .accessibilityHidden(true)
    }

    /// The words at a FIXED width, so the sticker wraps the same in the
    /// editor, on the photo and in the bake, whatever size it's offered.
    private func wrapped(_ words: String, width: CGFloat) -> some View {
        Text(words)
            .font(Self.font(style))
            .multilineTextAlignment(.center)
            .lineLimit(Self.lineLimit)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func font(_ style: TextStickerStyle) -> Font {
        switch style {
        case .classic: return .system(size: 30, weight: .heavy, design: .rounded)
        case .pill: return .system(size: 26, weight: .black, design: .rounded)
        case .neon: return .system(size: 30, weight: .bold, design: .rounded).italic()
        case .typewriter: return .system(size: 22, weight: .semibold, design: .monospaced)
        }
    }

    private static func uiFont(_ style: TextStickerStyle) -> UIFont {
        let spec: (size: CGFloat, weight: UIFont.Weight, design: UIFontDescriptor.SystemDesign)
        switch style {
        case .classic: spec = (30, .heavy, .rounded)
        case .pill: spec = (26, .black, .rounded)
        case .neon: spec = (30, .bold, .rounded)
        case .typewriter: spec = (22, .semibold, .monospaced)
        }
        let (size, weight, design) = spec
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        var descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        if style == .neon { descriptor = descriptor.withSymbolicTraits(.traitItalic) ?? descriptor }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// The narrower of the longest typed line and the chosen limit: short
    /// words stay hugged, long ones wrap at the limit.
    static func lineWidth(for words: String, style: TextStickerStyle, limit: CGFloat?) -> CGFloat {
        let cap = (limit ?? defaultWidth).clamped(to: widthRange)
        let font = uiFont(style)
        let longest = words.split(separator: "\n", omittingEmptySubsequences: false)
            .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        // A little slack so rounding never wraps a line that fits.
        return min(cap, ceil(longest) + 6)
    }
}

// MARK: - Badge

/// A word or two on a pill. A tap cycles `variant` through four looks.
struct FunBadgeSticker: View {
    let badge: FunBadge
    let text: String
    let accent: StickerAccent
    let variant: Int

    static let variantCount = 4

    private var dark: Color { Color(red: 0.08, green: 0.06, blue: 0.08) }

    var body: some View {
        let v = ((variant % Self.variantCount) + Self.variantCount) % Self.variantCount
        let fills: [Color] = [accent.color, Color.white, Color.black.opacity(0.5), accent.color]
        let fill = fills[v]
        let ink: Color = (v == 1 || (accent == .mono && (v == 0 || v == 3))) ? dark : .white
        HStack(spacing: 7) {
            Image(systemName: badge.icon)
                .font(.system(size: v == 3 ? 20 : 16, weight: .heavy))
            Text(text)
                .font(.system(size: v == 3 ? 22 : 18, weight: .black, design: .rounded))
                .tracking(0.6)
                .monospacedDigit()
        }
        .lineLimit(1)
        .foregroundColor(ink)
        .padding(.horizontal, v == 3 ? 20 : 16)
        .padding(.vertical, v == 3 ? 12 : 9)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(Color.white.opacity(v == 2 ? 0.55 : 0.3), lineWidth: v == 2 ? 1.5 : 1))
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        .rotationEffect(.degrees(v == 3 ? -6 : 0))
        .padding(v == 3 ? 10 : 2)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

// MARK: - Single number

/// One stat, big and frameless — the Strava-style number you drop beside
/// the view. A soft shadow keeps it readable on any photo.
struct NumberPostSticker: View {
    let kind: RunStatKind
    let input: RunStatsInput
    let accent: StickerAccent
    /// Bright photo under it: dark numbers with a light halo instead of
    /// white numbers that vanish into a sky.
    var onBright: Bool = false

    private var ink: Color { onBright ? Color(red: 0.08, green: 0.08, blue: 0.1) : .white }

    /// Label, value and an optional smaller unit. Nil when the walk has no
    /// such number (the tray never offers it then).
    static func parts(for kind: RunStatKind, input: RunStatsInput) -> (label: String, value: String, unit: String?)? {
        let unit = DistanceUnits.current
        switch kind {
        case .distance:
            guard input.distance > 0 else { return nil }
            return ("DISTANCE", (input.isExtra ? "+" : "") + input.distance.distanceText, unit.abbreviation)
        case .duration:
            guard let d = input.durationSeconds, d > 0 else { return nil }
            return ("TIME", RunStatsStickerView.durationText(d), nil)
        case .pace:
            guard let p = input.paceSecondsPerMile, p > 0 else { return nil }
            return ("PACE", RunStatsStickerView.paceText(p.pacePerDisplayUnit), unit.paceSuffix)
        case .streak:
            guard let s = input.streak, s > 0 else { return nil }
            return ("DAY STREAK", "\(s)", nil)
        case .calories:
            guard let c = input.calories, c > 0 else { return nil }
            return ("CALORIES", "\(Int(c.rounded()))", nil)
        case .steps:
            guard let st = input.steps, st > 0, let datum = input.datum(for: .steps) else { return nil }
            return ("STEPS", datum.value, nil)
        case .date:
            guard let d = input.dateText, !d.isEmpty else { return nil }
            return ("DATE", d, nil)
        case .competition:
            return nil
        }
    }

    /// The kinds a Numbers sticker can be made of, in tray order.
    static func available(for input: RunStatsInput) -> [RunStatKind] {
        [.distance, .duration, .pace, .streak, .steps, .calories, .date]
            .filter { parts(for: $0, input: input) != nil }
    }

    var body: some View {
        if let parts = Self.parts(for: kind, input: input) {
            VStack(spacing: 0) {
                Text(parts.label)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundColor(accent.color)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.value)
                        .font(.system(size: kind == .date ? 30 : 46, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(ink)
                    if let u = parts.unit {
                        Text(u)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(ink.opacity(0.9))
                    }
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 6)
            .shadow(color: onBright ? .white.opacity(0.55) : .black.opacity(0.55), radius: 6, x: 0, y: 2)
            .fixedSize()
        }
    }
}

// MARK: - Dispatcher

/// Any sticker, drawn. The one view both the live editor and the baked
/// `PostCanvas` use, so the preview and the upload can't disagree.
struct PostStickerView: View, Equatable {
    let kind: PostStickerKind
    let context: StickerRenderContext
    /// The photo under this sticker is bright (`StickerPlacement.brightThreshold`).
    /// Decided by the composer from where the sticker sits, identically for
    /// the editor and the bake.
    var onBright: Bool = false
    /// The sticker's own colour (`PlacedSticker.accent`); nil = the default.
    var accent: StickerAccent? = nil
    var variant: Int = 0
    var text: String? = nil
    var textWidth: CGFloat? = nil

    init(kind: PostStickerKind, context: StickerRenderContext, onBright: Bool = false,
         accent: StickerAccent? = nil, variant: Int = 0, text: String? = nil, textWidth: CGFloat? = nil) {
        self.kind = kind
        self.context = context
        self.onBright = onBright
        self.accent = accent
        self.variant = variant
        self.text = text
        self.textWidth = textWidth
    }

    /// Everything one placed sticker needs, in one call.
    init(_ sticker: PlacedSticker, context: StickerRenderContext, onBright: Bool = false) {
        self.init(kind: sticker.kind, context: context, onBright: onBright,
                  accent: sticker.accent, variant: sticker.variant, text: sticker.text,
                  textWidth: sticker.textWidth)
    }

    private var resolvedAccent: StickerAccent { accent ?? context.config.accent }

    var body: some View {
        switch kind {
        case .stats:
            RunStatsStickerView(input: context.input, config: statsConfig)
        case .flamey(let sticker):
            FlameyPostSticker(sticker: sticker, streak: context.input.streak, accent: resolvedAccent)
        case .basicFlamey(let sticker):
            FlameyPostSticker(sticker: sticker, streak: context.input.streak, accent: resolvedAccent,
                              basic: true)
        case .route(let style):
            if let trace = context.route {
                RouteTraceSticker(trace: trace, style: style, accent: resolvedAccent.color,
                                  caption: Self.routeCaption(context.input),
                                  stats: Self.routeStats(context.input), onBright: onBright)
            }
        case .number(let stat):
            NumberPostSticker(kind: stat, input: context.input, accent: resolvedAccent,
                              onBright: onBright)
        case .badge(let badge):
            FunBadgeSticker(badge: badge, text: badge.text(captured: text), accent: resolvedAccent,
                            variant: variant)
        case .text(let style):
            TextPostSticker(text: text ?? "", style: style, accent: resolvedAccent, width: textWidth)
        case .pack(let sticker):
            FlameyPackStickerView(sticker: sticker)
        case .emoji(let emoji):
            Text(emoji)
                .font(.system(size: 84))
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
                .padding(4)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }

    private var statsConfig: StickerConfig {
        guard let accent else { return context.config }
        var cfg = context.config
        cfg.accent = accent
        return cfg
    }

    /// "1.02 mi · 9:41" (time only when the walk has one).
    /// Distance, time and pace for the route's Stats and Badge styles,
    /// through the same formatting as the number stickers.
    static func routeStats(_ input: RunStatsInput) -> [(label: String, value: String)] {
        [RunStatKind.distance, .duration, .pace].compactMap { kind in
            NumberPostSticker.parts(for: kind, input: input).map { parts in
                (label: parts.label, value: parts.value + (parts.unit.map { " " + $0 } ?? ""))
            }
        }
    }

    static func routeCaption(_ input: RunStatsInput) -> String? {
        guard input.distance > 0 else { return nil }
        var text = input.distance.distanceFormatted
        if let d = input.durationSeconds, d > 0 {
            text += " · " + RunStatsStickerView.durationText(d)
        }
        return text
    }
}
