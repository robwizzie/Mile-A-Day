import SwiftUI
import CoreLocation
import HealthKit

// MARK: - Style

/// How a finish frame looks: chosen in `AddFinishStorySheet` (remembered as
/// the next default) and carried on the post in `stats_snapshot`
/// (`frame_theme` / `frame_route` / `frame_flamey`), which every story read
/// returns verbatim. Unknown or absent values fall back to the defaults, so
/// an older post (or a newer value an old build doesn't know) still draws.
struct FinishFrameStyle: Equatable {
    var theme: Theme = .ember
    var route: RouteStyle = .neon
    var flamey: Bool = true

    enum Theme: String, CaseIterable, Identifiable {
        case ember, midnight, sunset, aurora, chalk
        var id: String { rawValue }

        var name: String {
            switch self {
            case .ember: return "Ember"
            case .midnight: return "Midnight"
            case .sunset: return "Sunset"
            case .aurora: return "Aurora"
            case .chalk: return "Chalk"
            }
        }

        /// Background, top to bottom.
        var background: [Color] {
            switch self {
            case .ember: return [Color(red: 0.30, green: 0.09, blue: 0.13), Color(red: 0.07, green: 0.02, blue: 0.04)]
            case .midnight: return [Color(red: 0.06, green: 0.10, blue: 0.24), Color(red: 0.01, green: 0.02, blue: 0.07)]
            case .sunset: return [Color(red: 0.98, green: 0.55, blue: 0.30), Color(red: 0.86, green: 0.25, blue: 0.45), Color(red: 0.30, green: 0.10, blue: 0.40)]
            case .aurora: return [Color(red: 0.04, green: 0.22, blue: 0.27), Color(red: 0.08, green: 0.07, blue: 0.24), Color(red: 0.02, green: 0.03, blue: 0.08)]
            case .chalk: return [Color(red: 0.98, green: 0.95, blue: 0.90), Color(red: 0.93, green: 0.88, blue: 0.81)]
            }
        }

        /// The route's colours, start → finish.
        var route: [Color] {
            switch self {
            case .ember: return [Color(red: 1.0, green: 0.78, blue: 0.30), Color(red: 1.0, green: 0.36, blue: 0.30)]
            case .midnight: return [Color(red: 0.45, green: 0.95, blue: 1.0), Color(red: 0.30, green: 0.50, blue: 1.0)]
            case .sunset: return [.white, Color(red: 1.0, green: 0.92, blue: 0.55)]
            case .aurora: return [Color(red: 0.45, green: 1.0, blue: 0.72), Color(red: 0.55, green: 0.55, blue: 1.0)]
            case .chalk: return [Color(red: 0.85, green: 0.25, blue: 0.35), Color(red: 0.95, green: 0.50, blue: 0.20)]
            }
        }

        var isLight: Bool { self == .chalk }
        var text: Color { isLight ? Color(red: 0.16, green: 0.10, blue: 0.10) : .white }
        var subtext: Color { text.opacity(isLight ? 0.6 : 0.65) }
        /// Stat tiles' fill.
        var tile: Color { isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08) }
    }

    enum RouteStyle: String, CaseIterable, Identifiable {
        case neon, gradient, dotted
        var id: String { rawValue }
        var name: String {
            switch self {
            case .neon: return "Neon"
            case .gradient: return "Gradient"
            case .dotted: return "Dotted"
            }
        }
        var icon: String {
            switch self {
            case .neon: return "sparkles"
            case .gradient: return "paintbrush.pointed.fill"
            case .dotted: return "circle.dotted"
            }
        }
    }

    /// The style a post carries (defaults for anything missing or unknown).
    init(stats: PostStats?) {
        theme = stats?.frame_theme.flatMap(Theme.init(rawValue:)) ?? .ember
        route = stats?.frame_route.flatMap(RouteStyle.init(rawValue:)) ?? .neon
        flamey = stats?.frame_flamey ?? true
    }

    init(theme: Theme = .ember, route: RouteStyle = .neon, flamey: Bool = true) {
        self.theme = theme
        self.route = route
        self.flamey = flamey
    }

    // Remembered per device: your last pick is next time's default.
    private static let key = "finishFrameStyleV1"
    static var lastUsed: FinishFrameStyle {
        let parts = (UserDefaults.standard.string(forKey: key) ?? "").split(separator: "|").map(String.init)
        guard parts.count == 3 else { return FinishFrameStyle() }
        return FinishFrameStyle(theme: Theme(rawValue: parts[0]) ?? .ember,
                                route: RouteStyle(rawValue: parts[1]) ?? .neon,
                                flamey: parts[2] == "1")
    }
    func remember() {
        UserDefaults.standard.set("\(theme.rawValue)|\(route.rawValue)|\(flamey ? "1" : "0")", forKey: Self.key)
    }

    /// Writes the style into a post's stats.
    func apply(to stats: PostStats) -> PostStats {
        var s = stats
        s.frame_theme = theme.rawValue
        s.frame_route = route.rawValue
        s.frame_flamey = flamey
        return s
    }
}

// MARK: - Frame

/// The finish frame: a story with no photo, drawn live from the walk. It
/// only ever exists because the user added it on purpose (the Today tile's
/// "Add to my story", `AddFinishStorySheet`); nothing posts one on its own.
///
/// Laid out as a designed card, not a line on a void: date and wordmark on
/// top, the route large with a start ring and a glowing finish (Flamey riding
/// it, when on), the distance big, and Time / Pace / Streak tiles, all in the
/// chosen `FinishFrameStyle`. The bottom stays clear for the story footer.
///
/// Used full-screen in the story viewer and, still, as the sheet's preview.
struct StoryFinishFrame: View {
    let stats: PostStats?
    let coordinates: [CLLocationCoordinate2D]?
    let workoutType: String?
    var style: FinishFrameStyle? = nil
    /// The AUTHOR's Flamey (`FeedCardFlamey.look`), nil = no Flamey to draw.
    var flameyLook: FlameyLook? = nil
    /// Draw the finished frame with no motion (the sheet's preview, and
    /// Reduce Motion).
    var still: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var traced: CGFloat = 0
    @State private var shownMiles: Double = 0

    private var resolved: FinishFrameStyle { style ?? FinishFrameStyle(stats: stats) }
    private var theme: FinishFrameStyle.Theme { resolved.theme }
    private var miles: Double { stats?.distance ?? 0 }
    private var animates: Bool { !still && !reduceMotion }
    private var points: [CGPoint] {
        guard let coordinates, coordinates.count >= 2 else { return [] }
        return Self.normalize(coordinates)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // Scales every size from a 390-wide story, so the small preview
            // in the sheet is the same picture, just smaller.
            let k = max(0.3, w / 390)
            ZStack {
                background(w: w, h: h)

                VStack(spacing: 0) {
                    header(k: k)
                        .padding(.top, h * 0.13)
                        .padding(.horizontal, 24 * k)
                    routeArea(k: k)
                        .frame(height: h * 0.38)
                        .padding(.horizontal, w * 0.12)
                        .padding(.top, 14 * k)
                    numbers(k: k)
                        .padding(.top, 10 * k)
                    statTiles(k: k)
                        .padding(.horizontal, 22 * k)
                        .padding(.top, 16 * k)
                    Spacer(minLength: 0)
                }
                // Room for the story footer (Seen by / Add to feed).
                .padding(.bottom, h * 0.12)
            }
        }
        .onAppear {
            guard animates else {
                traced = 1
                shownMiles = miles
                return
            }
            // Next turn, so the trace and the roll start from their empty
            // state on screen rather than inside the appear commit.
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 1.9)) { traced = 1 }
                withAnimation(.easeOut(duration: 1.2).delay(0.4)) { shownMiles = miles }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Pieces

    private func background(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: theme.background, startPoint: .top, endPoint: .bottom)
            // A soft glow behind the route, in the route's colour.
            RadialGradient(colors: [theme.route[0].opacity(theme.isLight ? 0.18 : 0.28), .clear],
                           center: UnitPoint(x: 0.5, y: 0.36), startRadius: 0, endRadius: w * 0.75)
            if theme == .midnight || theme == .aurora {
                Starfield(seed: 7, count: 46, color: .white.opacity(0.55))
            }
        }
    }

    private func header(k: CGFloat) -> some View {
        HStack {
            Text(dateLine)
                .font(.system(size: 12 * k, weight: .heavy, design: .rounded))
                .tracking(1.2 * k)
                .foregroundColor(theme.subtext)
            Spacer()
            HStack(spacing: 4 * k) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11 * k, weight: .bold))
                    .foregroundColor(theme.route[1])
                Text("MILE A DAY")
                    .font(.system(size: 11 * k, weight: .black, design: .rounded))
                    .tracking(1.4 * k)
                    .foregroundColor(theme.subtext)
            }
        }
    }

    @ViewBuilder
    private func routeArea(k: CGFloat) -> some View {
        if points.count >= 2 {
            GeometryReader { box in
                let rect = CGRect(origin: .zero, size: box.size)
                let shape = RouteTraceShape(points: points)
                ZStack {
                    routeStroke(shape, k: k)
                    // Start: a ring where the walk began.
                    if let a = RouteTraceShape.place(points.first!, in: rect) {
                        Circle()
                            .strokeBorder(theme.route[0], lineWidth: 3 * k)
                            .background(Circle().fill(theme.background.last ?? .black))
                            .frame(width: 14 * k, height: 14 * k)
                            .position(a)
                    }
                    // Finish: a glowing dot, and Flamey riding it.
                    if let b = RouteTraceShape.place(points.last!, in: rect) {
                        Circle()
                            .fill(theme.route[1])
                            .frame(width: 16 * k, height: 16 * k)
                            .shadow(color: theme.route[1].opacity(0.9), radius: 10 * k)
                            .position(b)
                            .opacity(traced >= 0.98 ? 1 : 0)
                        if resolved.flamey {
                            FlameBuddyView(health: .healthy, size: 46 * k, still: still,
                                           showsMoodBubble: false, look: flameyLook, wardrobeReach: 0.6)
                                .frame(width: 60 * k, height: 60 * k)
                                .position(x: b.x, y: b.y - 34 * k)
                                .opacity(traced >= 0.98 ? 1 : 0)
                                .scaleEffect(traced >= 0.98 ? 1 : 0.6, anchor: .bottom)
                                .animation(.spring(response: 0.45, dampingFraction: 0.6), value: traced >= 0.98)
                        }
                    }
                }
            }
        } else {
            // No route (indoor, maps off, stealth): Flamey or the activity.
            ZStack {
                if resolved.flamey {
                    FlameBuddyView(health: .healthy, size: 130 * k, still: still,
                                   showsMoodBubble: false, look: flameyLook, wardrobeReach: 0.7)
                } else {
                    Image(systemName: ActivityCardView.icon(workoutType, paceSecondsPerMile: stats?.pace))
                        .font(.system(size: 76 * k, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: theme.route, startPoint: .top, endPoint: .bottom))
                }
            }
            .opacity(traced)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func routeStroke(_ shape: RouteTraceShape, k: CGFloat) -> some View {
        let trimmed = shape.trim(from: 0, to: traced)
        switch resolved.route {
        case .neon:
            trimmed
                .stroke(theme.route[1], style: StrokeStyle(lineWidth: 5 * k, lineCap: .round, lineJoin: .round))
                .shadow(color: theme.route[1].opacity(0.9), radius: 6 * k)
                .shadow(color: theme.route[0].opacity(0.6), radius: 16 * k)
        case .gradient:
            trimmed
                .stroke(LinearGradient(colors: theme.route, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 8 * k, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(theme.isLight ? 0.12 : 0.35), radius: 4 * k, y: 2 * k)
        case .dotted:
            trimmed
                .stroke(LinearGradient(colors: theme.route, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 6 * k, lineCap: .round, lineJoin: .round, dash: [0.1, 12 * k]))
        }
    }

    private func numbers(k: CGFloat) -> some View {
        VStack(spacing: 2 * k) {
            HStack(alignment: .firstTextBaseline, spacing: 6 * k) {
                Text(shownMiles.distanceText)
                    .font(.system(size: 76 * k, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: shownMiles))
                    .foregroundColor(theme.text)
                Text(DistanceUnits.current.abbreviation.uppercased())
                    .font(.system(size: 20 * k, weight: .heavy, design: .rounded))
                    .foregroundColor(theme.subtext)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(PostCardView.activityNoun(workoutType, pace: stats?.pace).uppercased() + " COMPLETE")
                .font(.system(size: 13 * k, weight: .heavy, design: .rounded))
                .tracking(1.6 * k)
                .foregroundStyle(LinearGradient(colors: theme.route, startPoint: .leading, endPoint: .trailing))
        }
    }

    private func statTiles(k: CGFloat) -> some View {
        HStack(spacing: 10 * k) {
            if let duration = stats?.duration, duration > 0 {
                tile(value: Self.clock(duration), label: "TIME", k: k)
            }
            if let pace = stats?.pace, pace > 0 {
                tile(value: Self.clock(pace.pacePerDisplayUnit), label: "PACE \(DistanceUnits.current.paceSuffix.uppercased())", k: k)
            }
            if let streak = stats?.streak, streak > 0 {
                tile(value: "\(streak)", label: "DAY STREAK", k: k, flame: true)
            }
        }
    }

    private func tile(value: String, label: String, k: CGFloat, flame: Bool = false) -> some View {
        VStack(spacing: 3 * k) {
            HStack(spacing: 3 * k) {
                if flame {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 15 * k, weight: .bold))
                        .foregroundColor(.orange)
                }
                Text(value)
                    .font(.system(size: 21 * k, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(flame ? .orange : theme.text)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10 * k, weight: .heavy, design: .rounded))
                .tracking(0.8 * k)
                .foregroundColor(theme.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12 * k)
        .background(RoundedRectangle(cornerRadius: 16 * k, style: .continuous).fill(theme.tile))
    }

    // MARK: Text

    /// "THU, NOV 5" from the post's day (today in a preview).
    private var dateLine: String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        let day = stats?.date.flatMap { parser.date(from: String($0.prefix(10))) } ?? Date()
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    private var accessibilitySummary: String {
        var s = "\(PostCardView.activityNoun(workoutType, pace: stats?.pace)) finished, \(miles.distanceFormatted)"
        if let streak = stats?.streak, streak > 0 { s += ", \(streak) day streak" }
        return s
    }

    /// Route → points in a unit box, aspect preserved (equirectangular with a
    /// cos(latitude) squeeze, plenty at walk scale).
    static func normalize(_ coords: [CLLocationCoordinate2D]) -> [CGPoint] {
        guard let first = coords.first else { return [] }
        let k = cos(first.latitude * .pi / 180)
        let xs = coords.map { $0.longitude * k }
        let ys = coords.map { -$0.latitude }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return [] }
        let span = max(maxX - minX, maxY - minY, 1e-9)
        let offX = (span - (maxX - minX)) / 2
        let offY = (span - (maxY - minY)) / 2
        return zip(xs, ys).map { pair in
            CGPoint(x: (pair.0 - minX + offX) / span, y: (pair.1 - minY + offY) / span)
        }
    }
}

/// A route already normalized to a unit square, drawn centred in the rect.
private struct RouteTraceShape: Shape {
    let points: [CGPoint]

    /// Where a unit point lands in `rect` (the same placement as the path).
    static func place(_ p: CGPoint, in rect: CGRect) -> CGPoint? {
        let side = min(rect.width, rect.height)
        guard side > 0 else { return nil }
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        return CGPoint(x: origin.x + p.x * side, y: origin.y + p.y * side)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2, let first = Self.place(points[0], in: rect) else { return path }
        path.move(to: first)
        for p in points.dropFirst() {
            if let q = Self.place(p, in: rect) { path.addLine(to: q) }
        }
        return path
    }
}

/// A fixed scatter of small stars (deterministic, so it never shimmers
/// between redraws).
private struct Starfield: View {
    let seed: UInt64
    let count: Int
    let color: Color

    var body: some View {
        Canvas { context, size in
            var state = seed &* 6364136223846793005 &+ 1442695040888963407
            func next() -> CGFloat {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((state >> 33) % 10_000) / 10_000
            }
            for _ in 0..<count {
                let x = next() * size.width, y = next() * size.height * 0.7
                let r = 0.6 + next() * 1.4
                context.opacity = 0.3 + Double(next()) * 0.7
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The opt-in moment: after your mile, tapping your own Today tile offers the
/// finish frame for your story. Nothing is posted until the user taps "Add to
/// my story"; "Post a photo instead" opens the composer.
///
/// Make it yours first: a live preview beside a theme, a route style and
/// Flamey on or off (`FinishFrameStyle`, remembered as next time's default).
/// The sheet is exactly as tall as its content.
struct AddFinishStorySheet: View {
    let stats: RunStatsInput
    let onAdded: () -> Void
    let onPostPhoto: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPosting = false
    @State private var errorText: String?
    /// What friends will get: the uploaded points, trimmed the way the server
    /// trims them. Nil draws Flamey, which is exactly what they'd see.
    @State private var coordinates: [CLLocationCoordinate2D]?
    /// "running"/"walking" for the preview's noun; the posted frame reads the
    /// type from the server's workout row.
    @State private var workoutType: String?
    /// Why friends will see something different from this preview, if they will.
    @State private var friendsNote: String?
    @State private var style = FinishFrameStyle.lastUsed
    @State private var contentHeight: CGFloat = 640

    private var ownLook: FlameyLook? { FeedCardFlamey.look(authorFlamey: nil, isOwn: true) }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Add today's finish to your story?")
                    .madFont(size: 19, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("Friends see it for 24 hours. Only if you add it.")
                    .madFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 22)
            .padding(.horizontal, 24)

            HStack(alignment: .center, spacing: 16) {
                StoryFinishFrame(stats: stats.snapshot, coordinates: coordinates,
                                 workoutType: workoutType, style: style,
                                 flameyLook: ownLook, still: true)
                    .frame(width: 168, height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                    .animation(.easeInOut(duration: 0.25), value: style)
                    .accessibilityLabel("Preview of your story")

                VStack(alignment: .leading, spacing: 16) {
                    controlGroup("THEME") {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 10), count: 3),
                                  alignment: .leading, spacing: 10) {
                            ForEach(FinishFrameStyle.Theme.allCases) { theme in
                                themeSwatch(theme)
                            }
                        }
                    }
                    controlGroup("ROUTE") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(FinishFrameStyle.RouteStyle.allCases) { route in
                                routeChip(route)
                            }
                        }
                    }
                    Toggle(isOn: $style.flamey.animation(.easeInOut(duration: 0.2))) {
                        Text("Flamey")
                            .madFont(size: 14, weight: .heavy, design: .rounded, maxScale: 1.2)
                            .foregroundColor(.white)
                    }
                    .tint(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)

            if let friendsNote {
                Label(friendsNote, systemImage: "eye")
                    .madFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 24)
            }

            if let errorText {
                Text(errorText)
                    .madFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundColor(MADTheme.Colors.madRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 10) {
                Button {
                    Task { await add() }
                } label: {
                    HStack(spacing: 8) {
                        if isPosting { ProgressView().tint(.white) }
                        Text("Add to my story")
                            .madFont(size: 16, weight: .heavy, design: .rounded, maxScale: 1.3)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(MADTheme.Colors.madRed))
                }
                .buttonStyle(.plain)
                .disabled(isPosting)

                Button {
                    dismiss()
                    onPostPhoto()
                } label: {
                    Text("Post a photo instead")
                        .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .disabled(isPosting)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.09, green: 0.05, blue: 0.07).ignoresSafeArea())
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .madTypeCap(.madCardCap)
        .task { await loadRoute() }
    }

    private func controlGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.2)
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.5))
            content()
        }
    }

    private func themeSwatch(_ theme: FinishFrameStyle.Theme) -> some View {
        let selected = style.theme == theme
        return Button {
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.2)) { style.theme = theme }
        } label: {
            ZStack {
                Circle().fill(LinearGradient(colors: theme.background, startPoint: .top, endPoint: .bottom))
                Circle()
                    .trim(from: 0.1, to: 0.6)
                    .stroke(LinearGradient(colors: theme.route, startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(8)
            }
            .frame(width: 34, height: 34)
            .overlay(Circle().strokeBorder(selected ? Color.white : Color.white.opacity(0.15), lineWidth: selected ? 2.5 : 1))
            .scaleEffect(selected ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func routeChip(_ route: FinishFrameStyle.RouteStyle) -> some View {
        let selected = style.route == route
        return Button {
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.2)) { style.route = route }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: route.icon)
                    .font(.system(size: 11, weight: .bold))
                Text(route.name)
                    .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.2)
                    .lineLimit(1)
            }
            .foregroundColor(selected ? Color(red: 0.10, green: 0.05, blue: 0.07) : .white.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func loadRoute() async {
        guard let id = stats.workoutId,
              let workout = HealthKitManager.shared.cachedWorkouts.first(where: { $0.uuid.uuidString == id })
        else { return }
        workoutType = workout.workoutActivityType == .running ? "running" : "walking"
        // A stealth route never leaves the phone, so even your own posted story
        // has no map. The preview shows that instead of promising one.
        if StealthModeStore.shared.isStealth(workout) {
            friendsNote = "Stealth walk: friends won't see a route. They'll see Flamey and your stats, like this."
            return
        }
        let full = await WorkoutSyncService.shared.uploadableRoute(for: workout)
        coordinates = RoutePrivacyTrim.friendsView(full, workoutId: id)
        friendsNote = noteForFriends(full: full, friendsLine: coordinates)
    }

    private func noteForFriends(
        full: [CLLocationCoordinate2D]?,
        friendsLine: [CLLocationCoordinate2D]?
    ) -> String? {
        guard let full, full.count >= 2 else { return nil }
        if !NotificationPreferences.load().shareRouteMaps {
            return "Show route maps is off, so friends won't see a route. They'll see Flamey and your stats, like this."
        }
        guard let friendsLine else {
            return "Friends won't see a route. This walk stays too close to its start and end to keep them hidden, so they'll see Flamey and your stats, like this."
        }
        return friendsLine.count < full.count
            ? "This is what friends will see, with your start and end hidden."
            : "This is what friends will see."
    }

    private func add() async {
        isPosting = true
        errorText = nil
        do {
            try await RunPostService.addFinishCardToStory(stats: stats, style: style)
            style.remember()
            MADHaptics.success()
            isPosting = false
            dismiss()
            onAdded()
        } catch {
            isPosting = false
            errorText = "Couldn't add it right now. Check your connection and try again."
        }
    }
}
