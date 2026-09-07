import SwiftUI
import HealthKit
import CoreLocation
import UIKit

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

/// A past workout's MEDIA, drawn where the workout is LISTED — its route, its
/// photo, or both.
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
struct WorkoutMediaPreviewCard: View {
    let workout: HKWorkout
    /// Empty (or a single point) when the walk left no trace — the card is
    /// then photo-only, and draws nothing at all without one either.
    var coordinates: [CLLocationCoordinate2D] = []
    /// The photo on this workout's own post, resolved by the HOST through
    /// `photoURL(for:)` — same one batched lookup that badges the row, so the
    /// badge and the picture can never disagree.
    var photoURL: URL? = nil
    /// Tapping the media does what tapping the row does. The map is part of the
    /// row, and a dead map under a live row reads as a broken card.
    var onOpen: (() -> Void)? = nil
    var height: CGFloat = 150

    /// Item-based, per the fullScreenCover rule in ios.md.
    @State private var flyoverLaunch: FlyoverLaunch?
    /// The map leads when there is one: this card exists because a walk's
    /// route had nowhere to be seen, and the picture is one tap away behind a
    /// thumbnail of itself rather than behind a word.
    @State private var showingPhoto = false
    /// Shared by the corner thumbnail and the full photo face, so flipping to
    /// the photo shows the bitmap the thumbnail already loaded.
    @State private var photo: UIImage?
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

    /// A trace worth drawing. One point is a fix, not a route.
    private var hasRoute: Bool { coordinates.count >= 2 }
    private var hasPhoto: Bool { photoURL != nil }

    /// Which face is up. The photo wins whenever there is no map to show, so a
    /// treadmill walk with a picture still gets a card.
    private var showsPhoto: Bool { hasPhoto && (showingPhoto || !hasRoute) }

    var body: some View {
        Group {
            if showsPhoto {
                photoFace
            } else if hasRoute {
                mapFace
            }
        }
        // Overlaid AFTER the face's own tap target, the same rule the feed
        // card follows with its zoom host: whatever is added last is what a
        // tap on a chip actually reaches. The face is one VoiceOver element by
        // then, so each control stays its own.
        .overlay(alignment: .topLeading) {
            if !showsPhoto, hasRoute {
                flyoverChip.padding(10)
            }
        }
        .overlay(alignment: .bottomLeading) {
            // Moved off the top-right corner, which the face switch now owns.
            if !showsPhoto, hasRoute, isStealth {
                stealthBadge.padding(10)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if hasPhoto, hasRoute {
                faceSwitch.padding(10)
            }
        }
        .fullScreenCover(item: $flyoverLaunch) { launch in
            RouteFlyoverPlayerView(launch: launch)
        }
    }

    /// The other face, in the same corner both ways round.
    ///
    /// On the map it is the PHOTO ITSELF at thumbnail size, not a word: the
    /// picture is the reason to tap, and a card that says "PHOTO" hides the
    /// very thing it is advertising. Coming back is a labelled pill instead —
    /// a map thumbnail would mean rendering the route twice for a 52pt square
    /// nobody is studying.
    @ViewBuilder
    private var faceSwitch: some View {
        Button {
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.22)) { showingPhoto.toggle() }
        } label: {
            if showingPhoto {
                HStack(spacing: 4) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 10, weight: .bold))
                        .accessibilityHidden(true)
                    Text("MAP")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .contentShape(Capsule())
            } else {
                FeedImageView(url: photoURL, loadedImage: $photo)
                    .frame(width: 52, height: 52)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showingPhoto ? "Show route map" : "Show photo")
    }

    private var photoFace: some View {
        FeedImageView(url: photoURL, loadedImage: $photo)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(shape)
            .onTapGesture { onOpen?() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Workout photo")
            .accessibilityAddTraits(onOpen == nil ? [] : .isButton)
            .accessibilityHint(onOpen == nil ? "" : "Opens this workout")
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

    /// The picture to preview for a workout, from its own post.
    ///
    /// ONE definition, called by every host: the "Photo" badge on the row and
    /// the thumbnail on the card were separately derived expressions in two
    /// list screens each, and a row badged "Photo" over a card with no picture
    /// (or the reverse) is the kind of disagreement nobody reports and
    /// everybody notices. An `is_auto` post is excluded on purpose — its media
    /// IS a rendered route card, so previewing it would draw the map twice.
    static func photoURL(for post: PostItem?) -> URL? {
        guard let post else { return nil }
        if let story = post.storyPhotoURL { return story }
        guard post.is_auto != true else { return nil }
        return post.mediaURL
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
