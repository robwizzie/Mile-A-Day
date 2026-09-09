import SwiftUI
import MapKit
import UIKit

// The route Flyover: a full-screen cinematic camera flight along the workout's
// GPS trace — overview swoop-in, a cruise that follows the line while the
// accent trail brightens and the runner's badge flies the tip, then a
// pull-back reveal of the whole route. Crew walks fly EVERYONE: each person's
// badge rides their own line, the HUD picks whose path the camera follows,
// identical paths are offset into side-by-side lanes, and the closing
// overview frames the whole crew.
//
// Geography exposure is identical to the existing map-on-tap: the player only
// ever opens where the viewer already holds the route coords. Playback pacing
// is synthesized (routes carry no timestamps) — constant ground speed,
// distance-scaled duration.

// MARK: - Launch payload

struct FlyoverCompanion: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
    let avatar: RouteArtAvatar?
    /// Their replay clock: seconds since THEIR first fix, one per coordinate,
    /// and that fix's epoch seconds. Nil (or a count that doesn't match the
    /// coordinates) means no clock — the engine falls back to its synthetic
    /// constant-speed flight for the whole crew.
    var pointTimes: [Double]? = nil
    var startedAt: Double? = nil
    /// This walker's RECORDED distance (`coauthors[].distance_miles`, the
    /// participant row's figure). Their polyline is despiked and simplified
    /// like everyone else's, so its raw arc length reads 1–3% short of the
    /// number their own card shows — the closing standings must not be the one
    /// place a friend's walk is quietly a hundredth shorter. Calibration is
    /// sanity-banded, so an out-of-band figure falls back to raw geo.
    var distanceMiles: Double? = nil
}

struct FlyoverLaunch: Identifiable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let workoutType: String?
    /// Optional chips for the HUD (pace/time). The odometer deliberately does
    /// NOT use `stats.distance`: on a daily-mile anchor that's the DAY's
    /// rollup while the route is one workout — the flight counts the track's
    /// own geographic miles instead (see the leg chip below for the day).
    let stats: PostStats?
    let author: RouteArtAvatar?
    var companions: [FlyoverCompanion] = []
    /// When the card's stats are a stitched day's rollup (`segment_count` > 1)
    /// the route is only the FINAL leg — the HUD says so, or the odometer
    /// "contradicts" the card it was launched from.
    var segmentCount: Int? = nil
    var dayDistanceMiles: Double? = nil
    /// Per-mile splits for the followed author's workout — passing mile
    /// markers flashes that mile's time ("MILE 2 · 9:41").
    var splitBars: [WorkoutSplitBar] = []
    /// The workout's OFFICIAL recorded distance (tracker receipt / server
    /// figure). The polyline is despiked, smoothed, simplified and
    /// downsampled, so its raw arc length reads ~1–3% short of the number
    /// the app shows everywhere else ("walked 1.01, flyover says 0.98") —
    /// when this is present the odometer and mile marks are scaled to it.
    var officialDistanceMiles: Double? = nil
    /// The author's replay clock (see `FlyoverCompanion.pointTimes`). With a
    /// clock for everyone on the flight, the replay runs on the walk's REAL
    /// time: each rider is where they actually were at that second and stops
    /// where they stopped, so an early finisher stands at the line while the
    /// rest come in.
    var pointTimes: [Double]? = nil
    var startedAt: Double? = nil
    /// Which day this leg is from, for a chained tour's HUD ("TUE · AUG 27").
    var legTitle: String? = nil
    /// Hype from the landing screen: you just WATCHED the run — the social
    /// action belongs right there. Nil for your own workouts (can't hype
    /// yourself) and surfaces with no hype wiring.
    var onHype: (() -> Void)? = nil
    /// Already hyped before the flight — the button lands in its done state.
    var initiallyHyped: Bool = false
}

extension FlyoverLaunch {
    /// The raw-workout twin of `forPost` — the feed's workout-card chip must
    /// carry the same calibration/stitched-day rules, and a second hand-rolled
    /// construction is how the two would drift.
    static func forEntry(_ entry: FeedEntry) -> FlyoverLaunch? {
        guard let coords = entry.routeCoordinates, coords.count >= 2 else { return nil }
        let stats = PostStats(
            distance: (entry.distance ?? 0) > 0 ? entry.distance : nil,
            pace: DisplayPace.secondsPerMile(
                distanceMiles: entry.distance ?? 0,
                movingSeconds: entry.moving_seconds,
                elapsedSeconds: entry.total_duration
            ),
            duration: entry.total_duration,
            streak: nil, date: nil,
            calories: entry.calories, steps: entry.steps
        )
        return FlyoverLaunch(
            coordinates: coords,
            workoutType: entry.workout_type,
            stats: stats,
            author: RouteArtAvatar(name: entry.displayName, imageURL: entry.profile_image_url),
            segmentCount: entry.segment_count,
            dayDistanceMiles: entry.distance,
            splitBars: WorkoutSplitBar.bars(from: entry.splits),
            officialDistanceMiles: (entry.segment_count ?? 1) <= 1 ? entry.distance : nil,
            pointTimes: entry.route_times,
            startedAt: entry.route_started_at
        )
    }

    /// ONE construction for a post's flyover — the card chip and the
    /// `?flyover=1` deep link must fly the identical launch. Nil when the
    /// post has nothing flyable. Hype wiring is the call site's (closures
    /// don't belong in a factory that deep links also use).
    static func forPost(_ post: PostItem) -> FlyoverLaunch? {
        let coords = post.routeCoordinates ?? []
        // Colours assigned across the WHOLE credited crew then filtered —
        // same rule as the card's legend (never colour the filtered list).
        let palette = CrewRoutePalette.companionColors(
            count: post.acceptedCoauthors.count,
            avoiding: ActivityCardView.color(post.workout_type)
        )
        let companions: [FlyoverCompanion] = post.acceptedCoauthors.enumerated()
            .compactMap { pair in
                guard let route = pair.element.routeCoordinates else { return nil }
                return FlyoverCompanion(
                    id: pair.element.user_id,
                    coordinates: route,
                    color: palette[pair.offset],
                    avatar: RouteArtAvatar(name: pair.element.displayName,
                                           imageURL: pair.element.profile_image_url),
                    pointTimes: pair.element.route_times,
                    startedAt: pair.element.route_started_at,
                    distanceMiles: pair.element.distance_miles
                )
            }
        guard coords.count >= 2 || !companions.isEmpty else { return nil }
        return FlyoverLaunch(
            coordinates: coords,
            workoutType: post.workout_type,
            stats: post.stats_snapshot,
            author: RouteArtAvatar(name: post.displayName, imageURL: post.profile_image_url),
            companions: companions,
            segmentCount: post.segment_count,
            dayDistanceMiles: post.stats_snapshot?.distance,
            splitBars: WorkoutSplitBar.bars(from: post.splits),
            officialDistanceMiles: (post.segment_count ?? 1) <= 1
                ? post.stats_snapshot?.distance : nil,
            pointTimes: post.route_times,
            startedAt: post.route_started_at
        )
    }
}

/// One followable person, in the exact order the engine builds its tracks —
/// derived in ONE place so the HUD picker's indices always match.
struct FlyoverPersonInfo: Identifiable {
    let id: String
    let name: String
    let imageURL: String?
    let color: Color
}

extension FlyoverLaunch {
    var flyablePeople: [FlyoverPersonInfo] {
        var out: [FlyoverPersonInfo] = []
        if FlyoverTrack(coordinates: coordinates).isFlyable {
            out.append(FlyoverPersonInfo(
                id: "author",
                name: author?.name ?? "Author",
                imageURL: author?.imageURL,
                color: ActivityCardView.color(workoutType)
            ))
        }
        for companion in companions
        where FlyoverTrack(coordinates: companion.coordinates).isFlyable {
            out.append(FlyoverPersonInfo(
                id: companion.id,
                name: companion.avatar?.name ?? "a friend",
                imageURL: companion.avatar?.imageURL,
                color: companion.color
            ))
        }
        return out
    }
}

/// Remembered playback rate ("flyoverSpeedV1"); falls back to 1×.
private func flyoverStoredSpeed() -> Double {
    let stored = UserDefaults.standard.double(forKey: "flyoverSpeedV1")
    return [0.25, 0.5, 1, 2].contains(stored) ? stored : 1
}

/// "0:12" under a minute reads oddly for a margin — "12s" under 60, m:ss over.
private func flyoverMarginText(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s < 60 { return "\(s)s" }
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// The payload behind a route slide's Share button — the finished art frame
/// as an image, handed to the system share sheet.
struct RouteSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Share chip, styled as FlyoverChipButton's sibling.
struct RouteShareChipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 10, weight: .bold))
                Text("Share")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
    }
}

/// One chained leg per route: plays each flight in order with a cumulative
/// odometer and a "ROUTE n OF m" chip — the "fly my week" tour.
struct WeeklyFlyoverPlayerView: View {
    let launches: [FlyoverLaunch]

    @State private var index = 0
    @State private var advanceTask: Task<Void, Never>?

    var body: some View {
        // `.id(index)` rebuilds the whole player per leg — fresh engine,
        // fresh prewarm, fresh flight.
        RouteFlyoverPlayerView(
            launch: launches[index],
            odometerBase: baseMiles(before: index),
            legLabel: legLabel,
            onPreviousLeg: index > 0 ? { jump(to: index - 1) } : nil,
            onNextLeg: index + 1 < launches.count ? { jump(to: index + 1) } : nil,
            onFinished: advance,
            showsReplay: index == launches.count - 1
        )
        .id(index)
        .onDisappear { advanceTask?.cancel() }
    }

    /// "TUE · AUG 27 · 2 OF 5": the DAY leads, because a week of loops looks
    /// alike from the air and "route 2" told you nothing.
    private var legLabel: String? {
        guard launches.count > 1 else { return launches.first?.legTitle }
        let day = launches[index].legTitle ?? "ROUTE"
        return "\(day) · \(index + 1) OF \(launches.count)"
    }

    /// Miles flown by the legs before this one — the leg's OFFICIAL figure
    /// when it has one (the flight's own odometer is calibrated to it), else
    /// the polyline's length. Recomputed from the index rather than
    /// accumulated, so stepping backwards stays honest.
    private func baseMiles(before index: Int) -> Double {
        launches.prefix(index).reduce(0) { sum, leg in
            sum + (leg.officialDistanceMiles ?? FlyoverTrack(coordinates: leg.coordinates).totalMiles)
        }
    }

    private func jump(to target: Int) {
        guard launches.indices.contains(target) else { return }
        advanceTask?.cancel()
        index = target
    }

    private func advance() {
        guard index + 1 < launches.count else { return }
        let finished = index
        advanceTask?.cancel()
        advanceTask = Task { @MainActor in
            // A beat on the finished overview before the next leg lifts off.
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled, index == finished else { return }
            index += 1
        }
    }
}

/// THE flyover entry, everywhere a route can fly: post cards (both faces),
/// raw workout cards, the walk detail, and the two workout detail sheets.
/// Deliberately loud — a filled pill in the workout's own colour with a
/// white play disc, not the black glass chip it used to be, which people
/// only found because they already knew it was there. Until the user has
/// EVER tapped one it also wears a one-shot glow pulse (transform/opacity on
/// a cached layer, suppressed under Reduce Motion).
struct FlyoverChipButton: View {
    /// The workout's colour (red runs, blue walks) — the pill's fill.
    var accent: Color = MADTheme.Colors.madRed
    let action: () -> Void

    private static let seenKey = "flyoverChipSeenV1"
    @State private var pulsing = false
    @State private var unseen = !UserDefaults.standard.bool(forKey: FlyoverChipButton.seenKey)

    var body: some View {
        Button {
            MADHaptics.tap()
            if unseen {
                unseen = false
                UserDefaults.standard.set(true, forKey: Self.seenKey)
            }
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(accent)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white))
                Text("FLYOVER")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(.white)
            }
            .padding(.leading, 5)
            .padding(.trailing, 13)
            .padding(.vertical, 5)
            .background(Capsule().fill(accent))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            .overlay(
                Capsule().stroke(Color.white.opacity(unseen ? (pulsing ? 0.0 : 0.85) : 0),
                                 lineWidth: 1.5)
                    .scaleEffect(pulsing ? 1.25 : 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play route flyover")
        .onAppear {
            guard unseen, !UIAccessibility.isReduceMotionEnabled else { return }
            // Off the appear commit (see FlameBuddyView): a repeatForever
            // started inside onAppear attaches to unrelated layout changes.
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
        }
    }
}

// MARK: - Geo track (MKMapPoint arc-length parameterization)

/// The flyover's twin of `RouteArtMetrics`, in map space: cumulative
/// MKMapPoint arc length per vertex (the SAME measure `MKPolylineRenderer`'s
/// `strokeEnd` clips by, so the drawn tip and the flying badge can never
/// disagree) plus cumulative geographic meters for the odometer, mile marks
/// and timing.
struct FlyoverTrack {
    let coordinates: [CLLocationCoordinate2D]
    private let mapPoints: [MKMapPoint]
    private let cumulativeMap: [Double]
    private let cumulativeMeters: [Double]
    let totalMapLength: Double
    let totalMeters: Double

    var isFlyable: Bool { coordinates.count >= 2 && totalMeters > 30 }
    var totalMiles: Double { totalMeters / 1609.344 }

    init(coordinates: [CLLocationCoordinate2D]) {
        let pts = coordinates.map(MKMapPoint.init)
        var cumMap: [Double] = []
        var cumMeters: [Double] = []
        cumMap.reserveCapacity(pts.count)
        cumMeters.reserveCapacity(pts.count)
        var mapDist = 0.0
        var meters = 0.0
        for (i, p) in pts.enumerated() {
            if i > 0 {
                mapDist += hypot(p.x - pts[i - 1].x, p.y - pts[i - 1].y)
                meters += pts[i - 1].distance(to: p)
            }
            cumMap.append(mapDist)
            cumMeters.append(meters)
        }
        self.coordinates = coordinates
        mapPoints = pts
        cumulativeMap = cumMap
        cumulativeMeters = cumMeters
        totalMapLength = mapDist
        totalMeters = meters
    }

    /// Coordinates shifted `meters` perpendicular to the local direction of
    /// travel — the "lanes" that keep a crew who walked the SAME path visible
    /// as side-by-side lines instead of one line drawn N times. Uses each
    /// point's neighbours for the local bearing, so the lane follows every
    /// bend. Invisible when routes genuinely differ (a few meters at flyover
    /// altitude), decisive when they don't.
    static func laneOffset(_ coordinates: [CLLocationCoordinate2D], meters: Double) -> [CLLocationCoordinate2D] {
        guard abs(meters) > 0.01, coordinates.count >= 2 else { return coordinates }
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(coordinates.count)
        for i in coordinates.indices {
            let prev = coordinates[max(i - 1, 0)]
            let next = coordinates[min(i + 1, coordinates.count - 1)]
            let a = MKMapPoint(prev), b = MKMapPoint(next)
            var dx = b.x - a.x, dy = b.y - a.y
            let length = hypot(dx, dy)
            guard length > 0.0000001 else {
                out.append(coordinates[i])
                continue
            }
            dx /= length
            dy /= length
            let scale = MKMapPointsPerMeterAtLatitude(coordinates[i].latitude)
            let p = MKMapPoint(coordinates[i])
            out.append(MKMapPoint(
                x: p.x + dy * meters * scale,
                y: p.y - dx * meters * scale
            ).coordinate)
        }
        return out
    }

    /// Interpolated map point at a fraction of the MAP arc length.
    private func mapPoint(atFraction fraction: Double) -> MKMapPoint {
        guard let first = mapPoints.first else { return MKMapPoint() }
        guard mapPoints.count > 1, totalMapLength > 0 else { return first }
        let target = min(max(fraction, 0), 1) * totalMapLength
        var lo = 0, hi = mapPoints.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulativeMap[mid] < target { lo = mid + 1 } else { hi = mid }
        }
        let i = max(lo, 1)
        let segment = cumulativeMap[i] - cumulativeMap[i - 1]
        let t = segment > 0 ? (target - cumulativeMap[i - 1]) / segment : 0
        let a = mapPoints[i - 1], b = mapPoints[i]
        return MKMapPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    func coordinate(atFraction fraction: Double) -> CLLocationCoordinate2D {
        mapPoint(atFraction: fraction).coordinate
    }

    /// MAP-length fraction of the point at `index`, `t` of the way toward the
    /// next one — how a per-point clock is turned into the same fraction
    /// `Path.trim`/`strokeEnd` clip by, so a timed rider stays welded to the
    /// drawn tip exactly like a synthetic one.
    func fraction(atPointIndex index: Int, toward t: Double) -> Double {
        guard totalMapLength > 0, !cumulativeMap.isEmpty else { return 0 }
        let i = min(max(index, 0), cumulativeMap.count - 1)
        let next = min(i + 1, cumulativeMap.count - 1)
        let at = cumulativeMap[i] + (cumulativeMap[next] - cumulativeMap[i]) * min(max(t, 0), 1)
        return min(max(at / totalMapLength, 0), 1)
    }

    /// A smooth resampling of the [from, to] fraction window — the pace-tinted
    /// trail segments are built from these so neighbouring segments share
    /// exact endpoints.
    func sampledCoordinates(fromFraction: Double, toFraction: Double, count: Int = 48) -> [CLLocationCoordinate2D] {
        guard toFraction > fromFraction, count >= 2 else { return [] }
        return (0..<count).map { i in
            let t = fromFraction + (toFraction - fromFraction) * Double(i) / Double(count - 1)
            return coordinate(atFraction: t)
        }
    }

    func metersTraveled(atFraction fraction: Double) -> Double {
        guard mapPoints.count > 1, totalMapLength > 0 else { return 0 }
        let target = min(max(fraction, 0), 1) * totalMapLength
        var lo = 0, hi = mapPoints.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulativeMap[mid] < target { lo = mid + 1 } else { hi = mid }
        }
        let i = max(lo, 1)
        let segment = cumulativeMap[i] - cumulativeMap[i - 1]
        let t = segment > 0 ? (target - cumulativeMap[i - 1]) / segment : 0
        return cumulativeMeters[i - 1] + (cumulativeMeters[i] - cumulativeMeters[i - 1]) * t
    }

    /// Compass bearing (degrees) of travel at `fraction`, looking
    /// `lookaheadMeters` further along the line.
    func bearing(atFraction fraction: Double, lookaheadMeters: Double) -> Double {
        guard totalMeters > 0 else { return 0 }
        let aheadFraction = min(1, fraction + lookaheadMeters / totalMeters)
        var a = mapPoint(atFraction: fraction)
        var b = mapPoint(atFraction: max(aheadFraction, fraction + 0.0005))
        if fraction >= 0.999 {
            // AT the line there is nothing ahead to look at, and two equal
            // points read as "north" — which swung the camera round the
            // moment a followed rider finished early. Look back along the
            // last stretch instead.
            b = mapPoint(atFraction: 1)
            a = mapPoint(atFraction: max(0, 1 - max(lookaheadMeters / totalMeters, 0.0005)))
        }
        let dx = b.x - a.x
        let dy = b.y - a.y
        guard dx != 0 || dy != 0 else { return 0 }
        // Map points grow x-east, y-SOUTH: north is -y.
        let radians = atan2(dx, -dy)
        let degrees = radians * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Whole-mile boundaries, each with its MAP-length fraction so the
    /// crossing matches the drawn tip exactly. `distanceScale` maps polyline
    /// meters onto OFFICIAL miles (see `officialDistanceMiles`), so the marks
    /// agree with the calibrated odometer.
    func mileMarks(limit: Int = 30, distanceScale: Double = 1) -> [(mile: Int, coordinate: CLLocationCoordinate2D, fraction: Double)] {
        guard mapPoints.count > 1, totalMeters > 0, totalMapLength > 0,
              distanceScale > 0 else { return [] }
        let wholeMiles = Int(totalMeters * distanceScale / 1609.344)
        guard wholeMiles >= 1 else { return [] }
        var out: [(Int, CLLocationCoordinate2D, Double)] = []
        var index = 1
        for mile in 1...min(wholeMiles, limit) {
            let targetMeters = Double(mile) * 1609.344 / distanceScale
            while index < mapPoints.count - 1, cumulativeMeters[index] < targetMeters {
                index += 1
            }
            let segMeters = cumulativeMeters[index] - cumulativeMeters[index - 1]
            let t = segMeters > 0 ? (targetMeters - cumulativeMeters[index - 1]) / segMeters : 0
            let a = mapPoints[index - 1], b = mapPoints[index]
            let point = MKMapPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            let mapAt = cumulativeMap[index - 1] + (cumulativeMap[index] - cumulativeMap[index - 1]) * t
            out.append((mile, point.coordinate, mapAt / totalMapLength))
        }
        return out
    }
}

/// One walker's clock over their track: seconds since THEIR first fix, one
/// per track coordinate, plus how long after the walk's earliest start they
/// set off. Turns a walk-clock second into an arc fraction of their line —
/// 0 before they started, 1 once they stopped, so a rider who finished first
/// stands at the line while the rest come in.
struct FlyoverPersonClock {
    let times: [Double]
    let offset: Double
    var duration: Double { times.last ?? 0 }
    var endsAt: Double { offset + duration }

    /// Seconds into THEIR walk at walk-clock second `walkSeconds`, clamped
    /// to [0, duration] — the HUD's elapsed readout for the followed rider.
    func ownElapsed(at walkSeconds: Double) -> Double {
        min(max(walkSeconds - offset, 0), duration)
    }

    func arcFraction(track: FlyoverTrack, at walkSeconds: Double) -> Double {
        let local = walkSeconds - offset
        guard local > 0, times.count >= 2, duration > 0 else { return 0 }
        guard local < duration else { return 1 }
        var lo = 0, hi = times.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if times[mid] < local { lo = mid + 1 } else { hi = mid }
        }
        let i = max(lo, 1)
        let span = times[i] - times[i - 1]
        let t = span > 0 ? (local - times[i - 1]) / span : 1
        return track.fraction(atPointIndex: i - 1, toward: t)
    }
}

// MARK: - Player

enum FlyoverPhase: Equatable {
    /// Tiles are streaming in — the flight is held (behind an opaque cover)
    /// while the engine prewarms the cruise corridor, so the swoop never
    /// plays over blurry half-loaded imagery.
    case loading
    case intro, cruise, outro, finished
}

struct FlyoverTick {
    let phase: FlyoverPhase
    /// The shared CLOCK fraction (what the scrubber shows) — on a timed
    /// flight the followed rider's arc fraction can lag or lead it.
    let fraction: Double
    let miles: Double
    /// Timed flights only: seconds into the FOLLOWED rider's own walk,
    /// frozen at their finish once they've stopped. Nil on synthetic flights.
    var elapsedSeconds: Double? = nil
    /// Set on the frame a rider crosses their own finish (timed flights) —
    /// the HUD flashes it: "MegsMiles finished first · 31:04 · 2:10 ahead
    /// of Aaron". The badge on the map gets its check the same frame.
    var notice: FlyoverNotice? = nil
    /// Set only on the frame a mile marker drops AND a split time exists for
    /// it — the HUD flashes it as a toast.
    var milestone: FlyoverMilestone? = nil
    /// Everyone on the walk, in the order they finished — carried on the outro
    /// and finished ticks so the closing card is already on screen as the
    /// camera pulls out. Empty on a solo flight, where the HUD's own odometer
    /// and chips already say all of this.
    var standings: [FlyoverStanding] = []
}

/// One walker in the closing standings: how far they went, how long they took,
/// and how far behind the first one home they were.
///
/// The finish notices that flash mid-flight are one rider at a time and gone in
/// three seconds — by the landing there was nothing left on screen saying who
/// actually won the walk or by how much.
struct FlyoverStanding: Identifiable, Equatable {
    let id: String
    /// Position in whatever the standings are ordered by — finishing time on a
    /// timed flight, distance otherwise.
    let place: Int
    let name: String
    let imageURL: String?
    let color: Color
    let distanceMiles: Double?
    /// How long THIS walker took. Nil on a synthetic (clockless) flight, which
    /// is what `isTimed` below is read from.
    let seconds: Double?
    /// Seconds behind the first finisher. Nil for the winner, for anyone tied
    /// with them, and on an untimed flight.
    let behindSeconds: Double?
    let isFollowed: Bool

    static func isTimed(_ standings: [FlyoverStanding]) -> Bool {
        standings.contains { $0.seconds != nil }
    }
}

struct FlyoverMilestone: Equatable {
    let mile: Int
    let text: String
}

struct FlyoverNotice: Equatable {
    let icon: String
    let text: String
}

struct RouteFlyoverPlayerView: View {
    let launch: FlyoverLaunch
    /// Weekly chaining: miles already flown by earlier legs — added to the
    /// odometer so the week accumulates across routes.
    var odometerBase: Double = 0
    /// "TUE · AUG 27 · 2 OF 5" chip when part of a chained tour.
    var legLabel: String? = nil
    /// Chained tour navigation: chevrons either side of the leg chip. Nil on a
    /// single flight (no chevron drawn).
    var onPreviousLeg: (() -> Void)? = nil
    var onNextLeg: (() -> Void)? = nil
    /// Fired once each time the flight lands — the weekly wrapper advances on
    /// it.
    var onFinished: (() -> Void)? = nil
    /// False on a chained tour's non-final legs: the wrapper auto-advances
    /// 1.6s after landing, and a Replay tapped in that window would race the
    /// advance timer (replay starts, tour yanks to the next leg anyway).
    var showsReplay: Bool = true
    @Environment(\.dismiss) private var dismiss

    @State private var phase: FlyoverPhase = .loading
    @State private var fraction: Double = 0
    @State private var miles: Double = 0
    /// Timed flights: the followed rider's own running time (see
    /// `FlyoverTick.elapsedSeconds`). Nil ⇒ the static time chip instead.
    @State private var elapsedSeconds: Double? = nil
    @State private var replayTrigger = 0
    @State private var paused = false
    /// Playback rate — remembered across flights (someone who prefers ½×
    /// prefers it tomorrow too). All options are laid out at once in the HUD.
    @State private var speed: Double = flyoverStoredSpeed()
    /// Whose path the camera follows — index into `people`.
    @State private var followedIndex = 0
    /// The progress line is a scrubber: drag anywhere on the flight.
    @State private var isScrubbing = false
    @State private var scrubFraction: Double = 0
    @State private var scrubSeq = 0
    /// The mile-split toast, cleared by its own task after a beat.
    @State private var mileToast: FlyoverMilestone?
    @State private var toastSeq = 0
    /// A rider crossing their line (timed flights) — same lifetime as the
    /// mile toast, its own slot so the two never fight over one capsule.
    @State private var noticeToast: FlyoverNotice?
    @State private var noticeSeq = 0
    /// The closing standings — everyone on the walk, in the order they
    /// finished. Empty until the outro, and empty for a solo flight.
    @State private var standings: [FlyoverStanding] = []
    /// One adoption ping per player open, fired at first takeoff.
    @State private var hasLoggedPlay = false
    @State private var didNotifyFinish = false
    /// Hyped from THIS screen (or before the flight) — flips the button done.
    @State private var didHype = false
    private static let speeds: [Double] = [0.25, 0.5, 1, 2]

    private var people: [FlyoverPersonInfo] { launch.flyablePeople }

    private func legChevron(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard enabled else { return }
            MADHaptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(.white.opacity(enabled ? 0.9 : 0.25))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
    private var accent: Color { ActivityCardView.color(launch.workoutType) }
    private var followedColor: Color {
        people.indices.contains(followedIndex) ? people[followedIndex].color : accent
    }

    private func speedLabel(_ value: Double) -> String {
        if value == 0.25 { return "¼×" }
        if value == 0.5 { return "½×" }
        if value == 2 { return "2×" }
        return "1×"
    }

    var body: some View {
        ZStack {
            FlyoverMapView(launch: launch, replayTrigger: replayTrigger,
                           paused: paused, speed: speed,
                           followedIndex: followedIndex,
                           scrubSeq: scrubSeq, scrubFraction: scrubFraction,
                           scrubActive: isScrubbing) { tick in
                let wasLoading = phase == .loading
                phase = tick.phase
                fraction = tick.fraction
                miles = tick.miles
                elapsedSeconds = tick.elapsedSeconds
                if let milestone = tick.milestone {
                    showToast(milestone)
                }
                if let notice = tick.notice {
                    showNotice(notice)
                }
                // Carried on the outro tick too, so the card is already up as
                // the camera pulls out rather than popping in after it lands.
                if !tick.standings.isEmpty || tick.phase == .cruise || tick.phase == .intro {
                    standings = tick.standings
                }
                if wasLoading, tick.phase == .intro, !hasLoggedPlay {
                    hasLoggedPlay = true
                    TelemetryService.record("flyover_play")
                }
                if tick.phase == .finished, !didNotifyFinish {
                    didNotifyFinish = true
                    onFinished?()
                } else if tick.phase != .finished {
                    didNotifyFinish = false
                }
            }
            .ignoresSafeArea()

            // Opaque while loading: the engine is sweeping the camera along
            // the route to prewarm tiles, which must not read as glitching.
            if phase == .loading {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.09, green: 0.09, blue: 0.12), .black],
                        startPoint: .top, endPoint: .bottom
                    )
                    RadialGradient(colors: [accent.opacity(0.35), .clear],
                                   center: .init(x: 0.5, y: 0.4),
                                   startRadius: 10, endRadius: 320)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }

            // Scrims so the HUD reads over any imagery.
            VStack {
                LinearGradient(colors: [.black.opacity(0.5), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 240)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                topBar
                Spacer()
                hud
            }
        }
        .animation(.easeOut(duration: 0.5), value: phase == .loading)
        .preferredColorScheme(.dark)
        .onChange(of: speed) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "flyoverSpeedV1")
        }
    }

    // MARK: - Closing standings

    private var showsStandings: Bool {
        !standings.isEmpty && (phase == .outro || phase == .finished)
    }

    /// Who finished when, how far they went, and by how much. The mid-flight
    /// finish notices are one rider at a time and gone in three seconds, so by
    /// the landing nothing on screen said who won the walk or by how much —
    /// which is the whole thing a crew watches a replay to find out.
    ///
    /// Distances read in miles to match the odometer directly below it; the
    /// flyover is a mile-only screen throughout.
    @ViewBuilder
    private var finishStandingsCard: some View {
        if showsStandings {
            let timed = FlyoverStanding.isTimed(standings)
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: timed ? "flag.checkered" : "figure.walk")
                        .font(.system(size: 9, weight: .black))
                        .accessibilityHidden(true)
                    Text(timed ? "FINISH ORDER" : "ON THIS WALK")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(1.4)
                }
                .foregroundColor(.white.opacity(0.55))

                VStack(spacing: 6) {
                    ForEach(standings) { standing in
                        standingRow(standing, timed: timed)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.52))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    private func standingRow(_ standing: FlyoverStanding, timed: Bool) -> some View {
        HStack(spacing: 9) {
            standingLeading(standing, timed: timed)

            AvatarView(name: standing.name, imageURL: standing.imageURL, size: 26)
                .overlay(Circle().stroke(standing.color, lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 1) {
                Text(standing.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(standingDetail(standing))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            standingGap(standing, timed: timed)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        // Whoever the camera was following is marked, so a crew of four can
        // find their own line in the card without counting avatars.
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(standing.isFollowed ? standing.color.opacity(0.2) : Color.clear)
        )
    }

    /// A rank badge only when the order is a real RESULT. An untimed flight is
    /// synthetic — everyone drawn at a constant share of one clock — so a "1st"
    /// there would be the order the tracks were built in wearing a medal.
    @ViewBuilder
    private func standingLeading(_ standing: FlyoverStanding, timed: Bool) -> some View {
        if timed {
            let medal: Color = standing.place == 1
                ? .yellow
                : (standing.place == 2 ? Color(white: 0.8) : (standing.place == 3 ? .orange : .white.opacity(0.22)))
            Text("\(standing.place)")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(standing.place <= 3 ? .black : .white.opacity(0.8))
                .frame(width: 20, height: 20)
                .background(Circle().fill(medal))
                .fixedSize()
        } else {
            Circle()
                .fill(standing.color)
                .frame(width: 8, height: 8)
                .frame(width: 20)
                .accessibilityHidden(true)
        }
    }

    private func standingDetail(_ standing: FlyoverStanding) -> String {
        var parts: [String] = []
        if let miles = standing.distanceMiles, miles > 0 {
            parts.append("\(miles.milesText) mi")
        }
        if let seconds = standing.seconds, seconds > 0 {
            parts.append(RunStatsStickerView.durationText(seconds))
        }
        return parts.joined(separator: " · ")
    }

    /// How far off this walker finished. The winner gets the flag; everyone
    /// else gets the gap, which is the number a crew actually argues about.
    @ViewBuilder
    private func standingGap(_ standing: FlyoverStanding, timed: Bool) -> some View {
        if timed, let behind = standing.behindSeconds, behind >= 1 {
            Text("+\(flyoverMarginText(behind))")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .fixedSize()
                .accessibilityLabel("\(flyoverMarginText(behind)) behind")
        } else if timed, standing.place == 1 {
            HStack(spacing: 4) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 9, weight: .black))
                    .accessibilityHidden(true)
                Text("FIRST")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.yellow))
            .fixedSize()
        } else if timed {
            // Tied with the leader to the second — say so rather than showing
            // an empty slot that reads as missing data.
            Text("TIED")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .fixedSize()
        }
    }

    private func showToast(_ milestone: FlyoverMilestone) {
        toastSeq += 1
        let seq = toastSeq
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            mileToast = milestone
        }
        Task {
            try? await Task.sleep(for: .milliseconds(2400))
            if toastSeq == seq {
                withAnimation(.easeOut(duration: 0.4)) { mileToast = nil }
            }
        }
    }

    private func showNotice(_ notice: FlyoverNotice) {
        noticeSeq += 1
        let seq = noticeSeq
        MADHaptics.success()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            noticeToast = notice
        }
        Task {
            try? await Task.sleep(for: .milliseconds(3200))
            if noticeSeq == seq {
                withAnimation(.easeOut(duration: 0.4)) { noticeToast = nil }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: ActivityCardView.icon(launch.workoutType))
                    .font(.system(size: 12, weight: .bold))
                Text("\(ActivityCardView.verb(launch.workoutType).uppercased()) · FLYOVER")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundColor(accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.black.opacity(0.45)))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var hud: some View {
        VStack(spacing: 12) {
            if phase == .loading {
                HStack(spacing: 8) {
                    ProgressView().tint(.white.opacity(0.8))
                    Text("PREPARING FLYOVER")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.45)))
            }

            // Crew picker: whose path the camera follows. Only when there is
            // actually a crew to pick from.
            if people.count > 1, phase != .loading {
                HStack(spacing: 10) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                        Button {
                            followedIndex = index
                        } label: {
                            AvatarView(name: person.name, imageURL: person.imageURL, size: 30)
                                .overlay(
                                    Circle().stroke(
                                        index == followedIndex ? person.color : Color.white.opacity(0.25),
                                        lineWidth: index == followedIndex ? 2.5 : 1.5
                                    )
                                )
                                .opacity(index == followedIndex ? 1 : 0.65)
                                .scaleEffect(index == followedIndex ? 1.1 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.4)))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: followedIndex)
            }

            if let toast = mileToast {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 11, weight: .bold))
                    Text("MILE \(toast.mile) · \(toast.text)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .tracking(0.5)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule().fill(accent.opacity(0.85)))
                .shadow(color: accent.opacity(0.6), radius: 6)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }

            if let notice = noticeToast {
                HStack(spacing: 6) {
                    Image(systemName: notice.icon)
                        .font(.system(size: 11, weight: .bold))
                        .accessibilityHidden(true)
                    Text(notice.text)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule().fill(MADTheme.Colors.success.opacity(0.85)))
                .shadow(color: MADTheme.Colors.success.opacity(0.6), radius: 6)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }

            if let win = launch.stats?.ghostWin {
                HStack(spacing: 5) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("BEAT THE GHOST BY \(flyoverMarginText(win.margin))")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1)
                }
                .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.35))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.5)))
            }

            if let legLabel {
                // A chained tour: which day this is, and a chevron either
                // side to step through the week without waiting for a landing.
                HStack(spacing: 8) {
                    if onPreviousLeg != nil || onNextLeg != nil {
                        legChevron("chevron.left", enabled: onPreviousLeg != nil) { onPreviousLeg?() }
                    }
                    Text(legLabel)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.4)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                    if onPreviousLeg != nil || onNextLeg != nil {
                        legChevron("chevron.right", enabled: onNextLeg != nil) { onNextLeg?() }
                    }
                }
            }

            finishStandingsCard

            odometerBlock

            scrubberAndControls
        }
        .padding(.bottom, 26)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showsStandings)
    }

    /// The odometer, the stitched-day chip and the stat chips as ONE child of
    /// the HUD stack. Grouped so the HUD's own `VStack` stays at ten children:
    /// past that the whole block leans on the parameter-pack `buildBlock`, and
    /// this stack's children are long modifier chains that the type-checker
    /// then has to solve together.
    private var odometerBlock: some View {
        VStack(spacing: 12) {
            // The odometer — the FOLLOWED track's own geographic miles (plus
            // any earlier legs of a chained tour).
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                // The stats band's own formatter — which is the app's floor
                // (`milesText`) now that the band no longer rounds: this
                // number is compared against the card it was launched from,
                // and the two formatters put "1.04" on the map over a card
                // reading "1.03". Mid-flight it may read a whole mile a few
                // metres before the mark drops; the landing figure being the
                // card's figure is what matters.
                Text((odometerBase + miles).milesText)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                Text("MI")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }

            // A stitched day: the route is only the mile's FINAL leg, and the
            // card this launched from shows the day total — say so, or the
            // odometer reads as a miscalculation.
            if followedIndex == 0, (launch.segmentCount ?? 1) > 1,
               let day = launch.dayDistanceMiles, day > 0 {
                Text("FINAL LEG · \(day.milesText) MI DAY")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
            }

            // The standings card already carries every walker's distance and
            // time, the followed one included — showing the chips underneath it
            // is the same numbers twice, and on a small screen it is what
            // pushes the controls off the bottom.
            if let chips = statChips, !chips.isEmpty, !showsStandings {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.0) { chip in
                        HStack(spacing: 5) {
                            Image(systemName: chip.1)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(accent)
                            Text(chip.2)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                    }
                }
            }
        }
    }

    /// The scrubber, the speed row and the Replay/Hype (or pause) controls, as
    /// the HUD stack's last child. Same grouping reason as `odometerBlock`.
    private var scrubberAndControls: some View {
        VStack(spacing: 12) {
            // The progress line IS a scrubber: grab anywhere and drag to any
            // point of the walk — the camera, trail, badges and odometer all
            // jump with it, and playback resumes from wherever you let go.
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 4)
                    Capsule()
                        .fill(followedColor)
                        .frame(width: max(4, width * fraction), height: 4)
                        .shadow(color: followedColor.opacity(0.7), radius: 3)
                    Circle()
                        .fill(.white)
                        .frame(width: isScrubbing ? 18 : 12, height: isScrubbing ? 18 : 12)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                        .position(x: min(max(width * fraction, 7), width - 7),
                                  y: geo.size.height / 2)
                        .animation(.easeOut(duration: 0.15), value: isScrubbing)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Scrubbable once the flight exists — not while
                            // tiles prewarm or the intro swoop is framing.
                            guard phase != .loading, phase != .intro else { return }
                            isScrubbing = true
                            let f = min(max(value.location.x / width, 0), 1)
                            fraction = f
                            scrubFraction = f
                            scrubSeq += 1
                        }
                        .onEnded { _ in
                            guard isScrubbing else { return }
                            isScrubbing = false
                            scrubSeq += 1
                        }
                )
            }
            .frame(height: 26)
            .padding(.horizontal, 36)

            VStack(spacing: 10) {
                if phase != .loading {
                    // Every speed on screen at once — selected one wears the
                    // accent. Stays visible when finished so a replay can be
                    // queued up at a different pace.
                    HStack(spacing: 6) {
                        ForEach(Self.speeds, id: \.self) { option in
                            Button {
                                speed = option
                            } label: {
                                Text(speedLabel(option))
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 32)
                                    .background(
                                        Capsule().fill(speed == option
                                            ? accent.opacity(0.85)
                                            : Color.black.opacity(0.45))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if phase == .finished {
                    HStack(spacing: 10) {
                        if showsReplay {
                            Button {
                                replayTrigger += 1
                                paused = false
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("Replay")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(accent.opacity(0.85)))
                            }
                            .buttonStyle(.plain)
                        }
                        // You just watched the whole run — the kudos belongs
                        // right here, not two screens back.
                        if launch.onHype != nil {
                            Button {
                                guard !didHype, !launch.initiallyHyped else { return }
                                didHype = true
                                MADHaptics.action()
                                launch.onHype?()
                            } label: {
                                let done = didHype || launch.initiallyHyped
                                HStack(spacing: 6) {
                                    Image(systemName: done ? "checkmark" : "hands.clap.fill")
                                        .font(.system(size: 13, weight: .bold))
                                    Text(done ? "Hyped" : "Hype")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(done
                                    ? Color.white.opacity(0.18)
                                    : Color(red: 1.0, green: 0.62, blue: 0.1).opacity(0.9)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if phase != .loading {
                    Button {
                        paused.toggle()
                    } label: {
                        Image(systemName: paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var statChips: [(String, String, String)]? {
        var out: [(String, String, String)] = []
        // A timed replay counts the followed rider's OWN clock up as they
        // go and freezes it where they stopped — it replaces the static
        // total, which would otherwise sit beside it saying something else.
        if let e = elapsedSeconds {
            out.append(("elapsed", "stopwatch.fill", RunStatsStickerView.durationText(e)))
        }
        if let stats = launch.stats {
            if let p = stats.pace, p > 0 {
                out.append(("pace", "speedometer", "\(RunStatsStickerView.paceText(p)) /mi"))
            }
            if elapsedSeconds == nil, let d = stats.duration, d > 0 {
                out.append(("time", "clock.fill", RunStatsStickerView.durationText(d)))
            }
        }
        return out.isEmpty ? nil : out
    }
}

// MARK: - Map representable + flight engine

private struct FlyoverMapView: UIViewRepresentable {
    let launch: FlyoverLaunch
    let replayTrigger: Int
    let paused: Bool
    let speed: Double
    let followedIndex: Int
    let scrubSeq: Int
    let scrubFraction: Double
    let scrubActive: Bool
    let onTick: (FlyoverTick) -> Void

    func makeCoordinator() -> FlyoverEngine {
        FlyoverEngine(launch: launch, onTick: onTick)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        // HYBRID + FLAT, both on purpose. Flat: with `.realistic`, MapKit's
        // 3D terrain drapes OVER overlay polylines, so the trail sinks into
        // the ground at cruise pitch. Hybrid (not imagery): the pure-imagery
        // configuration does not reliably composite MKOverlay polylines at
        // all — annotations drew while every line stayed invisible — whereas
        // hybrid carries the vector layer overlays render through. POIs are
        // filtered so the cinematics aren't littered with pins.
        let config = MKHybridMapConfiguration(elevationStyle: .flat)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config
        map.isUserInteractionEnabled = false
        map.showsCompass = false
        map.delegate = context.coordinator
        context.coordinator.inViewUpdate = true
        defer { context.coordinator.inViewUpdate = false }
        context.coordinator.attach(to: map)
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Everything below runs DURING the SwiftUI view update. Any tick the
        // engine emits from here (a follow switch, a scrub seek) would write
        // the player's @State mid-update — "Modifying state during view
        // update, this will cause undefined behavior" — so the engine defers
        // emissions while this flag is up. Display-link and delegate-driven
        // ticks fire outside the update and stay synchronous.
        context.coordinator.inViewUpdate = true
        defer { context.coordinator.inViewUpdate = false }
        context.coordinator.setPaused(paused)
        context.coordinator.setSpeed(speed)
        context.coordinator.setFollowed(followedIndex)
        context.coordinator.applyScrub(seq: scrubSeq, fraction: scrubFraction, active: scrubActive)
        context.coordinator.replayIfNeeded(replayTrigger)
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: FlyoverEngine) {
        coordinator.stop()
        uiView.delegate = nil
    }
}

/// One rider or mile-mark pin, with its image prepared up front so `viewFor`
/// never renders SwiftUI mid-frame.
private final class FlyoverAnnotation: MKPointAnnotation {
    var preparedImage: UIImage?
    var isRider = false
}

/// The flight itself: a display link advancing a phase timeline, moving the
/// camera, the followed trail's `strokeEnd` and every badge from ONE
/// map-arc-length clock (the same weld-the-rider-to-the-tip principle as
/// `RouteArtMetrics` on the art canvas). Multi-person: each flyable person
/// gets a full casing+colour line and a rider badge advancing by the shared
/// fraction over their OWN track; only the FOLLOWED person carries the
/// progressive glow/bright-trail pair and the mile marks.
private final class FlyoverEngine: NSObject, MKMapViewDelegate {

    private struct Person {
        let color: UIColor
        let avatar: RouteArtAvatar?
        let track: FlyoverTrack
        /// Polyline meters → official miles (1 when unknown, e.g. companions).
        let distanceScale: Double
        /// The recorded figure the odometer lands on, when calibration was
        /// accepted — the number the card shows, kept as-is rather than
        /// reconstructed from `distanceScale`.
        let calibratedMiles: Double?
        let mileMarks: [(mile: Int, coordinate: CLLocationCoordinate2D, fraction: Double)]
        let annotation: FlyoverAnnotation
        /// Their real clock, on timed flights only (nil ⇒ synthetic).
        let clock: FlyoverPersonClock?
    }

    private enum OverlayRole {
        case casing
        case fullLine(UIColor)
        case glow(personIndex: Int, UIColor)
        case trail(personIndex: Int, UIColor)
        /// One whole-mile slice of the AUTHOR's trail, tinted by that mile's
        /// pace (fast = brighter) — the run's effort made visible as it draws.
        case trailSegment(segment: Int, UIColor)
    }

    private let launch: FlyoverLaunch
    private let onTick: (FlyoverTick) -> Void
    /// Raised by the representable around `makeUIView`/`updateUIView`. While
    /// up, `emit` hops to the next main-queue turn instead of calling
    /// `onTick` inline — the closure writes @State, which is undefined
    /// behavior from inside a view update.
    var inViewUpdate = false
    private var people: [Person] = []
    private let accent: UIColor
    /// Timed flights: the walk's length in real seconds, from the earliest
    /// start to the last finish across the crew. 0 on a synthetic flight.
    private var walkDuration: Double = 0
    private var isTimed: Bool { walkDuration > 0 }
    /// Per rider: has their clock run out at the current position? Flipping
    /// it swaps their badge for the checked one and raises the finish
    /// notice; a backward scrub or a replay flips it back (silently).
    private var finishedFlags: [Bool] = []
    private var pendingNotice: FlyoverNotice?

    private weak var mapView: MKMapView?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var elapsed: Double = 0
    private var handledReplay = 0
    private var finishedNotified = false
    private var flightStarted = false
    private var stopped = false
    private var speed: Double = 1
    private var awaitingRender = false
    private var followed = 0
    private var currentFraction: Double = 0
    private var scrubbing = false
    private var lastScrubSeq = 0
    /// The pause BUTTON's state, remembered through a scrub so letting go of
    /// the knob resumes only if the user hadn't paused.
    private var userPaused = false

    private var overlayRoles: [ObjectIdentifier: OverlayRole] = [:]
    private var glowRenderers: [Int: MKPolylineRenderer] = [:]
    private var trailRenderers: [Int: MKPolylineRenderer] = [:]
    /// Pace-tinted author trail: fraction range + renderer per whole-mile
    /// slice (plus a base-accent remainder). Empty = author draws the plain
    /// single trail like everyone else.
    private var authorSegmentRanges: [ClosedRange<Double>] = []
    private var authorSegmentRenderers: [Int: MKPolylineRenderer] = [:]
    private var mileAnnotations: [FlyoverAnnotation] = []
    private var droppedMiles = 0
    /// Split time per mile (author's workout) — flashed as the marker drops.
    private let splitByMile: [Int: String]
    private var pendingMilestone: FlyoverMilestone?

    private var smoothedHeading: Double = 0
    /// The fitted closing camera, resolved once when the outro starts so the
    /// blend walks toward a fixed target instead of a slightly different one
    /// every frame. Cleared on replay.
    private var outroTarget: MKMapCamera?
    /// Built once alongside `outroTarget` rather than per frame: the outro
    /// reports ~60 times and the standings don't move once everyone is home.
    /// Rebuilt when the followed rider changes, which is the only thing that
    /// alters them (`isFollowed`).
    private var cachedStandings: [FlyoverStanding] = []
    /// Throttle: overlay invalidation only at visible increments (~0.3% of
    /// the line) AND at most ~20 times a second (10 at 2×) — the rider badge
    /// still moves every frame. `MKPolylineRenderer` re-rasterises tiles on
    /// background threads; invalidated every frame at 2× the tiles landed at
    /// different `strokeEnd`s and the line broke up / vanished between them.
    private var lastStrokeFraction: Double = -1
    private var lastStrokeTime: CFTimeInterval = 0

    // Combined framing: the whole crew, so the closing overhead shows
    // everyone's path.
    private let allCoordinates: [CLLocationCoordinate2D]

    // Timeline: distance-scaled cruise between a swoop-in and a pull-back.
    private let introDuration = 2.2
    private let outroDuration = 2.4
    private var cruiseDuration: Double {
        // ~9s per mile of the LONGEST flyable track, so the shared fraction
        // clock is stable when the camera switches people mid-flight.
        let miles = people.map(\.track.totalMiles).max() ?? 0
        return min(36, max(9, miles * 9))
    }
    private var cruiseAltitude: Double {
        min(900, max(230, boundingDiagonalMeters * 0.30))
    }
    private var overviewAltitude: Double {
        min(7000, max(700, boundingDiagonalMeters * 2.1))
    }
    private var lookaheadMeters: Double {
        min(80, max(30, (followedTrack?.totalMeters ?? 0) * 0.03))
    }
    private var followedTrack: FlyoverTrack? {
        people.indices.contains(followed) ? people[followed].track : nil
    }

    init(launch: FlyoverLaunch, onTick: @escaping (FlyoverTick) -> Void) {
        self.launch = launch
        self.onTick = onTick
        self.accent = UIColor(ActivityCardView.color(launch.workoutType))
        self.allCoordinates = launch.coordinates + launch.companions.flatMap(\.coordinates)
        var byMile: [Int: String] = [:]
        for bar in launch.splitBars where (bar.partialDistance ?? 1) >= 0.95 {
            // Same mm:ss formatter as the HUD's pace chip — one format, one
            // screen.
            byMile[bar.mile] = RunStatsStickerView.paceText(bar.paceSeconds)
        }
        self.splitByMile = byMile
        super.init()
        // MUST mirror `FlyoverLaunch.flyablePeople` order exactly — the HUD
        // picker indexes into that list. Companions get side-by-side lanes
        // (±3m, ±6m …) so a crew that walked the SAME path stays readable.
        struct Rider {
            let coordinates: [CLLocationCoordinate2D]
            let color: UIColor
            let avatar: RouteArtAvatar?
            let officialMiles: Double?
            let times: [Double]?
            let startedAt: Double?
        }
        var riders: [Rider] = []
        if FlyoverTrack(coordinates: launch.coordinates).isFlyable {
            riders.append(Rider(
                coordinates: launch.coordinates, color: accent, avatar: launch.author,
                officialMiles: launch.officialDistanceMiles,
                times: launch.pointTimes, startedAt: launch.startedAt))
        }
        for companion in launch.companions {
            let raw = FlyoverTrack(coordinates: companion.coordinates)
            guard raw.isFlyable else { continue }
            riders.append(Rider(
                coordinates: companion.coordinates, color: UIColor(companion.color),
                avatar: companion.avatar, officialMiles: companion.distanceMiles,
                times: companion.pointTimes, startedAt: companion.startedAt))
        }

        // Real time only when EVERYONE on the flight has a clock that lines
        // up with their line — and, with more than one rider, an absolute
        // start to line the clocks up on. One rider without is the whole
        // flight synthetic: a crew half on real time and half on constant
        // speed would show people passing each other who never did.
        let clocks: [FlyoverPersonClock?]
        let aligned = riders.allSatisfy { rider in
            guard let times = rider.times, times.count == rider.coordinates.count,
                  times.count >= 2, (times.last ?? 0) > 0 else { return false }
            return riders.count == 1 || rider.startedAt != nil
        }
        if !riders.isEmpty, aligned {
            let earliest = riders.compactMap(\.startedAt).min() ?? 0
            clocks = riders.map { rider in
                FlyoverPersonClock(
                    times: rider.times ?? [],
                    offset: riders.count == 1 ? 0 : max(0, (rider.startedAt ?? earliest) - earliest))
            }
            walkDuration = clocks.compactMap { $0?.endsAt }.max() ?? 0
        } else {
            clocks = riders.map { _ in nil }
        }

        var built: [Person] = []
        for (index, rider) in riders.enumerated() {
            built.append(Self.person(
                coordinates: rider.coordinates,
                color: rider.color, avatar: rider.avatar, laneIndex: built.count,
                officialMiles: rider.officialMiles, clock: clocks[index]))
        }
        people = built
        finishedFlags = Array(repeating: false, count: built.count)
    }

    /// The finish line story for rider `index`, from the clocks everyone
    /// carries: first home says how far ahead of the next; everyone else
    /// how far behind the first.
    private func finishNotice(for index: Int) -> FlyoverNotice? {
        guard people.indices.contains(index), let clock = people[index].clock else { return nil }
        let name = people[index].avatar?.name ?? "Rider"
        let own = RunStatsStickerView.durationText(clock.duration)
        let others = people.enumerated().compactMap { pair -> (String, Double)? in
            guard pair.offset != index, let c = pair.element.clock else { return nil }
            return (pair.element.avatar?.name ?? "a friend", c.endsAt)
        }
        let earlier = others.filter { $0.1 < clock.endsAt }
        if earlier.isEmpty {
            var text = others.isEmpty ? "\(name) finished · \(own)" : "\(name) finished first · \(own)"
            if let next = others.min(by: { $0.1 < $1.1 }), next.1 > clock.endsAt {
                text += " · \(RunStatsStickerView.durationText(next.1 - clock.endsAt)) ahead of \(next.0)"
            }
            return FlyoverNotice(icon: "flag.checkered", text: text)
        }
        let first = earlier.min(by: { $0.1 < $1.1 })!
        return FlyoverNotice(
            icon: "flag.checkered",
            text: "\(name) finished · \(own) · \(RunStatsStickerView.durationText(clock.endsAt - first.1)) behind \(first.0)")
    }

    /// Where rider `index` is on THEIR line at shared-clock fraction `clock`:
    /// their real position on a timed flight, the clock itself otherwise.
    private func arcFraction(of index: Int, clock: Double) -> Double {
        guard isTimed, people.indices.contains(index), let personClock = people[index].clock
        else { return clock }
        return personClock.arcFraction(track: people[index].track,
                                       at: min(max(clock, 0), 1) * walkDuration)
    }

    private static func person(
        coordinates: [CLLocationCoordinate2D],
        color: UIColor,
        avatar: RouteArtAvatar?,
        laneIndex: Int,
        officialMiles: Double?,
        clock: FlyoverPersonClock?
    ) -> Person {
        // Lane 0 (author or first flyable) rides the true path; each later
        // lane alternates sides at 3m spacing.
        let magnitude = Double((laneIndex + 1) / 2) * 3.0
        let offset = laneIndex == 0 ? 0 : (laneIndex % 2 == 1 ? magnitude : -magnitude)
        let laned = FlyoverTrack.laneOffset(coordinates, meters: offset)
        let track = FlyoverTrack(coordinates: laned)
        // Calibrate to the recorded number, sanity-banded to the 1–3%
        // shortfall route simplification actually causes (plus GPS-vs-
        // pedometer slack). Deliberately TIGHT: an out-of-band ratio means
        // the official figure isn't THIS track's distance — most commonly a
        // friend's stitched-day anchor, whose row restates the DAY's rollup
        // over a final-leg route — and raw geo is the honest story then.
        var scale = 1.0
        var calibratedMiles: Double? = nil
        if let officialMiles, officialMiles > 0, track.totalMiles > 0 {
            let ratio = officialMiles / track.totalMiles
            if ratio > 0.9, ratio < 1.15 {
                scale = ratio
                calibratedMiles = officialMiles
            }
        }
        let annotation = FlyoverAnnotation()
        annotation.isRider = true
        annotation.coordinate = track.coordinate(atFraction: 0)
        return Person(
            color: color,
            avatar: avatar,
            track: track,
            distanceScale: scale,
            calibratedMiles: calibratedMiles,
            mileMarks: track.mileMarks(distanceScale: scale),
            annotation: annotation,
            clock: clock
        )
    }

    /// Whole-mile fraction windows tinted by that mile's pace: fastest mile
    /// brightest, slowest at base accent, remainder past the last whole mile
    /// at base. Empty (→ plain single trail) below two full-mile paces.
    private func buildAuthorPaceSegments() -> [(range: ClosedRange<Double>, color: UIColor)] {
        guard !people.isEmpty else { return [] }
        let marks = people[0].mileMarks
        var paceByMile: [Int: Double] = [:]
        for bar in launch.splitBars where (bar.partialDistance ?? 1) >= 0.95 {
            paceByMile[bar.mile] = bar.paceSeconds
        }
        let paces = marks.compactMap { paceByMile[$0.mile] }
        guard marks.count >= 1, paces.count >= 2,
              let fastest = paces.min(), let slowest = paces.max(), slowest > fastest
        else { return [] }

        var out: [(ClosedRange<Double>, UIColor)] = []
        var lower = 0.0
        for mark in marks {
            guard mark.fraction > lower else { continue }
            let color: UIColor
            if let pace = paceByMile[mark.mile] {
                // 0 = slowest (base accent), 1 = fastest (lifted toward white).
                let heat = (slowest - pace) / (slowest - fastest)
                color = Self.lifted(accent, toward: .white, amount: 0.12 + 0.38 * heat)
            } else {
                color = accent
            }
            out.append((lower...mark.fraction, color))
            lower = mark.fraction
        }
        if lower < 1 { out.append((lower...1.0, accent)) }
        return out
    }

    private static func lifted(_ base: UIColor, toward target: UIColor, amount: CGFloat) -> UIColor {
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        target.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        let t = min(max(amount, 0), 1)
        return UIColor(red: br + (tr - br) * t, green: bg + (tg - bg) * t,
                       blue: bb + (tb - bb) * t, alpha: 1)
    }

    // MARK: Setup

    @MainActor
    func attach(to map: MKMapView) {
        mapView = map
        guard !people.isEmpty else {
            // Nothing flyable: park on whatever there is and report done.
            let center = allCoordinates.first ?? CLLocationCoordinate2D()
            map.setRegion(MKCoordinateRegion(center: center,
                                             latitudinalMeters: 800,
                                             longitudinalMeters: 800), animated: false)
            finishedNotified = true
            // `attach` runs inside `makeUIView`; `emit` defers for us.
            emit(FlyoverTick(phase: .finished, fraction: 1, miles: 0))
            return
        }

        // Every person's full line (casing under colour), then the
        // progressive pairs — one per person, only the followed one visible.
        // The AUTHOR's trail is per-mile pace-tinted slices when splits exist.
        let paceSegments = buildAuthorPaceSegments()
        for (index, person) in people.enumerated() {
            let coords = person.track.coordinates
            let casing = MKPolyline(coordinates: coords, count: coords.count)
            overlayRoles[ObjectIdentifier(casing)] = .casing
            map.addOverlay(casing, level: .aboveLabels)
            let line = MKPolyline(coordinates: coords, count: coords.count)
            overlayRoles[ObjectIdentifier(line)] = .fullLine(person.color)
            map.addOverlay(line, level: .aboveLabels)
            let glow = MKPolyline(coordinates: coords, count: coords.count)
            overlayRoles[ObjectIdentifier(glow)] = .glow(personIndex: index, person.color)
            map.addOverlay(glow, level: .aboveLabels)
            if index == 0, !paceSegments.isEmpty {
                for (segIndex, segment) in paceSegments.enumerated() {
                    let coords = person.track.sampledCoordinates(
                        fromFraction: segment.range.lowerBound,
                        toFraction: segment.range.upperBound)
                    guard coords.count >= 2 else { continue }
                    authorSegmentRanges.append(segment.range)
                    let poly = MKPolyline(coordinates: coords, count: coords.count)
                    overlayRoles[ObjectIdentifier(poly)] = .trailSegment(
                        segment: authorSegmentRanges.count - 1, segment.color)
                    map.addOverlay(poly, level: .aboveLabels)
                    _ = segIndex
                }
            } else {
                let trail = MKPolyline(coordinates: coords, count: coords.count)
                overlayRoles[ObjectIdentifier(trail)] = .trail(personIndex: index, person.color)
                map.addOverlay(trail, level: .aboveLabels)
            }
        }

        // Badges: companions first so the followed/author draws above.
        for (index, person) in people.enumerated().reversed() {
            person.annotation.preparedImage = Self.badgeImage(
                avatar: person.avatar,
                ring: Color(person.color),
                size: index == 0 ? 34 : 28)
            map.addAnnotation(person.annotation)
            loadAvatarLater(person.avatar, into: person.annotation, personIndex: index,
                            ring: Color(person.color), size: index == 0 ? 34 : 28)
        }

        smoothedHeading = people[0].track.bearing(atFraction: 0, lookaheadMeters: lookaheadMeters)
        map.camera = overviewCamera(pitch: 35)
        emit(FlyoverTick(phase: .loading, fraction: 0, miles: 0))

        // The player keeps an opaque "preparing" cover up through .loading,
        // so the sweep below is invisible to the user.
        Task { @MainActor [weak self] in
            await self?.prewarmAndTakeOff()
        }
    }

    /// Waiting for the OVERVIEW alone loads only the tiles the intro needs —
    /// the cruise then flies into unloaded imagery. So before takeoff, walk
    /// the camera through the cruise corridor at cruise altitude, waiting for
    /// each stop to render; MapKit caches the tiles, and the real flight
    /// re-visits them warm. Every wait is deadline-capped so offline degrades
    /// to "fly over what loaded".
    @MainActor
    private func prewarmAndTakeOff() async {
        guard let track = followedTrack else { return }
        let deadline = Date().addingTimeInterval(10)
        await waitForRender(budget: 1.5, deadline: deadline)
        let steps = max(3, min(9, Int(track.totalMeters / 400)))
        for i in 0...steps {
            guard !stopped, mapView != nil, Date() < deadline else { break }
            mapView?.camera = cruiseCameraTarget(fraction: Double(i) / Double(steps))
            await waitForRender(budget: 1.2, deadline: deadline)
        }
        guard !stopped, mapView != nil else { return }
        mapView?.camera = overviewCamera(pitch: 35)
        await waitForRender(budget: 0.8, deadline: Date().addingTimeInterval(1))
        startFlightIfReady()
    }

    @MainActor
    private func waitForRender(budget: TimeInterval, deadline: Date) async {
        awaitingRender = true
        let stepDeadline = min(Date().addingTimeInterval(budget), deadline)
        while awaitingRender, !stopped, Date() < stepDeadline {
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    /// Takeoff — idempotent.
    private func startFlightIfReady() {
        guard !flightStarted, !stopped, mapView != nil, !people.isEmpty else { return }
        flightStarted = true
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        stopped = true
        displayLink?.invalidate()
        displayLink = nil
    }

    func setSpeed(_ multiplier: Double) {
        speed = multiplier
    }

    func setPaused(_ paused: Bool) {
        userPaused = paused
        // A scrub owns the link's pause state until the knob is released.
        guard !scrubbing, let displayLink, displayLink.isPaused != paused else { return }
        displayLink.isPaused = paused
        lastTimestamp = nil
    }

    /// The scrubber: position the whole flight at `fraction` directly. While
    /// active the display link is held; on release playback resumes from the
    /// scrubbed point (honouring the pause button), and a flight that had
    /// finished un-finishes so it can land again.
    @MainActor
    func applyScrub(seq: Int, fraction: Double, active: Bool) {
        guard seq != lastScrubSeq, flightStarted else { return }
        lastScrubSeq = seq
        guard let mapView, let track = followedTrack else { return }
        if active {
            scrubbing = true
            displayLink?.isPaused = true
            lastTimestamp = nil
            finishedNotified = false
            let f = min(max(fraction, 0), 1)
            elapsed = introDuration + f * cruiseDuration
            currentFraction = f
            let arc = arcFraction(of: followed, clock: f)
            // Jump-cut: the smoother would lag a fast drag around a bend.
            smoothedHeading = track.bearing(atFraction: arc, lookaheadMeters: lookaheadMeters)
            mapView.camera = cruiseCamera(fraction: arc, heading: smoothedHeading)
            lastStrokeFraction = -1
            setStroke(arc)
            moveRiders(to: f)
            report(.cruise, fraction: f)
        } else {
            scrubbing = false
            // Backward scrubs leave future mile marks standing — rebuild to
            // exactly the scrubbed point (silently).
            rebuildMileMarks(upTo: arcFraction(of: followed, clock: currentFraction))
            displayLink?.isPaused = userPaused
            lastTimestamp = nil
        }
    }

    /// Mid-flight follow switch: the shared fraction clock keeps running; the
    /// progressive highlight, mile marks, camera and odometer move to the new
    /// person. The heading smoother glides the camera around rather than
    /// snapping it.
    @MainActor
    func setFollowed(_ index: Int) {
        guard index != followed, people.indices.contains(index) else { return }
        // Old highlight off.
        glowRenderers[followed]?.alpha = 0
        trailRenderers[followed]?.alpha = 0
        if followed == 0 {
            for renderer in authorSegmentRenderers.values { renderer.alpha = 0 }
        }
        followed = index
        // New highlight catches up to the shared clock — at THIS rider's
        // place on it.
        let arc = arcFraction(of: followed, clock: currentFraction)
        lastStrokeFraction = -1
        setStroke(arc)
        glowRenderers[followed]?.alpha = 1
        trailRenderers[followed]?.alpha = 1
        if followed == 0 {
            for renderer in authorSegmentRenderers.values { renderer.alpha = 1 }
        }
        rebuildMileMarks(upTo: arc)
        // A paused or finished flight still reflects the switch immediately.
        if let track = followedTrack {
            // The card marks whoever the camera is on, so switching rider after
            // landing has to rebuild it.
            if finishedNotified { cachedStandings = finalStandings() }
            report(finishedNotified ? .finished : (flightStarted ? .cruise : .loading),
                   fraction: currentFraction,
                   standings: finishedNotified ? cachedStandings : [])
            if displayLink?.isPaused ?? true {
                mapView?.camera = finishedNotified
                    ? fittedOverviewCamera()
                    : cruiseCamera(fraction: arc,
                                   heading: track.bearing(atFraction: arc,
                                                          lookaheadMeters: lookaheadMeters))
            }
        }
    }

    @MainActor
    func replayIfNeeded(_ trigger: Int) {
        guard trigger != handledReplay else { return }
        handledReplay = trigger
        guard let mapView, !people.isEmpty else { return }
        elapsed = 0
        lastTimestamp = nil
        finishedNotified = false
        droppedMiles = 0
        currentFraction = 0
        lastStrokeFraction = -1
        outroTarget = nil
        cachedStandings = []
        mapView.removeAnnotations(mileAnnotations)
        mileAnnotations = []
        smoothedHeading = followedTrack?.bearing(atFraction: 0, lookaheadMeters: lookaheadMeters) ?? 0
        setStroke(0)
        moveRiders(to: 0)
        displayLink?.isPaused = false
    }

    // MARK: The flight

    @objc private func step(_ link: CADisplayLink) {
        // Clamped dt self-heals pauses, hitches and background gaps.
        let dt: Double
        if let lastTimestamp {
            dt = min(link.timestamp - lastTimestamp, 1.0 / 15.0)
        } else {
            dt = 0
        }
        lastTimestamp = link.timestamp
        elapsed += dt * speed

        guard let mapView, let track = followedTrack else { return }

        if elapsed < introDuration {
            // Swoop: overview → cruise start.
            let s = smoothstep(elapsed / introDuration)
            let start = cruiseCameraTarget(fraction: 0)
            mapView.camera = blend(from: overviewCamera(pitch: 35), to: start, amount: s)
            report(.intro, fraction: 0)
            return
        }

        let cruiseT = elapsed - introDuration
        if cruiseT < cruiseDuration {
            let fraction = cruiseT / cruiseDuration
            currentFraction = fraction
            // The camera, trail and marks follow the FOLLOWED rider's own
            // position; the shared clock only decides where that is.
            let arc = arcFraction(of: followed, clock: fraction)
            let target = track.bearing(atFraction: arc, lookaheadMeters: lookaheadMeters)
            smoothedHeading = approachAngle(smoothedHeading, toward: target, rate: 2.4, dt: dt)
            mapView.camera = cruiseCamera(fraction: arc, heading: smoothedHeading)
            setStroke(arc)
            moveRiders(to: fraction)
            dropMileMarks(upTo: arc)
            report(.cruise, fraction: fraction)
            return
        }

        let outroT = cruiseT - cruiseDuration
        if outroT < outroDuration {
            currentFraction = 1
            let s = smoothstep(outroT / outroDuration)
            let end = cruiseCamera(fraction: 1, heading: smoothedHeading)
            // The closing overhead FITS everyone's path — resolved once, on the
            // first outro frame, so the blend has a fixed target to walk to.
            if outroTarget == nil {
                outroTarget = fittedOverviewCamera()
                cachedStandings = finalStandings()
            }
            mapView.camera = blend(from: end,
                                   to: outroTarget ?? overviewCamera(pitch: 28),
                                   amount: s)
            setStroke(1)
            moveRiders(to: 1)
            dropMileMarks(upTo: 1)
            report(.outro, fraction: 1, standings: cachedStandings)
            return
        }

        displayLink?.isPaused = true
        if !finishedNotified {
            finishedNotified = true
            // Land exactly on the fit rather than wherever the blend arrived:
            // the view can be resized mid-flight (rotation, the standings card
            // appearing), and "the whole route is visible" is the one thing the
            // last frame has to be right about.
            let rect = routeMapRect
            if !rect.isNull {
                mapView.setVisibleMapRect(rect, edgePadding: overviewInsets, animated: true)
            }
            if cachedStandings.isEmpty { cachedStandings = finalStandings() }
            MADHaptics.success()
            report(.finished, fraction: 1, standings: cachedStandings)
        }
    }

    private func report(_ phase: FlyoverPhase, fraction: Double,
                        standings: [FlyoverStanding] = []) {
        let person = people.indices.contains(followed) ? people[followed] : nil
        let arc = arcFraction(of: followed, clock: fraction)
        let meters = person?.track.metersTraveled(atFraction: arc) ?? 0
        let miles: Double
        if let official = person?.calibratedMiles,
           let total = person?.track.totalMeters, total > 0 {
            // The recorded figure × the fraction of the line covered — NOT
            // metres × scale. That product is official/total × total, which
            // in floating point lands a hair under the recorded number at
            // the finish (1.0599…), and a two-decimal display then read 1.05
            // beside a card that said 1.06. This form is exactly `official`
            // at the line.
            miles = official * (meters / total)
        } else {
            miles = meters / 1609.344
        }
        let milestone = pendingMilestone
        pendingMilestone = nil
        // The followed rider's OWN time, frozen at their finish — the number
        // beside a rider standing at the line is how long THEY took.
        let elapsedSeconds = isTimed
            ? person?.clock?.ownElapsed(at: min(max(fraction, 0), 1) * walkDuration)
            : nil
        let notice = pendingNotice
        pendingNotice = nil
        emit(FlyoverTick(phase: phase, fraction: fraction, miles: miles,
                         elapsedSeconds: elapsedSeconds, notice: notice,
                         milestone: milestone, standings: standings))
    }

    /// The ONE door every tick leaves through. Synchronous from the display
    /// link and MapKit delegate callbacks (they fire outside SwiftUI's
    /// update, and the HUD stays welded to the frame); deferred one
    /// main-queue turn when the representable is mid-update (`inViewUpdate`),
    /// where a synchronous @State write is undefined behavior. `stop()` may
    /// land before a deferred tick does — a write to a dismantled view's
    /// state is ignored, so that is harmless.
    private func emit(_ tick: FlyoverTick) {
        guard inViewUpdate else {
            onTick(tick)
            return
        }
        let report = onTick
        DispatchQueue.main.async { report(tick) }
    }

    private func setStroke(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        let endpoint = clamped == 0 || clamped == 1
        let now = CACurrentMediaTime()
        // Faster playback advances further per frame, which is MORE
        // invalidations, not fewer — cap harder there so the tile renderer
        // can finish a pass before the next one starts.
        let minInterval: CFTimeInterval = speed >= 2 ? 1.0 / 10.0 : 1.0 / 20.0
        guard endpoint
            || (abs(clamped - lastStrokeFraction) >= 0.003 && now - lastStrokeTime >= minInterval)
        else { return }
        lastStrokeFraction = clamped
        lastStrokeTime = now
        if followed == 0, !authorSegmentRanges.isEmpty {
            // Each mile slice fills over its own fraction window, so the
            // seams stay welded to the shared clock.
            for (index, range) in authorSegmentRanges.enumerated() {
                guard let renderer = authorSegmentRenderers[index] else { continue }
                let span = range.upperBound - range.lowerBound
                let local = span > 0 ? (clamped - range.lowerBound) / span : 1
                let next = CGFloat(min(max(local, 0), 1))
                if renderer.strokeEnd != next {
                    renderer.strokeEnd = next
                    invalidate(renderer, whole: endpoint)
                }
            }
        } else if let renderer = trailRenderers[followed] {
            renderer.strokeEnd = CGFloat(clamped)
            invalidate(renderer, whole: endpoint)
        }
        if let renderer = glowRenderers[followed] {
            renderer.strokeEnd = CGFloat(clamped)
            invalidate(renderer, whole: endpoint)
        }
    }

    /// Redraw only what's on screen (padded, so the tip just off the edge is
    /// covered too) rather than every tile of a mile-long overlay — the
    /// endpoints redraw everything so nothing is left stale when the camera
    /// pulls back to the overview.
    private func invalidate(_ renderer: MKOverlayRenderer, whole: Bool) {
        guard !whole, let mapView else {
            renderer.setNeedsDisplay()
            return
        }
        let visible = mapView.visibleMapRect
        renderer.setNeedsDisplay(visible.insetBy(
            dx: -visible.size.width * 0.35, dy: -visible.size.height * 0.35))
    }

    /// `fraction` is the shared CLOCK: every rider goes to their own place on
    /// it (real position on a timed flight, the clock itself otherwise).
    private func moveRiders(to fraction: Double) {
        let walkSeconds = min(max(fraction, 0), 1) * walkDuration
        for (index, person) in people.enumerated() {
            person.annotation.coordinate = person.track.coordinate(
                atFraction: arcFraction(of: index, clock: fraction))
            // Crossing their own line: the badge gets its check and the HUD
            // says who finished and by how much. Scrubbing back un-checks
            // it silently — the notice is for a flight, not a drag.
            guard isTimed, let clock = person.clock, finishedFlags.indices.contains(index) else { continue }
            let done = walkSeconds >= clock.endsAt && clock.endsAt > 0
            guard done != finishedFlags[index] else { continue }
            finishedFlags[index] = done
            let image = Self.badgeImage(
                avatar: person.avatar, ring: Color(person.color),
                size: index == 0 ? 34 : 28, finished: done)
            person.annotation.preparedImage = image
            (mapView?.view(for: person.annotation))?.image = image
            if done, !scrubbing, fraction < 1 { pendingNotice = finishNotice(for: index) }
        }
    }

    private func dropMileMarks(upTo fraction: Double) {
        guard let mapView, people.indices.contains(followed) else { return }
        let marks = people[followed].mileMarks
        while droppedMiles < marks.count, marks[droppedMiles].fraction <= fraction {
            let mark = marks[droppedMiles]
            let annotation = FlyoverAnnotation()
            annotation.coordinate = mark.coordinate
            annotation.preparedImage = Self.mileImage(mark.mile, accent: Color(people[followed].color))
            mapView.addAnnotation(annotation)
            mileAnnotations.append(annotation)
            droppedMiles += 1
            MADHaptics.tap()
            // Splits belong to the AUTHOR's workout — only their line's
            // markers narrate times.
            if followed == 0, let text = splitByMile[mark.mile] {
                pendingMilestone = FlyoverMilestone(mile: mark.mile, text: text)
            }
        }
    }

    /// Follow switch: swap the mile marks to the new person — marks already
    /// passed appear at once (silently), the rest drop as the flight reaches
    /// them.
    @MainActor
    private func rebuildMileMarks(upTo fraction: Double) {
        guard let mapView, people.indices.contains(followed) else { return }
        mapView.removeAnnotations(mileAnnotations)
        mileAnnotations = []
        droppedMiles = 0
        let marks = people[followed].mileMarks
        while droppedMiles < marks.count, marks[droppedMiles].fraction <= fraction {
            let mark = marks[droppedMiles]
            let annotation = FlyoverAnnotation()
            annotation.coordinate = mark.coordinate
            annotation.preparedImage = Self.mileImage(mark.mile, accent: Color(people[followed].color))
            mapView.addAnnotation(annotation)
            mileAnnotations.append(annotation)
            droppedMiles += 1
        }
    }

    // MARK: Cameras

    private var boundingCenter: CLLocationCoordinate2D {
        guard let first = allCoordinates.first else { return CLLocationCoordinate2D() }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in allCoordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        return CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                      longitude: (minLon + maxLon) / 2)
    }

    private var boundingDiagonalMeters: Double {
        guard let first = allCoordinates.first else { return 0 }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in allCoordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        return MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: minLon))
            .distance(to: MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)))
    }

    private func overviewCamera(pitch: CGFloat) -> MKMapCamera {
        MKMapCamera(lookingAtCenter: boundingCenter,
                    fromDistance: overviewAltitude,
                    pitch: pitch,
                    heading: smoothedHeading)
    }

    /// The whole crew's path as a map rect — the thing the closing overhead has
    /// to FIT, not merely be centred on.
    private var routeMapRect: MKMapRect {
        var rect = MKMapRect.null
        for coordinate in allCoordinates {
            rect = rect.union(MKMapRect(origin: MKMapPoint(coordinate),
                                        size: MKMapSize(width: 0.1, height: 0.1)))
        }
        return rect
    }

    /// What the closing frame must leave clear. The HUD owns the bottom of the
    /// screen (odometer, leg chip, stat chips, scrubber, speed row, and now the
    /// standings card) and the crew picker the top, so a route fitted to the
    /// raw viewport lands underneath them. Proportional and capped, because the
    /// insets have to leave something to fit INTO on a small screen.
    private var overviewInsets: UIEdgeInsets {
        guard let mapView, mapView.bounds.height > 1 else {
            return UIEdgeInsets(top: 80, left: 36, bottom: 220, right: 36)
        }
        let height = mapView.bounds.height
        return UIEdgeInsets(
            top: min(max(height * 0.11, 60), height * 0.2),
            left: 36,
            bottom: min(max(height * 0.34, 180), height * 0.45),
            right: 36
        )
    }

    /// A camera that provably SHOWS the whole crew's route in this map view's
    /// actual bounds.
    ///
    /// The heuristic this replaces — centre on the bounding box at 2.1× its
    /// diagonal — knew nothing about the view's aspect ratio, the camera's
    /// pitch, or the HUD sitting over the bottom third, so a route wider than
    /// it was tall landed with both ends off the sides of the screen. A
    /// diagonal is also the wrong measure for an L-shaped walk, which is most
    /// of them. `cameraThatFits` asks MapKit the question directly; it answers
    /// north-up and level, which is also why the pull-out settles rather than
    /// staying banked at the followed rider's last heading.
    private func fittedOverviewCamera() -> MKMapCamera {
        guard let mapView, mapView.bounds.width > 1, mapView.bounds.height > 1 else {
            return overviewCamera(pitch: 28)
        }
        let rect = routeMapRect
        guard !rect.isNull else { return overviewCamera(pitch: 28) }
        return mapView.cameraThatFits(rect, edgePadding: overviewInsets)
    }

    /// The closing standings: who finished when, how far they went, and the gap
    /// to the first one home. Empty for a solo flight — the HUD's odometer and
    /// chips already say all of it for one person.
    ///
    /// Ordered by finishing time when the flight is timed, and by distance when
    /// it isn't: a clockless flight is synthetic (everyone drawn at a constant
    /// share of one shared clock), so a "finish order" read off it would be the
    /// order the tracks were built in, dressed up as a result.
    private func finalStandings() -> [FlyoverStanding] {
        guard people.count > 1 else { return [] }

        func distance(_ index: Int) -> Double {
            people[index].calibratedMiles ?? people[index].track.totalMiles
        }

        let order: [Int]
        if isTimed {
            order = people.indices.sorted { lhs, rhs in
                let l = people[lhs].clock?.endsAt ?? .greatestFiniteMagnitude
                let r = people[rhs].clock?.endsAt ?? .greatestFiniteMagnitude
                return l == r ? lhs < rhs : l < r
            }
        } else {
            order = people.indices.sorted { lhs, rhs in
                let l = distance(lhs), r = distance(rhs)
                return l == r ? lhs < rhs : l > r
            }
        }

        let winnerEndsAt = order.first.flatMap { people[$0].clock?.endsAt }
        return order.enumerated().map { place, index in
            let person = people[index]
            let endsAt = person.clock?.endsAt
            var behind: Double?
            if let endsAt, let winnerEndsAt, endsAt > winnerEndsAt {
                behind = endsAt - winnerEndsAt
            }
            return FlyoverStanding(
                id: "\(index)",
                place: place + 1,
                name: person.avatar?.name ?? (index == 0 ? "Author" : "A friend"),
                imageURL: person.avatar?.imageURL,
                color: Color(person.color),
                distanceMiles: distance(index),
                seconds: person.clock?.duration,
                behindSeconds: behind,
                isFollowed: index == followed
            )
        }
    }

    /// Camera slightly AHEAD of the rider so the badge flies in the lower
    /// third of the screen instead of dead center.
    private func cruiseCamera(fraction: Double, heading: Double) -> MKMapCamera {
        guard let track = followedTrack else { return overviewCamera(pitch: 35) }
        let rider = track.coordinate(atFraction: fraction)
        let aheadFraction = min(1, fraction + (lookaheadMeters * 0.6) / max(track.totalMeters, 1))
        let ahead = track.coordinate(atFraction: aheadFraction)
        let center = CLLocationCoordinate2D(
            latitude: rider.latitude + (ahead.latitude - rider.latitude) * 0.5,
            longitude: rider.longitude + (ahead.longitude - rider.longitude) * 0.5
        )
        return MKMapCamera(lookingAtCenter: center,
                           fromDistance: cruiseAltitude,
                           // Flatter than a chase cam: more of the drawn
                           // trail stays in frame behind the rider.
                           pitch: 58,
                           heading: heading)
    }

    private func cruiseCameraTarget(fraction: Double) -> MKMapCamera {
        guard let track = followedTrack else { return overviewCamera(pitch: 35) }
        return cruiseCamera(fraction: fraction,
                            heading: track.bearing(atFraction: fraction,
                                                   lookaheadMeters: lookaheadMeters))
    }

    private func blend(from: MKMapCamera, to: MKMapCamera, amount: Double) -> MKMapCamera {
        let s = min(max(amount, 0), 1)
        let center = CLLocationCoordinate2D(
            latitude: from.centerCoordinate.latitude
                + (to.centerCoordinate.latitude - from.centerCoordinate.latitude) * s,
            longitude: from.centerCoordinate.longitude
                + (to.centerCoordinate.longitude - from.centerCoordinate.longitude) * s
        )
        let heading = from.heading + shortestAngle(from: from.heading, to: to.heading) * s
        return MKMapCamera(lookingAtCenter: center,
                           fromDistance: from.centerCoordinateDistance
                               + (to.centerCoordinateDistance - from.centerCoordinateDistance) * s,
                           pitch: from.pitch + (to.pitch - from.pitch) * CGFloat(s),
                           heading: heading)
    }

    private func smoothstep(_ t: Double) -> Double {
        let s = min(max(t, 0), 1)
        return s * s * (3 - 2 * s)
    }

    private func approachAngle(_ current: Double, toward target: Double, rate: Double, dt: Double) -> Double {
        let next = current + shortestAngle(from: current, to: target) * min(1, rate * dt)
        return next.truncatingRemainder(dividingBy: 360)
    }

    private func shortestAngle(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    // MARK: Badge/mark images

    @MainActor
    private static func badgeImage(avatar: RouteArtAvatar?, ring: Color, size: CGFloat,
                                   finished: Bool = false) -> UIImage? {
        let badge = RouteAvatarBadge(
            name: avatar?.name ?? "?",
            image: RouteAvatarImageLoader.cachedImage(for: avatar?.imageURL),
            size: size,
            ring: ring
        )
        // A finished rider wears a check — the same green as "goal done"
        // everywhere else — so a badge standing still reads as "done", not
        // "stuck".
        let checked = ZStack(alignment: .bottomTrailing) {
            badge
            if finished {
                ZStack {
                    Circle().fill(MADTheme.Colors.success)
                    Circle().stroke(.white, lineWidth: 1.5)
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.24, weight: .black))
                        .foregroundColor(.white)
                }
                .frame(width: size * 0.44, height: size * 0.44)
                .offset(x: 2, y: 2)
            }
        }
        // Padding so the glow shadow isn't clipped off the bitmap.
        let renderer = ImageRenderer(content: checked.padding(6))
        renderer.scale = 3
        return renderer.uiImage
    }

    @MainActor
    private static func mileImage(_ mile: Int, accent: Color) -> UIImage? {
        let mark = ZStack {
            Circle().fill(accent)
            Circle().stroke(.white, lineWidth: 1.5)
            Text("\(mile)")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 20, height: 20)
        .shadow(color: accent.opacity(0.7), radius: 3)
        let renderer = ImageRenderer(content: mark.padding(4))
        renderer.scale = 3
        return renderer.uiImage
    }

    /// Cache-miss avatars download after takeoff and swap in mid-flight.
    @MainActor
    private func loadAvatarLater(_ avatar: RouteArtAvatar?, into annotation: FlyoverAnnotation,
                                 personIndex: Int, ring: Color, size: CGFloat) {
        guard let avatar, let key = avatar.imageURL, !key.isEmpty,
              RouteAvatarImageLoader.cachedImage(for: key) == nil else { return }
        Task { @MainActor [weak self, weak annotation] in
            guard await RouteAvatarImageLoader.loadImage(for: key) != nil,
                  let self, let annotation else { return }
            // Keep the check if they finished while the picture was loading.
            let finished = self.finishedFlags.indices.contains(personIndex) && self.finishedFlags[personIndex]
            let image = Self.badgeImage(avatar: avatar, ring: ring, size: size, finished: finished)
            annotation.preparedImage = image
            (self.mapView?.view(for: annotation))?.image = image
        }
    }

    // MARK: MKMapViewDelegate

    func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
        if fullyRendered { awaitingRender = false }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? MKPolyline,
              let role = overlayRoles[ObjectIdentifier(polyline)]
        else { return MKOverlayRenderer(overlay: overlay) }
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.lineCap = .round
        renderer.lineJoin = .round
        switch role {
        case .casing:
            // Dark edge so every colour line stays legible over imagery.
            renderer.strokeColor = UIColor.black.withAlphaComponent(0.5)
            renderer.lineWidth = 7
        case .fullLine(let color):
            // The route itself — full length, always visible from the first
            // frame; the trail below only BRIGHTENS it.
            renderer.strokeColor = color.withAlphaComponent(0.55)
            renderer.lineWidth = 4
        case .glow(let personIndex, let color):
            renderer.strokeColor = color.withAlphaComponent(0.4)
            renderer.lineWidth = 12
            renderer.strokeEnd = 0
            renderer.alpha = personIndex == followed ? 1 : 0
            glowRenderers[personIndex] = renderer
        case .trail(let personIndex, let color):
            renderer.strokeColor = color
            renderer.lineWidth = 5.5
            renderer.strokeEnd = 0
            renderer.alpha = personIndex == followed ? 1 : 0
            trailRenderers[personIndex] = renderer
        case .trailSegment(let segment, let color):
            renderer.strokeColor = color
            renderer.lineWidth = 5.5
            renderer.strokeEnd = 0
            renderer.alpha = followed == 0 ? 1 : 0
            authorSegmentRenderers[segment] = renderer
        }
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let flyover = annotation as? FlyoverAnnotation else { return nil }
        let identifier = flyover.isRider ? "flyover-rider" : "flyover-mile"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        view.annotation = annotation
        view.image = flyover.preparedImage
        view.displayPriority = .required
        view.collisionMode = .none
        view.zPriority = flyover.isRider ? .max : .defaultSelected
        return view
    }
}
