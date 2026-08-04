import SwiftUI
import UIKit
import MapKit
import HealthKit
import CoreLocation

/// Builds and publishes the "auto" feed post for a completed mile when the user
/// doesn't add a photo: a rendered GPS route map when the run has one, otherwise
/// a branded stats card. Linked to the workout so the backend upserts one post
/// per run (a later photo replaces this image in place).
enum RunPostService {

    /// Build stats for the linked workout so one day's extra walks/runs don't
    /// collapse into a single all-day post. Uses the local WorkoutIndex when
    /// the HKWorkout object is still lagging, then falls back to day totals.
    ///
    /// One exception, and it's the common case: when the workout IS the day's
    /// daily-mile anchor, the numbers are the DAY's rollup up to that point —
    /// because that's what every read surface restates the card with (see
    /// `POST_COLUMNS` in postService.ts). Baking the single leg meant a mile
    /// walked in three goes produced a card reading "0.33 mi" sitting under a
    /// "1.06 mi" headline. Workouts AFTER the anchor (the extra-mile posts) are
    /// still exactly themselves — that's the whole reason the anchor check is
    /// here rather than a blanket switch to day totals.
    @MainActor
    static func todayStats(workoutId: String) -> RunStatsInput {
        if let stats = exactStats(workoutId: workoutId) {
            return dayRollupStats(anchorId: workoutId) ?? stats
        }

        return todayFallbackStats(workoutId: workoutId)
    }

    /// The day's combined totals when `anchorId` is the workout that completed
    /// the mile and it took more than one walk/run to get there. Nil otherwise,
    /// so single-workout days and extra-mile posts keep their exact stats.
    ///
    /// Membership mirrors the server's rollup lateral: everything logged up to
    /// and including the anchor. Pace is recomputed from the totals rather than
    /// averaged — a 20-minute walk and a 7-minute jog don't average.
    @MainActor
    private static func dayRollupStats(anchorId: String) -> RunStatsInput? {
        guard dailyMileWorkoutId() == anchorId else { return nil }
        let hk = HealthKitManager.shared
        guard let anchor = hk.todaysWorkouts.first(where: { $0.uuid.uuidString == anchorId })
        else { return nil }

        let segments = hk.todaysWorkouts.filter { $0.endDate <= anchor.endDate }
        // Sub-floor phantoms are SUMMED but don't make a day "multi-segment" —
        // the server counts legs the same way (`feed_role <> 'hidden'`), and if
        // the two disagree the server declines to restate and the card is left
        // showing a number nothing else reports.
        guard segments.filter({ WorkoutFeedFloor.isSubstantive($0) }).count > 1 else { return nil }

        let distance = segments.reduce(0.0) {
            $0 + ($1.totalDistance?.doubleValue(for: .mile()) ?? 0)
        }
        let duration = segments.reduce(0.0) { $0 + $1.duration }
        // Pace divides by MOVING time where legs recorded it (per-leg elapsed
        // fallback — a day can mix in-app and Watch legs), mirroring the
        // server's rollup restating. `duration` stays the elapsed truth.
        let paceDivisor = segments.reduce(0.0) { $0 + paceDuration(of: $1) }
        let calories = segments.reduce(0.0) { $0 + workoutCalories($1) }
        guard distance > 0 else { return nil }

        return RunStatsInput(
            distance: distance,
            paceSecondsPerMile: workoutPaceSecondsPerMile(distance: distance, duration: paceDivisor),
            durationSeconds: duration > 0 ? duration : nil,
            streak: postableStreak(),
            calories: calories > 0 ? calories : nil,
            steps: nil,
            workoutId: anchorId,
            dateText: dateText(for: anchor.startDate),
            // The anchor IS the leg that crossed the mile, so its race result
            // is the day's race result.
            ghostMarginSeconds: ghostWin(of: anchor)?.margin,
            ghostTargetSeconds: ghostWin(of: anchor)?.target
        )
    }

    /// The streak to BAKE into a post. `currentUser.streak` is the live display
    /// value, which deliberately lags a real break (UserManager quarantines a
    /// 2+ day collapse until it's verified) — and a post keeps its number
    /// forever, so a post made after a missed day was showing a streak the
    /// author no longer had while every other surface showed the truth.
    @MainActor
    private static func postableStreak() -> Int {
        UserManager.shared.freshBackendStreak ?? UserManager.shared.currentUser.streak
    }

    @MainActor
    private static func exactStats(workoutId: String) -> RunStatsInput? {
        let hk = HealthKitManager.shared

        if let workout = hk.todaysWorkouts.first(where: { $0.uuid.uuidString == workoutId }) {
            let distance = workout.totalDistance?.doubleValue(for: .mile()) ?? 0
            let pace = workoutPaceSecondsPerMile(distance: distance, duration: paceDuration(of: workout))
            let calories = workoutCalories(workout)
            return RunStatsInput(
                distance: distance,
                paceSecondsPerMile: pace,
                durationSeconds: workout.duration > 0 ? workout.duration : nil,
                streak: postableStreak(),
                calories: calories > 0 ? calories : nil,
                steps: nil,
                workoutId: workoutId,
                dateText: dateText(for: workout.startDate),
                isExtra: isExtraWorkout(workoutId),
                ghostMarginSeconds: ghostWin(of: workout)?.margin,
                ghostTargetSeconds: ghostWin(of: workout)?.target
            )
        }

        if let record = hk.workoutIndex?.workouts(for: Date()).first(where: { $0.id == workoutId }) {
            let pace = workoutPaceSecondsPerMile(distance: record.distance, duration: record.duration)
            return RunStatsInput(
                distance: record.distance,
                paceSecondsPerMile: pace,
                durationSeconds: record.duration > 0 ? record.duration : nil,
                streak: postableStreak(),
                calories: nil,
                steps: nil,
                workoutId: workoutId,
                dateText: dateText(for: record.localDate),
                isExtra: isExtraWorkout(workoutId)
            )
        }

        return nil
    }

    @MainActor
    private static func todayFallbackStats(workoutId: String) -> RunStatsInput {
        let hk = HealthKitManager.shared
        let paceSecPerMile = hk.todaysAveragePace.map { $0 * 60 }
        return RunStatsInput(
            distance: hk.todaysDistance,
            paceSecondsPerMile: (paceSecPerMile ?? 0) > 0 ? paceSecPerMile : nil,
            durationSeconds: hk.todaysTotalDuration > 0 ? hk.todaysTotalDuration : nil,
            streak: postableStreak(),
            calories: hk.todaysTotalCalories > 0 ? hk.todaysTotalCalories : nil,
            steps: hk.todaysSteps > 0 ? hk.todaysSteps : nil,
            workoutId: workoutId,
            dateText: todayText()
        )
    }

    /// True when this workout is a post-goal bonus: the day's goal is already
    /// complete and this isn't the goal-completing anchor. Drives the
    /// "+0.14 mi" sticker framing so a short extra walk bakes as ADDED miles,
    /// never as a number that reads like the whole day. The goal check
    /// matters: pre-goal legs must stay plain (dailyMileWorkoutId falls back
    /// to the latest workout even before the goal is met).
    @MainActor
    private static func isExtraWorkout(_ workoutId: String) -> Bool {
        let hk = HealthKitManager.shared
        let goalDone = ProgressCalculator.isGoalCompleted(
            current: hk.todaysDistance,
            goal: UserManager.shared.currentUser.goalMiles
        )
        guard goalDone else { return false }
        return dailyMileWorkoutId() != workoutId
    }

    /// Display-pace divisor: the tracker's recorded moving time when this
    /// workout carries it (in-app tracked; clamped to elapsed), else elapsed.
    private static func paceDuration(of workout: HKWorkout) -> TimeInterval {
        if let moving = workout.metadata?[WorkoutLocationManager.movingSecondsMetadataKey] as? Double,
           moving > 0, moving <= workout.duration {
            return moving
        }
        return workout.duration
    }

    /// The ghost win stamped on this workout at finish, if it beat its ghost.
    /// Only winning workouts carry the metadata, so presence IS the win.
    private static func ghostWin(of workout: HKWorkout) -> (margin: Double, target: Double)? {
        guard
            let margin = workout.metadata?[WorkoutLocationManager.ghostMarginMetadataKey] as? Double,
            let target = workout.metadata?[WorkoutLocationManager.ghostTargetMetadataKey] as? Double,
            margin > 0, target > 0
        else { return nil }
        return (margin, target)
    }

    private static func workoutPaceSecondsPerMile(distance: Double, duration: TimeInterval) -> TimeInterval? {
        guard distance > 0, duration > 0 else { return nil }
        let paceMinutes = (duration / 60.0) / distance
        guard paceMinutes >= 2.0, paceMinutes <= 30.0 else { return nil }
        return duration / distance
    }

    private static func workoutCalories(_ workout: HKWorkout) -> Double {
        if #available(iOS 18.0, *),
           let statistics = workout.statistics(for: HKQuantityType(.activeEnergyBurned)),
           let energy = statistics.sumQuantity() {
            return energy.doubleValue(for: .kilocalorie())
        }
        return workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
    }

    private static func dateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// The workout that pushed today's total past the daily goal — the same one
    /// the post-run prompt auto-posts. Recomputed deterministically (today's
    /// workouts in start order, first to cross the goal) so a photo shared later
    /// from the feed composer carries the same workout id and upserts into the
    /// SAME feed post instead of creating a duplicate.
    ///
    /// Mirrors how the server picks a day's `daily_mile` anchor
    /// (`feedRoleStatements` in workoutService.ts), because the two must agree:
    /// the server folds the day's other workouts into whichever one it considers
    /// the anchor, so a post attached to a different workout wouldn't be restated
    /// with the day's combined stats.
    ///
    /// Two things that used to differ from the server, and why they matter:
    ///  - Sub-floor workouts can't be the anchor. A 0.02-mile phantom at 6am
    ///    would otherwise decide which workout "owns" the mile and headline the
    ///    day's card with an accident.
    ///  - Crossing is measured against the tolerance, not the raw goal. A
    ///    0.97-mile day passes the server's posting gate but never crosses
    ///    `goal` here, so every workout fell through to the `last` fallback.
    @MainActor
    static func dailyMileWorkoutId() -> String? {
        let workouts = HealthKitManager.shared.todaysWorkouts
            .sorted { $0.startDate < $1.startDate }
        let goal = UserManager.shared.currentUser.goalMiles
        var total = 0.0
        var lastSubstantive: HKWorkout?
        for workout in workouts {
            total += workout.totalDistance?.doubleValue(for: HKUnit.mile()) ?? 0
            if WorkoutFeedFloor.isSubstantive(workout) { lastSubstantive = workout }
            // The anchor is the last REAL workout at or before the crossing
            // point — so when a phantom is what tips the day over, the run that
            // did the work still owns the card.
            if ProgressCalculator.isGoalCompleted(current: total, goal: goal),
               let anchor = lastSubstantive {
                return anchor.uuid.uuidString
            }
        }
        // Goal met via non-workout distance, or only sub-floor workouts today —
        // fall back to the latest workout so the prompt still has something to
        // attach to.
        return (lastSubstantive ?? workouts.last)?.uuid.uuidString
    }

    /// Render the auto image (route map or stats card), upload it, and create the
    /// linked feed post. Called when the user skips the post-run photo prompt.
    @MainActor
    static func autoPostMile(workoutId: String, workoutType: String) async {
        let stats = todayStats(workoutId: workoutId)
        let workout = HealthKitManager.shared.todaysWorkouts.first { $0.uuid.uuidString == workoutId }

        var image: UIImage?
        if let workout {
            let coords = await HealthKitManager.shared.fetchAllRouteLocations(for: workout)
                .map { $0.coordinate }
            if coords.count >= 2 {
                // Same accent the feed uses for this workout type — the baked
                // card and the live cards must speak one color language.
                let color = UIColor(ActivityCardView.color(workoutType))
                image = await renderRouteImage(
                    coordinates: coords, color: color,
                    stats: stats, workoutType: workoutType
                )
            }
        }
        if image == nil {
            image = renderStatsCard(stats: stats, workoutType: workoutType)
        }
        guard let finalImage = image else { return }

        do {
            let mediaUrl = try await PostService.uploadMedia(finalImage)
            let created: PostItem
            do {
                // isAuto — the server may replace this card in place with a
                // later photo post, but it never counts as the user's one post
                // per workout.
                created = try await createAutoPost(mediaUrl: mediaUrl, workoutId: workoutId, stats: stats)
            } catch let APIError.badRequest(message)
                        where message == "auto_post_workout_unavailable" || message == "auto_post_stats_mismatch" {
                // HealthKit/backend sync can lag the prompt by a beat. Keep the
                // skip action reliable: publish the rendered card unlinked
                // instead of making "Skip" look broken. The raw workout card can
                // still appear later if the sync catches up.
                print("[RunPostService] linked auto post rejected (\(message)); retrying unlinked")
                created = try await createAutoPost(mediaUrl: mediaUrl, workoutId: nil, stats: stats)
            }
            // Skipping the photo still counts as posting this run live if it's
            // within the fresh window (no-op otherwise).
            FreshPostWindowManager.shared.markPostedLive(
                postId: created.post_id,
                workoutId: created.workout_id ?? workoutId
            )
        } catch {
            print("[RunPostService] autoPostMile failed: \(error)")
        }
    }

    @MainActor
    private static func createAutoPost(mediaUrl: String, workoutId: String?, stats: RunStatsInput) async throws -> PostItem {
        try await PostService.createPost(
            mediaUrl: mediaUrl,
            caption: nil,
            workoutId: workoutId,
            shareToFeed: true,
            shareToStory: false,
            stats: stats.snapshot,
            isAuto: true
        )
    }

    // MARK: - Rendering

    @MainActor
    static func renderStatsCard(stats: RunStatsInput, workoutType: String) -> UIImage? {
        // The card lays itself out at design size (360×450) — scale up to the
        // 1080×1350 upload size. Rendering AT 1080 with scale 1 is the classic
        // bug: point sizes become raw pixels and the whole card reads tiny.
        let card = RunStatsCardView(stats: stats, workoutType: workoutType)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1080 / RunStatsCardView.designSize.width
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// The stats/brand overlay for route images, rendered transparent at the
    /// same design-space scale so its type sizes match the stats card's.
    @MainActor
    private static func renderRouteOverlay(stats: RunStatsInput, workoutType: String) -> UIImage? {
        let overlay = RouteStatsOverlayView(stats: stats, workoutType: workoutType)
        let renderer = ImageRenderer(content: overlay)
        renderer.scale = 1080 / RunStatsCardView.designSize.width
        renderer.isOpaque = false
        return renderer.uiImage
    }

    /// Snapshot a map covering the route, draw the traced polyline + start/end
    /// pins, then composite the stats/brand overlay so the post carries its
    /// numbers instead of being a bare map. Uses `MKMapSnapshotter` (not
    /// `ImageRenderer`) because live map tiles don't render through SwiftUI's
    /// renderer.
    @MainActor
    static func renderRouteImage(
        coordinates: [CLLocationCoordinate2D],
        color: UIColor,
        stats: RunStatsInput,
        workoutType: String
    ) async -> UIImage? {
        guard coordinates.count >= 2 else { return nil }

        var minLat = coordinates[0].latitude, maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude, maxLon = coordinates[0].longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.003),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.003)
        )

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = CGSize(width: 1080, height: 1350)
        options.scale = 1
        options.mapType = .standard

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot: MKMapSnapshotter.Snapshot? = await withCheckedContinuation { cont in
            snapshotter.start { snap, _ in cont.resume(returning: snap) }
        }
        guard let snapshot else { return nil }

        let overlay = renderRouteOverlay(stats: stats, workoutType: workoutType)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: options.size, format: format)
        return renderer.image { ctx in
            snapshot.image.draw(at: .zero)
            let cg = ctx.cgContext

            // Line + pin sizes are in the 1080px space — thick enough to stay
            // visible when the image displays at ~a third of that width.
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(16)
            cg.setLineJoin(.round)
            cg.setLineCap(.round)
            // Same centripetal Catmull-Rom smoothing the live feed overlay
            // uses, so the baked image matches what friends swipe to on the
            // feed slide.
            let screenPoints = coordinates.map { snapshot.point(for: $0) }
            cg.addPath(RouteSmoothing.smoothedPath(through: screenPoints))
            cg.strokePath()

            drawDot(cg, at: snapshot.point(for: coordinates.first!), color: .systemGreen)
            drawDot(cg, at: snapshot.point(for: coordinates.last!), color: color)

            // Stats band + activity/date chips over the map.
            overlay?.draw(in: CGRect(origin: .zero, size: options.size))
        }
    }

    private static func drawDot(_ cg: CGContext, at pt: CGPoint, color: UIColor) {
        let outer: CGFloat = 21
        cg.setFillColor(UIColor.white.cgColor)
        cg.fillEllipse(in: CGRect(x: pt.x - outer, y: pt.y - outer, width: outer * 2, height: outer * 2))
        let inner: CGFloat = 13
        cg.setFillColor(color.cgColor)
        cg.fillEllipse(in: CGRect(x: pt.x - inner, y: pt.y - inner, width: inner * 2, height: inner * 2))
    }

    private static func todayText() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: Date())
    }
}
