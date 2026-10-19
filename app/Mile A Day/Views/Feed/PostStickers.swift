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

/// One of Flamey's stickers: a mood that renders still, plus a tag.
///
/// Each is a real `FlameBuddyView` in the user's OWN look
/// (`FlameyFacts.ownLook`) — the Flamey they dressed in the Closet, whatever
/// the dashboard style — so the sticker is recognisably theirs.
enum FlameySticker: String, CaseIterable, Identifiable {
    case mileDone, onFire, closeCall, riseAndRun, justFlamey
    var id: String { rawValue }

    /// The tray tile's label.
    var title: String {
        switch self {
        case .mileDone: return "Mile done"
        case .onFire: return "On fire"
        case .closeCall: return "Close call"
        case .riseAndRun: return "Rise & run"
        case .justFlamey: return "Just him"
        }
    }

    /// Only moods whose still frame reads well — shades, the party hat, the
    /// sweat drop, the nightcap. Never his speech bubble: a bubble baked into
    /// a picture reads as a caption nobody wrote.
    var mood: FlameMood.Kind? {
        switch self {
        case .mileDone: return .done
        case .onFire: return .party
        case .closeCall: return .nervous
        case .riseAndRun: return .sleepy
        case .justFlamey: return nil
        }
    }

    func tag(streak: Int?) -> String? {
        switch self {
        case .mileDone: return "MILE DONE"
        case .onFire:
            if let streak, streak > 0 { return "DAY \(streak)" }
            return "ON FIRE"
        case .closeCall: return "THAT WAS CLOSE"
        case .riseAndRun: return "RISE & RUN"
        case .justFlamey: return nil
        }
    }
}

/// How the route sticker draws the walk's trace.
enum RouteStickerStyle: String, CaseIterable, Identifiable {
    case line, glow, card
    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: return "Line"
        case .glow: return "Glow"
        case .card: return "Card"
        }
    }
}

/// What a sticker IS. Each case is also a slot: a photo carries at most one
/// sticker per slot (`slot`), so the tray can show a plain on/off state for
/// every tile instead of a pile of duplicates nobody asked for.
enum PostStickerKind: Hashable {
    /// The run-stats sticker, styled by the composer's `StickerConfig`.
    case stats
    case flamey(FlameySticker)
    case route(RouteStickerStyle)
    /// One big number, Strava-style: "3.12 mi", "28:41", "42 day streak".
    case number(RunStatKind)

    enum Slot: Hashable {
        case stats, flamey, route
        case number(RunStatKind)
    }

    var slot: Slot {
        switch self {
        case .stats: return .stats
        case .flamey: return .flamey
        case .route: return .route
        case .number(let kind): return .number(kind)
        }
    }

    /// Where a freshly added sticker lands (normalized canvas centre). Kept
    /// clear of the stats sticker's default spot near the bottom and of the
    /// FRONT & BACK inset (top-trailing by default), and re-clamped by the
    /// editor once the sticker's real size is known.
    var defaultPosition: CGPoint {
        switch self {
        case .stats: return CGPoint(x: 0.5, y: 0.82)
        case .flamey: return CGPoint(x: 0.74, y: 0.58)
        case .route: return CGPoint(x: 0.36, y: 0.46)
        case .number: return CGPoint(x: 0.34, y: 0.2)
        }
    }

    var accessibilityName: String {
        switch self {
        case .stats: return "Stats sticker"
        case .flamey(let f): return "Flamey sticker, \(f.title)"
        case .route(let s): return "Route sticker, \(s.title)"
        case .number(let k): return "\(k.label) sticker"
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

    init(kind: PostStickerKind, pos: CGPoint? = nil, scale: CGFloat = 1, rotation: Angle = .zero) {
        self.kind = kind
        self.pos = pos ?? kind.defaultPosition
        self.scale = scale
        self.rotation = rotation
    }

    /// The same sticker under a new identity — used when one view's stickers
    /// are copied onto the other, so the two layers never share view ids.
    func duplicated() -> PlacedSticker {
        PlacedSticker(kind: kind, pos: pos, scale: scale, rotation: rotation)
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
/// Built ONCE from the privacy-trimmed coordinates (`make`), so the editor
/// never re-projects thousands of GPS samples per frame, and compared by key +
/// count so equality is O(1).
struct RouteStickerTrace: Equatable {
    let key: String
    let points: [CGPoint]
    let size: CGSize

    static func == (a: RouteStickerTrace, b: RouteStickerTrace) -> Bool {
        a.key == b.key && a.points.count == b.points.count && a.size == b.size
    }

    /// The longest side of the trace, in points, before any pinch.
    static let longSide: CGFloat = 170
    /// Most points worth drawing at sticker size.
    private static let maxPoints = 400

    /// - Parameter coordinates: the route AFTER `RoutePrivacyTrim.shareable`
    ///   — a sticker publishes the shape of the walk, so it gets the same
    ///   hide-start-&-end treatment as every other surface that shares it.
    static func make(coordinates: [CLLocationCoordinate2D], key: String) -> RouteStickerTrace? {
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
                                 size: size)
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

    var body: some View {
        Group {
            switch style {
            case .line:
                line(color: .white, width: 5)
                    .shadow(color: .black.opacity(0.55), radius: 4, x: 0, y: 1)
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

    /// Figure size before his outfit is fitted (`ShareDressedFigure`).
    private static let figureSize: CGFloat = 104

    var body: some View {
        let mood = sticker.mood
        let look = FlameyFacts.ownLook(mood: mood)
        VStack(spacing: -4) {
            ShareDressedFigure(envelope: ShareFlameyEnvelope(look: look, mood: mood),
                               size: Self.figureSize, maxWidth: 170, maxHeight: 140) { d in
                FlameBuddyView(health: .blazing, size: d,
                               phase: .blazing, coalWarmth: 1,
                               mood: mood.map { FlameMood(kind: $0, streak: streak ?? 0) },
                               still: true, showsMoodBubble: false,
                               look: look)
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

// MARK: - Single number

/// One stat, big and frameless — the Strava-style number you drop beside
/// the view. A soft shadow keeps it readable on any photo.
struct NumberPostSticker: View {
    let kind: RunStatKind
    let input: RunStatsInput
    let accent: StickerAccent

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
                        .foregroundColor(.white)
                    if let u = parts.unit {
                        Text(u)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 6)
            .shadow(color: .black.opacity(0.55), radius: 6, x: 0, y: 2)
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

    var body: some View {
        switch kind {
        case .stats:
            RunStatsStickerView(input: context.input, config: context.config)
        case .flamey(let sticker):
            FlameyPostSticker(sticker: sticker, streak: context.input.streak,
                              accent: context.config.accent)
        case .route(let style):
            if let trace = context.route {
                RouteTraceSticker(trace: trace, style: style, accent: context.config.accent.color,
                                  caption: Self.routeCaption(context.input))
            }
        case .number(let stat):
            NumberPostSticker(kind: stat, input: context.input, accent: context.config.accent)
        }
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
