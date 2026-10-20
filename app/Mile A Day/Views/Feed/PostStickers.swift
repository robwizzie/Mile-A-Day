import SwiftUI
import CoreLocation

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
        case .clock: return "Time"
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
enum RouteStickerStyle: String, CaseIterable, Identifiable {
    case line, glow, markers, flamey, card
    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: return "Line"
        case .glow: return "Glow"
        case .markers: return DistanceUnits.current == .miles ? "Miles" : "Km"
        case .flamey: return "Flamey"
        case .card: return "Card"
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

    enum Slot: Hashable {
        case stats, flamey, basicFlamey, route, badge
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
        }
    }

    /// One per photo: adding it again restyles the one already there.
    var isSingleton: Bool {
        switch self {
        case .stats, .route, .number: return true
        case .flamey, .basicFlamey, .badge: return false
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
        case .badge: return CGPoint(x: 0.5, y: 0.5)
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

    init(kind: PostStickerKind, pos: CGPoint? = nil, scale: CGFloat = 1, rotation: Angle = .zero,
         accent: StickerAccent? = nil, variant: Int = 0, text: String? = nil) {
        self.kind = kind
        self.pos = pos ?? kind.defaultPosition
        self.scale = scale
        self.rotation = rotation
        self.accent = accent
        self.variant = variant
        self.text = text
    }

    /// The same sticker under a new identity — used when one view's stickers
    /// are copied onto the other, so the two layers never share view ids.
    func duplicated() -> PlacedSticker {
        PlacedSticker(kind: kind, pos: pos, scale: scale, rotation: rotation,
                      accent: accent, variant: variant, text: text)
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

private struct RouteTraceShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
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
    /// The photo under it is bright: frameless lines go dark so they read.
    var onBright: Bool = false

    private var ink: Color { onBright ? Color(red: 0.08, green: 0.08, blue: 0.1) : .white }
    private var inkShadow: Color { onBright ? .white.opacity(0.5) : .black.opacity(0.55) }

    var body: some View {
        Group {
            switch style {
            case .line:
                line(color: ink, width: 5)
                    .shadow(color: inkShadow, radius: 4, x: 0, y: 1)
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

    /// The line with its start and finish dots.
    private func line(color: Color, width: CGFloat) -> some View {
        ZStack {
            RouteTraceShape(points: trace.points)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
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
        .frame(width: trace.size.width, height: trace.size.height)
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

    init(kind: PostStickerKind, context: StickerRenderContext, onBright: Bool = false,
         accent: StickerAccent? = nil, variant: Int = 0, text: String? = nil) {
        self.kind = kind
        self.context = context
        self.onBright = onBright
        self.accent = accent
        self.variant = variant
        self.text = text
    }

    /// Everything one placed sticker needs, in one call.
    init(_ sticker: PlacedSticker, context: StickerRenderContext, onBright: Bool = false) {
        self.init(kind: sticker.kind, context: context, onBright: onBright,
                  accent: sticker.accent, variant: sticker.variant, text: sticker.text)
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
                                  caption: Self.routeCaption(context.input), onBright: onBright)
            }
        case .number(let stat):
            NumberPostSticker(kind: stat, input: context.input, accent: resolvedAccent,
                              onBright: onBright)
        case .badge(let badge):
            FunBadgeSticker(badge: badge, text: badge.text(captured: text), accent: resolvedAccent,
                            variant: variant)
        }
    }

    private var statsConfig: StickerConfig {
        guard let accent else { return context.config }
        var cfg = context.config
        cfg.accent = accent
        return cfg
    }

    /// "1.02 mi · 9:41" (time only when the walk has one).
    static func routeCaption(_ input: RunStatsInput) -> String? {
        guard input.distance > 0 else { return nil }
        var text = input.distance.distanceFormatted
        if let d = input.durationSeconds, d > 0 {
            text += " · " + RunStatsStickerView.durationText(d)
        }
        return text
    }
}
