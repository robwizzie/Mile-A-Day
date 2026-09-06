import SwiftUI
import HealthKit
import CoreLocation

/// Session cache of workouts' HealthKit GPS traces, keyed by workout UUID.
///
/// The past-workouts screen draws a map per outdoor workout in a lazy list, so
/// the SAME trace is asked for every time a row scrolls back into view or the
/// user re-picks a day — and reading an `HKWorkoutRoute` is a batched
/// enumeration of every fix, not a lookup. A written route never changes, so
/// one read per workout per process is all there is to do.
///
/// An EMPTY result is cached too, and that's the entry that earns this: indoor
/// and manually-entered workouts are the common case, and they'd otherwise be
/// re-probed forever because there is nothing to remember about them.
@MainActor
final class WorkoutRouteCache {
    static let shared = WorkoutRouteCache()

    private var traces: [String: [CLLocationCoordinate2D]] = [:]
    /// De-dupes concurrent asks for one workout — the calendar's day list and
    /// a detail sheet opened from it can both want the same trace at once.
    private var inFlight: [String: Task<[CLLocationCoordinate2D], Never>] = [:]

    private init() {}

    private func coordinates(
        for workout: HKWorkout,
        using manager: HealthKitManager
    ) async -> [CLLocationCoordinate2D] {
        let key = workout.uuid.uuidString
        if let hit = traces[key] { return hit }
        if let running = inFlight[key] { return await running.value }
        let task = Task { () -> [CLLocationCoordinate2D] in
            let locations = await manager.fetchAllRouteLocations(for: workout)
            return locations.map(\.coordinate)
        }
        inFlight[key] = task
        let coords = await task.value
        traces[key] = coords
        inFlight.removeValue(forKey: key)
        return coords
    }

    /// Reads a list of workouts' traces ONE AT A TIME, handing each one back as
    /// it lands so the rows fill in as they resolve rather than all at the end.
    ///
    /// Sequential on purpose: each read is a batched HealthKit query over every
    /// GPS fix of a workout, and ten of those fired at once is how a scroll
    /// stutters. Only routes worth drawing (2+ points) are reported.
    func loadTraces(
        for workouts: [HKWorkout],
        using manager: HealthKitManager,
        onEach: (String, [CLLocationCoordinate2D]) -> Void
    ) async {
        for workout in workouts {
            if Task.isCancelled { return }
            let coords = await coordinates(for: workout, using: manager)
            guard coords.count >= 2 else { continue }
            onEach(workout.uuid.uuidString, coords)
        }
    }
}

/// A past workout's route, drawn where the workout is LISTED.
///
/// The trace has been on the phone the whole time — HealthKit keeps one for
/// every outdoor walk, ours or another app's — but the only doors to it were a
/// post's card and the workout detail sheet, so an old outdoor walk with no
/// post read as a walk with no map. This is the same Route Art face the feed
/// draws (`RouteArtView`, the default route face everywhere) at list scale,
/// with the one flyover entry the app uses on every surface
/// (`FlyoverChipButton`).
///
/// Presentational on purpose — the coordinates come from the HOST, which loads
/// them through `WorkoutRouteCache`. A card that renders nothing until its own
/// `.task` fills it in is the EmptyView-lifecycle trap (ios.md): no body, no
/// `.task`, no coordinates, forever.
///
/// Deliberately NOT pinch-zoomable and with no Map/Art toggle: those live one
/// tap away in the detail sheet, and a zoom host here would eat the flyover
/// chip's taps and the row's own.
struct WorkoutRoutePreviewCard: View {
    let workout: HKWorkout
    let coordinates: [CLLocationCoordinate2D]
    /// Tapping the map does what tapping the row does. The map is part of the
    /// row, and a dead map under a live row reads as a broken card.
    var onOpen: (() -> Void)? = nil
    var height: CGFloat = 150

    /// Item-based, per the fullScreenCover rule in ios.md.
    @State private var flyoverLaunch: FlyoverLaunch?
    /// Splits cost a HealthKit round trip per workout and feed nothing but the
    /// flight's "MILE 2 · 9:41" toasts, so they're read when someone actually
    /// flies rather than for every row that happens to have a route.
    @State private var isPreparingFlyover = false

    private var workoutColor: Color {
        MADTheme.workoutColor(workout.workoutActivityType.madTypeKey)
    }

    private var distanceMiles: Double { workout.madDistanceMiles }

    /// Recorded in Stealth Mode: the route is on this phone and nowhere else,
    /// and the badge says so — the same words the detail sheet's hero uses.
    private var isStealth: Bool {
        StealthModeStore.shared.isStealth(workout)
    }

    /// These are only ever the current user's own workouts.
    private var owner: RouteArtAvatar {
        RouteArtAvatar(
            name: UserManager.shared.currentUser.name,
            imageURL: UserManager.shared.currentUser.profileImageUrl
        )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
    }

    var body: some View {
        mapFace
            // Overlaid on the map AFTER its own tap target, the same rule the
            // feed card follows with its zoom host: whatever is added last is
            // what a tap on the chip actually reaches. The map is one
            // VoiceOver element by then, so the chip stays its own.
            .overlay(alignment: .topLeading) {
                flyoverChip.padding(10)
            }
            .overlay(alignment: .topTrailing) {
                if isStealth {
                    stealthBadge.padding(10)
                }
            }
            .fullScreenCover(item: $flyoverLaunch) { launch in
                RouteFlyoverPlayerView(launch: launch)
            }
    }

    private var mapFace: some View {
        RouteArtView(
            coordinates: coordinates,
            routeColor: workoutColor,
            authorAvatar: owner,
            paletteDate: workout.endDate
        )
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .contentShape(shape)
        .onTapGesture { onOpen?() }
        // A drawn line reads as nothing to VoiceOver, and a tap gesture on a
        // plain container is unreachable without a trait to activate it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Route map")
        .accessibilityAddTraits(onOpen == nil ? [] : .isButton)
        .accessibilityHint(onOpen == nil ? "" : "Opens this workout")
    }

    private var flyoverChip: some View {
        FlyoverChipButton(accent: workoutColor) { prepareAndLaunch() }
            .overlay {
                if isPreparingFlyover {
                    Capsule()
                        .fill(Color.black.opacity(0.4))
                        .overlay(ProgressView().tint(.white).scaleEffect(0.7))
                }
            }
            .allowsHitTesting(!isPreparingFlyover)
    }

    private var stealthBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 8, weight: .bold))
                .accessibilityHidden(true)
            Text("Only on this phone")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
        }
        .foregroundColor(.white.opacity(0.85))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    private func prepareAndLaunch() {
        guard coordinates.count >= 2, !isPreparingFlyover else { return }
        isPreparingFlyover = true
        Task {
            let splits = await SplitCalculator.calculateSplits(for: workout)
            isPreparingFlyover = false
            flyoverLaunch = FlyoverLaunch(
                coordinates: coordinates,
                workoutType: workout.workoutActivityType.madTypeKey,
                stats: flyoverStats,
                author: owner,
                splitBars: WorkoutSplitBar.bars(from: splits),
                // The tracker's receipt-floored figure — the number every
                // other surface shows for this workout, which is what the
                // odometer calibrates to.
                officialDistanceMiles: distanceMiles > 0 ? distanceMiles : nil
            )
        }
    }

    /// Pace divides by elapsed duration, the same arithmetic the row above the
    /// map prints — the HUD and the row must not disagree about one walk.
    private var flyoverStats: PostStats {
        let miles = distanceMiles
        let seconds = workout.duration
        return PostStats(
            distance: miles > 0 ? miles : nil,
            pace: miles > 0 && seconds > 0 ? seconds / miles : nil,
            duration: seconds > 0 ? seconds : nil,
            streak: nil,
            date: nil,
            calories: nil,
            steps: nil
        )
    }
}
