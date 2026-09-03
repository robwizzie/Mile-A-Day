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
            $0 + $1.madDistanceMiles
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
            let distance = workout.madDistanceMiles
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

    /// The ghost WIN stamped on this workout, if it beat its ghost.
    ///
    /// The margin is signed and every completed race is stamped, so presence is
    /// no longer the win — the `> 0` below is what keeps losses out of the
    /// feed. That's deliberate: nobody wants their loss posted.
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

    /// Internal (not private): CalorieLedger counts treats with the same
    /// figure the post cards print, so the two can never disagree.
    static func workoutCalories(_ workout: HKWorkout) -> Double {
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
            total += workout.madDistanceMiles
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

    /// The workout a Buddy Walk actually was, resolved LOCALLY.
    ///
    /// A buddy participant row carries a `workout_id`, but the server only
    /// stamps it in `reconcileBuddySessions` once that person's HKWorkout has
    /// synced — a minute or two after the walk ends, and the recap opens
    /// *seconds* after. So in practice it was nil exactly when the post was
    /// being made, and the buddy post went up with no workout link at all.
    /// That single nil is what broke the "one post" guarantee: the server's
    /// `workout_already_posted` rule keys on `workout_id`, so with none set the
    /// run's slot stayed empty, the photo prompt still fired for it, skipping
    /// that prompt laid a SECOND auto card over the same walk, and the card
    /// could never be restated with the day's rollup.
    ///
    /// The device already knows the answer. Matching mirrors the server's own
    /// reconciliation window (`device_end_date >= started_at`, started before
    /// the session ended plus slack for a late Finish tap), newest first, and
    /// skips sub-floor phantoms — the server gives those no feed card, so
    /// linking a post to one would attach it to something that can't appear.
    ///
    /// Nil when nothing matches, which keeps today's behaviour (an unlinked
    /// post) rather than guessing at an unrelated walk.
    ///
    /// Falls back to the WORKOUT INDEX when `todaysWorkouts` hasn't caught up,
    /// and that fallback is the difference between the flow working and the
    /// whole cascade above firing anyway. The recap opens from the tracker
    /// cover's `onDismiss`, i.e. the instant the workout is saved — and
    /// `todaysWorkouts` is republished by an ASYNC HealthKit query that has not
    /// necessarily answered yet. So the window match ran against an array that
    /// didn't contain the walk that had just ended, returned nil, and every
    /// symptom the doc comment above describes happened in full: the post went
    /// up unlinked, the server had no workout to hang a route on (so the card
    /// showed the bare stats face), the photo prompt was never retired and
    /// surfaced as the recap dismissed, and skipping THAT laid a second,
    /// route-only auto card beside the post that was just made.
    ///
    /// The index is the same store `dailyMileWorkoutId`'s callers already fall
    /// back to (DashboardView's `todayIndexWorkoutUUID`), so this also keeps
    /// the buddy path and the photo prompt resolving through the same two
    /// sources — when those two disagree, `resolvePhotoPrompt` misses and the
    /// prompt fires for a walk that has already been posted.
    @MainActor
    static func buddyWorkoutId(
        reconciled: String?,
        startedAt: Date?,
        endedAt: Date?
    ) -> String? {
        if let reconciled, !reconciled.isEmpty { return reconciled }
        guard let startedAt else { return nil }
        let closedAt = (endedAt ?? Date()).addingTimeInterval(10 * 60)

        if let match = HealthKitManager.shared.todaysWorkouts
            .filter({ WorkoutFeedFloor.isSubstantive($0) })
            .filter({ $0.endDate >= startedAt && $0.startDate <= closedAt })
            .max(by: { $0.endDate < $1.endDate })?
            .uuid.uuidString {
            return match
        }

        // Same window, same substantive floor, against the index. `duration`
        // stands in for a start date the record doesn't carry — the index
        // stores when a workout ENDED, so the start is derived rather than
        // read, which is exact enough for a ten-minute window.
        return HealthKitManager.shared.workoutIndex?
            .workouts(for: Date())
            .filter { WorkoutFeedFloor.isSubstantive(distance: $0.distance, duration: $0.duration) }
            .filter {
                $0.deviceEndDate >= startedAt
                    && $0.deviceEndDate.addingTimeInterval(-$0.duration) <= closedAt
            }
            .max(by: { $0.deviceEndDate < $1.deviceEndDate })?
            .id
    }

    /// Render the auto image (route map or stats card), upload it, and create the
    /// linked feed post. Called when the user skips the post-run photo prompt.
    ///
    /// Deliberately NOT gated on `PostedWorkoutRegistry`. The server already
    /// refuses to let an auto card overwrite a deliberate post (`updateGuard`
    /// is `is_auto` only, and the fall-through raises `workout_already_posted`,
    /// which lands in the catch below), so there is no duplicate to prevent —
    /// and a client-side guard would be WRONG in one real case: a photo shared
    /// to a story only still consumes the run's one user-post slot, but leaves
    /// the FEED with no card, which is exactly what this is for.
    @MainActor
    static func autoPostMile(workoutId: String, workoutType: String) async {
        // "Only walks I photographed reach my feed." Gated HERE rather than at
        // each call site so every route into the photo-less card — skipping the
        // prompt, backing out of the composer, sharing to a story only, and
        // whatever gets added next — honours it from one place.
        //
        // Nothing else changes: the fresh-post window still opens, the prompt
        // still appears, and posting a photo still works normally. All this
        // removes is the card that would have gone up in the photo's place.
        guard NotificationPreferences.load().autoPostWithoutPhoto else { return }

        let stats = todayStats(workoutId: workoutId)
        let workout = HealthKitManager.shared.todaysWorkouts.first { $0.uuid.uuidString == workoutId }

        var image: UIImage?
        // Stealth Mode: this card is a PICTURE of the map, uploaded as media —
        // the one route leak no server-side gate can see. A stealth walk
        // falls through to the stats card.
        if let workout, !StealthModeStore.shared.isStealth(workout) {
            let coords = await HealthKitManager.shared.fetchAllRouteLocations(for: workout)
                .map { $0.coordinate }
            if coords.count >= 2 {
                // Same accent the feed uses for this workout type — the baked
                // card and the live cards must speak one color language.
                image = await renderRouteImage(
                    coordinates: coords, color: ActivityCardView.color(workoutType),
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
            do {
                // isAuto — the server may replace this card in place with a
                // later photo post, but it never counts as the user's one post
                // per workout.
                _ = try await createAutoPost(mediaUrl: mediaUrl, workoutId: workoutId, stats: stats)
            } catch let APIError.badRequest(message)
                        where message == "auto_post_workout_unavailable" || message == "auto_post_stats_mismatch" {
                // HealthKit/backend sync can lag the prompt by a beat. Keep the
                // skip action reliable: publish the rendered card unlinked
                // instead of making "Skip" look broken. The raw workout card can
                // still appear later if the sync catches up.
                print("[RunPostService] linked auto post rejected (\(message)); retrying unlinked")
                _ = try await createAutoPost(mediaUrl: mediaUrl, workoutId: nil, stats: stats)
            }
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
        // The routeless bake is the indoor card's still frame (track or
        // treadmill face — the POSTER's dashboard style picks, since a PNG is
        // rendered once on their device; it can't animate, but the visual
        // language matches the live cards). Avatar is cache-only: this isn't
        // async, and RouteAvatarBadge's initials fallback keeps the render
        // deterministic on a miss.
        //
        // The card lays itself out at design size (360×450) — scale up to the
        // 1080×1350 upload size. Rendering AT 1080 with scale 1 is the classic
        // bug: point sizes become raw pixels and the whole card reads tiny.
        let user = UserManager.shared.currentUser
        let card = IndoorWorkoutCard(
            stats: stats.snapshot,
            workoutType: workoutType,
            avatar: RouteArtAvatar(name: user.name, imageURL: user.profileImageUrl),
            still: true
        )
        .frame(width: RunStatsCardView.designSize.width,
               height: RunStatsCardView.designSize.height)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1080 / RunStatsCardView.designSize.width
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// The route as the branded art card at upload size — the same face the
    /// live feed slide draws (canvas + glow line + the poster's badge settled
    /// at the end + mile ticks), baked to a PNG. One `ImageRenderer` pass:
    /// the art canvas is pure SwiftUI, which is what lets the old
    /// MKMapSnapshotter+CoreGraphics composite go (map tiles were the only
    /// reason it existed — they don't render through SwiftUI's renderer).
    @MainActor
    static func renderRouteImage(
        coordinates: [CLLocationCoordinate2D],
        color: Color,
        stats: RunStatsInput,
        workoutType: String
    ) async -> UIImage? {
        guard coordinates.count >= 2 else { return nil }

        // Await the avatar once — this runs at post time, not in a scroll. A
        // miss falls back to initials, so the render is deterministic either
        // way (RouteAvatarBadge never touches AsyncImage).
        let user = UserManager.shared.currentUser
        let avatar = RouteArtAvatar(name: user.name, imageURL: user.profileImageUrl)
        var avatarImages: [String: UIImage] = [:]
        if let key = user.profileImageUrl,
           let image = await RouteAvatarImageLoader.loadImage(for: key) {
            avatarImages[key] = image
        }

        // Ghost-map underlay for the bake, same as the live cards. A failed
        // snapshot (offline) just bakes the pure canvas.
        let underlay = await RouteMapSnapshot.generate(
            coordinates: coordinates, size: RunStatsCardView.designSize)

        let content = ZStack(alignment: .topLeading) {
            RouteArtView.still(
                coordinates: coordinates,
                routeColor: color,
                authorAvatar: avatar,
                avatarImages: avatarImages,
                underlay: underlay,
                paletteDate: Date(),
                size: RunStatsCardView.designSize
            )
            // Stats band + activity/date chips, laid out in the same 360×450
            // design space the live slides scale from.
            RouteStatsOverlayView(stats: stats, workoutType: workoutType)
                .frame(width: RunStatsCardView.designSize.width,
                       height: RunStatsCardView.designSize.height,
                       alignment: .topLeading)
        }
        .frame(width: RunStatsCardView.designSize.width,
               height: RunStatsCardView.designSize.height)

        // Design size → 1080×1350 upload, same scale rule as renderStatsCard.
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1080 / RunStatsCardView.designSize.width
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private static func todayText() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: Date())
    }
}
