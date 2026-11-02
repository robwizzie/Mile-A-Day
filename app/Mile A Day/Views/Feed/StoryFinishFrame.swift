import SwiftUI
import CoreLocation
import HealthKit

/// The finish frame: a story with no photo, drawn live from the walk — the
/// route tracing itself, the distance rolling in, the streak — so a story can
/// say "done" without a picture. It only ever exists because the user added
/// it on purpose (the Today tile's "Add to my story", `AddFinishStorySheet`);
/// nothing posts one automatically.
///
/// Used full-screen in the story viewer and, still, as the preview in the
/// sheet that offers it.
struct StoryFinishFrame: View {
    let stats: PostStats?
    let coordinates: [CLLocationCoordinate2D]?
    let workoutType: String?
    /// Draw the finished frame with no motion (the sheet's preview, and
    /// Reduce Motion).
    var still: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var traced: CGFloat = 0
    @State private var shownMiles: Double = 0

    private var accent: Color { ActivityCardView.color(workoutType) }
    private var miles: Double { stats?.distance ?? 0 }
    private var animates: Bool { !still && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [Color(red: 0.23, green: 0.08, blue: 0.13), Color(red: 0.05, green: 0.02, blue: 0.03)],
                    center: UnitPoint(x: 0.5, y: 0.3),
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.8
                )

                VStack(spacing: 0) {
                    routeArea
                        .frame(height: geo.size.height * 0.36)
                        .padding(.horizontal, geo.size.width * 0.1)
                        .padding(.top, geo.size.height * 0.16)
                    Spacer(minLength: 12)
                    numbers
                    Spacer(minLength: 12)
                }
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
                withAnimation(.easeOut(duration: 1.8)) { traced = 1 }
                withAnimation(.easeOut(duration: 1.2).delay(0.4)) { shownMiles = miles }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var routeArea: some View {
        if let coordinates, coordinates.count >= 2 {
            RouteTraceShape(points: Self.normalize(coordinates))
                .trim(from: 0, to: traced)
                .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .shadow(color: accent.opacity(0.5), radius: 8)
        } else {
            // No route (indoor, maps off, stealth): the activity itself.
            Image(systemName: ActivityCardView.icon(workoutType, paceSecondsPerMile: stats?.pace))
                .font(.system(size: 72, weight: .bold))
                .foregroundColor(accent)
                .opacity(traced)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var numbers: some View {
        VStack(spacing: 6) {
            Text(shownMiles.distanceText)
                .font(.system(size: 64, weight: .black, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: shownMiles))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let streak = stats?.streak, streak > 0 {
                HStack(spacing: 6) {
                    StreakFlameChip(streak: streak, glyphSize: 14, numberSize: 16)
                    Text("day streak")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 24)
    }

    /// "mi · Walk · 13:42"
    private var subtitle: String {
        var parts = [DistanceUnits.current.abbreviation,
                     PostCardView.activityNoun(workoutType, pace: stats?.pace)]
        if let duration = stats?.duration, duration > 0 {
            let total = Int(duration.rounded())
            parts.append(total >= 3600
                         ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
                         : String(format: "%d:%02d", total / 60, total % 60))
        }
        return parts.joined(separator: " · ")
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

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        path.move(to: CGPoint(x: origin.x + points[0].x * side, y: origin.y + points[0].y * side))
        for p in points.dropFirst() {
            path.addLine(to: CGPoint(x: origin.x + p.x * side, y: origin.y + p.y * side))
        }
        return path
    }
}

/// The opt-in moment: after your mile, tapping your own Today tile offers the
/// finish frame for your story, with a preview. Nothing is posted until the
/// user taps "Add to my story"; "Post a photo instead" opens the composer.
struct AddFinishStorySheet: View {
    let stats: RunStatsInput
    let onAdded: () -> Void
    let onPostPhoto: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPosting = false
    @State private var errorText: String?
    /// The walk's own trace, for the preview (friends get the server's copy,
    /// trimmed by their privacy settings).
    @State private var coordinates: [CLLocationCoordinate2D]?
    /// "running"/"walking" for the preview's colour and noun; the posted
    /// frame reads the type from the server's workout row.
    @State private var workoutType: String?

    var body: some View {
        VStack(spacing: 18) {
            StoryFinishFrame(stats: stats.snapshot, coordinates: coordinates,
                             workoutType: workoutType, still: true)
                .frame(width: 150, height: 266)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .padding(.top, 24)

            VStack(spacing: 6) {
                Text("Add today's finish to your story?")
                    .madFont(size: 19, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("Friends see your route, distance and streak for 24 hours. Only if you add it.")
                    .madFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.09, green: 0.05, blue: 0.07).ignoresSafeArea())
        .madTypeCap(.madCardCap)
        .task { await loadRoute() }
    }

    private func loadRoute() async {
        guard let id = stats.workoutId,
              let workout = HealthKitManager.shared.cachedWorkouts.first(where: { $0.uuid.uuidString == id })
        else { return }
        workoutType = workout.workoutActivityType == .running ? "running" : "walking"
        await WorkoutRouteCache.shared.loadTraces(for: [workout], using: HealthKitManager.shared) { _, coords in
            coordinates = coords
        }
    }

    private func add() async {
        isPosting = true
        errorText = nil
        do {
            try await RunPostService.addFinishCardToStory(stats: stats)
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
