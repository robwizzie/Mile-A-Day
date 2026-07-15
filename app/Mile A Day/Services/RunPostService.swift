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

    /// Build today's run stats for the composer/auto-post, with the workout id set
    /// so the resulting post links to the run (enabling the one-post-per-workout
    /// upsert + feed dedup).
    @MainActor
    static func todayStats(workoutId: String) -> RunStatsInput {
        let hk = HealthKitManager.shared
        let user = UserManager.shared.currentUser
        let paceSecPerMile = hk.todaysAveragePace.map { $0 * 60 }
        return RunStatsInput(
            distance: hk.todaysDistance,
            paceSecondsPerMile: (paceSecPerMile ?? 0) > 0 ? paceSecPerMile : nil,
            durationSeconds: hk.todaysTotalDuration > 0 ? hk.todaysTotalDuration : nil,
            streak: user.streak,
            calories: hk.todaysTotalCalories > 0 ? hk.todaysTotalCalories : nil,
            steps: hk.todaysSteps > 0 ? hk.todaysSteps : nil,
            workoutId: workoutId,
            dateText: todayText()
        )
    }

    /// The workout that pushed today's total past the daily goal — the same one
    /// the post-run prompt auto-posts. Recomputed deterministically (today's
    /// workouts in start order, first to cross the goal) so a photo shared later
    /// from the feed composer carries the same workout id and upserts into the
    /// SAME feed post instead of creating a duplicate.
    @MainActor
    static func dailyMileWorkoutId() -> String? {
        let workouts = HealthKitManager.shared.todaysWorkouts
            .sorted { $0.startDate < $1.startDate }
        let goal = UserManager.shared.currentUser.goalMiles
        var total = 0.0
        for workout in workouts {
            total += workout.totalDistance?.doubleValue(for: HKUnit.mile()) ?? 0
            if total >= goal { return workout.uuid.uuidString }
        }
        // Goal met via non-workout distance — fall back to the latest workout.
        return workouts.last?.uuid.uuidString
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
            // isAuto — the server may replace this card in place with a later
            // photo post, but it never counts as the user's one post per workout.
            _ = try await PostService.createPost(
                mediaUrl: mediaUrl,
                caption: nil,
                workoutId: workoutId,
                shareToFeed: true,
                shareToStory: false,
                stats: stats.snapshot,
                isAuto: true
            )
        } catch {
            print("[RunPostService] autoPostMile failed: \(error)")
        }
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
