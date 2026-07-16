import SwiftUI
import HealthKit
import MapKit

// MARK: - Workout Detail View

struct WorkoutDetailView: View {
    let workout: HKWorkout
    /// The run's linked post, when the presenting list already fetched it — lets
    /// the photo appear instantly instead of re-scanning pages of posts here.
    var preloadedPost: PostItem? = nil
    /// Whether this page is the one on screen. In the swipe pager every page is
    /// built up front, so the heavy loads (HealthKit + network) gate on this so
    /// only the visible workout actually fetches. Standalone presentations pass
    /// the default (always active).
    var isActive: Bool = true
    @Environment(\.dismiss) private var dismiss
    @State private var calories: Double?
    @State private var splitTimes: [TimeInterval]?
    @State private var isLoadingSplits = false
    @State private var showEditSheet = false
    @State private var routeCoordinates: [CLLocationCoordinate2D]?
    @State private var isLoadingRoute = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    /// The user's own feed/story post linked to this workout, when one exists.
    @State private var linkedPost: PostItem?
    @State private var editingLinkedPost: PostItem?
    @State private var showPostDeleteConfirm = false
    @State private var isAddingToFeed = false
    @State private var addToFeedError: String?
    @EnvironmentObject var healthManager: HealthKitManager

    private let workoutService = WorkoutService()

    /// Average speed in mph for this workout (0 if we can't compute it).
    private var averageSpeedMph: Double {
        guard workout.duration > 0, distanceMiles > 0 else { return 0 }
        return distanceMiles / (workout.duration / 3600.0)
    }

    /// A human can't run/walk a mile faster than ~15 mph (world record), so high
    /// average speeds almost always mean the tracker was left running in a vehicle.
    /// >20 mph is auto-excluded by the server; 13–20 is flagged for the user.
    private enum VehicleSuspicion { case none, flagged, excluded }
    private var vehicleSuspicion: VehicleSuspicion {
        let mph = averageSpeedMph
        if mph >= 20 { return .excluded }
        if mph >= 13 { return .flagged }
        return .none
    }

    // Timezone-corrected times from index
    private var correctedEndTime: Date {
        healthManager.getCorrectedLocalTime(for: workout)
    }

    private var correctedStartTime: Date {
        let endTime = correctedEndTime
        return endTime.addingTimeInterval(-workout.duration)
    }

    private var workoutTypeString: String {
        switch workout.workoutActivityType {
        case .running: return "Run"
        case .walking: return "Walk"
        case .cycling: return "Ride"
        default: return "Workout"
        }
    }

    private var workoutIcon: String {
        switch workout.workoutActivityType {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        default: return "figure.mixed.cardio"
        }
    }

    // Same accent per type as the feed (ActivityCardView.color) — one color
    // language for a workout everywhere it appears.
    private var workoutColor: Color {
        MADTheme.workoutColor(workout.workoutActivityType.madTypeKey)
    }

    private var distanceMiles: Double {
        workout.totalDistance?.doubleValue(for: .mile()) ?? 0
    }

    /// Look up the source from the WorkoutIndex by matching UUID
    private var workoutSource: WorkoutSource {
        healthManager.workoutRecord(forUUID: workout.uuid.uuidString)?.source ?? .healthkit
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea()

                // No entrance animation here on purpose. The sheet's own
                // presentation IS the animation; fading + sliding the content in
                // on top of it read as a second, mushier motion — and in the
                // pager it was inconsistent besides, since TabView builds
                // adjacent pages off-screen, so the reveal fired where nobody
                // could see it and swiped-to pages just appeared.
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        // Hero — type, hero distance, date, and route/photo tags.
                        heroCard

                        // The run's feed/story post, rendered exactly like the
                        // feed shows it (photo, route + stats, caption). Owner
                        // actions — edit caption, add to feed, delete — live
                        // in the card's menu + header pill.
                        linkedPostSection

                        // Route — pulled up front so a run with a GPS trace leads
                        // with the map (hidden when the post card above already
                        // carries the run's visuals — no double map).
                        if linkedPost == nil {
                            routeMapSection
                        }

                        // The numbers — one home, no repeats across cards.
                        statsSection

                        // Mile splits as a pace bar chart.
                        mileSplitsSection

                        // When it started and ended.
                        timelineCard

                        // Delete — remove an accidental / vehicle workout.
                        deleteButton
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .alert("Delete this workout?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { performDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the workout from Mile A Day and recalculates your streak and medals. Badges you only earned because of it will be removed. This can't be undone.")
            }
            .alert("Couldn't delete workout", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showEditSheet = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .foregroundColor(.orange)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(MADTheme.Colors.madRed)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditWorkoutView(
                    workoutId: workout.uuid.uuidString,
                    currentDistance: distanceMiles,
                    currentDuration: workout.duration,
                    currentWorkoutType: workoutTypeString == "Run" ? "running" : workoutTypeString == "Walk" ? "walking" : "running"
                )
            }
            .task(id: isActive) {
                // Only the on-screen page loads (the pager builds every page up
                // front). Photo FIRST so it shows immediately — when the list
                // handed us the post, skip the multi-page re-scan that used to
                // run last (why a "Photo" badge could sit blank for seconds).
                guard isActive else { return }
                if let preloadedPost {
                    linkedPost = preloadedPost
                } else {
                    await fetchLinkedPost()
                }
                await fetchRouteData()
                await fetchCalories()
                await fetchSplitTimes()
            }
            .sheet(item: $editingLinkedPost) { post in
                EditCaptionSheet(post: post) { newCaption in
                    linkedPost?.caption = newCaption
                }
            }
            .alert("Delete this post?", isPresented: $showPostDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteLinkedPost() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes it from your feed and profile for good. The workout itself stays.")
            }
            .alert("Couldn't add to feed", isPresented: Binding(
                get: { addToFeedError != nil },
                set: { if !$0 { addToFeedError = nil } }
            )) {
                Button("OK", role: .cancel) { addToFeedError = nil }
            } message: {
                Text(addToFeedError ?? "")
            }
        }
    }

    // MARK: - Linked feed post

    /// The linked post with this workout's GPS trace injected, so the card
    /// shows the same route + stats slide the feed does (the profile posts
    /// endpoint doesn't ship routes).
    private var displayLinkedPost: PostItem? {
        guard var post = linkedPost else { return nil }
        if post.route == nil, let coords = routeCoordinates, coords.count >= 2 {
            post.route = coords.map { [$0.latitude, $0.longitude] }
        }
        return post
    }

    @ViewBuilder
    private var linkedPostSection: some View {
        if let post = displayLinkedPost {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text(post.share_to_feed == false ? "Your Story" : "On the Feed")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    if post.share_to_feed == false {
                        addToFeedPill
                    }
                }

                PostCardView(
                    post: post,
                    storyPhotoURL: post.storyPhotoURL,
                    onHype: {},
                    onReport: {},
                    onBlock: {},
                    onDelete: { showPostDeleteConfirm = true },
                    onEditCaption: { editingLinkedPost = post }
                )
            }
        }
    }

    private var addToFeedPill: some View {
        Button {
            addLinkedPostToFeed()
        } label: {
            HStack(spacing: 4) {
                if isAddingToFeed {
                    ProgressView().tint(.white).scaleEffect(0.6)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .heavy))
                }
                Text("Add to feed")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(MADTheme.Colors.redGradient))
        }
        .buttonStyle(.plain)
        .disabled(isAddingToFeed)
    }

    private func fetchLinkedPost() async {
        guard let uid = UserManager.shared.currentUser.backendUserId else { return }
        let post = try? await PostService.fetchOwnPostForWorkout(
            workoutId: workout.uuid.uuidString, userId: uid
        )
        await MainActor.run { linkedPost = post }
    }

    private func deleteLinkedPost() {
        guard let post = linkedPost else { return }
        Task {
            try? await PostService.deletePost(postId: post.post_id)
            await MainActor.run { linkedPost = nil }
        }
    }

    private func addLinkedPostToFeed() {
        guard let post = linkedPost, !isAddingToFeed else { return }
        isAddingToFeed = true
        Task {
            do {
                try await PostService.addPostToFeed(postId: post.post_id)
                await fetchLinkedPost()
            } catch {
                await MainActor.run {
                    addToFeedError = "This run may already have a feed post."
                }
            }
            await MainActor.run { isAddingToFeed = false }
        }
    }

    // MARK: - Vehicle warning

    private var vehicleWarningBanner: some View {
        let excluded = vehicleSuspicion == .excluded
        return HStack(spacing: 10) {
            Image(systemName: "car.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(excluded ? .red : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(excluded ? "Not counted — vehicle speed" : "This pace looks unusually fast")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                Text(excluded
                    ? "This workout averages \(Int(averageSpeedMph)) mph, so it doesn't count toward your mile. Delete it to clear it out."
                    : "Averaging \(Int(averageSpeedMph)) mph. If you left tracking on in a car, delete it so it doesn't count.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill((excluded ? Color.red : Color.orange).opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder((excluded ? Color.red : Color.orange).opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                if isDeleting {
                    ProgressView().tint(.red)
                } else {
                    Image(systemName: "trash")
                }
                Text(isDeleting ? "Deleting…" : "Delete this workout")
                    .fontWeight(.semibold)
            }
            .font(.system(size: 15, design: .rounded))
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.red.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .disabled(isDeleting)
        .padding(.top, MADTheme.Spacing.sm)
    }

    private func performDelete() {
        guard !isDeleting else { return }
        isDeleting = true
        let id = workout.uuid.uuidString
        Task {
            do {
                let resp = try await workoutService.deleteWorkout(workoutId: id)
                await MainActor.run {
                    // Rebuild local data excluding the now-tombstoned workout so the
                    // dashboard/streak/calendar drop it immediately.
                    WorkoutIndex.clear()
                    healthManager.workoutIndex = nil
                    healthManager.fetchAllWorkoutData()
                    healthManager.fetchTodaysDistance()
                    if let streak = resp.currentStreak {
                        healthManager.retroactiveStreak = streak
                    }
                    isDeleting = false
                    dismiss()
                }
                // Pull fresh server-authoritative badges + challenge state.
                await UserManager.shared.refreshBadgesFromServer()
                if let uid = UserManager.shared.currentUser.backendUserId {
                    await ChallengeService.refresh(userId: uid)
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    deleteError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        WorkoutHeroCard(
            icon: workoutIcon,
            typeLabel: workoutTypeString,
            color: workoutColor,
            distanceText: workout.formattedDistance,
            dateText: correctedEndTime.formattedDate,
            source: workoutSource,
            hasRoute: heroHasRoute,
            hasPhoto: heroHasPhoto
        ) {
            // Vehicle-speed warning — surfaces a likely drive so the user can remove it.
            if vehicleSuspicion != .none {
                vehicleWarningBanner
            }
        }
    }

    /// Does this run have a drawable GPS trace (drives the hero "Route" tag).
    private var heroHasRoute: Bool {
        (routeCoordinates?.isEmpty == false)
    }

    /// Does the linked post carry a real user photo — a deliberate photo post
    /// or a distinct story picture, not just an auto-generated route/stats card.
    private var heroHasPhoto: Bool {
        guard let post = linkedPost else { return false }
        if post.storyPhotoURL != nil { return true }
        return post.is_auto != true && !post.media_url.isEmpty
    }

    // MARK: - Section header (shared across the detail's cards)

    private func sectionHeader(_ icon: String, _ title: String) -> some View {
        WorkoutDetailSectionHeader(icon: icon, title: title)
    }

    // MARK: - Stats

    /// The run's headline numbers, in ONE place — distance lives in the hero,
    /// everything else lives here (no more repeating pace/calories in a second
    /// "Performance" card).
    private var statsSection: some View {
        WorkoutStatsCard(
            duration: workout.formattedDuration,
            pace: workout.pace,
            calories: calories.map { Int($0) }
        )
    }

    // MARK: - Timeline Card

    private var timelineCard: some View {
        WorkoutTimelineCard(
            startText: correctedStartTime.formattedTime,
            endText: correctedEndTime.formattedTime
        )
    }

    // MARK: - Mile Splits

    @ViewBuilder
    private var mileSplitsSection: some View {
        if let splitTimes = splitTimes, !splitTimes.isEmpty {
            let fastest = splitTimes.min() ?? 0
            let slowest = splitTimes.max() ?? 0
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                sectionHeader("flag.checkered", "Mile Splits")

                VStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(Array(splitTimes.enumerated()), id: \.offset) { index, splitTime in
                        SplitBarRow(
                            mile: index + 1,
                            timeLabel: formatSplitTime(splitTime),
                            fraction: splitBarFraction(time: splitTime, fastest: fastest, slowest: slowest),
                            isFastest: splitTimes.count > 1 && splitTime == fastest,
                            color: workoutColor
                        )
                    }
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        } else if isLoadingSplits {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                sectionHeader("flag.checkered", "Mile Splits")

                HStack(spacing: MADTheme.Spacing.sm) {
                    ProgressView()
                        .tint(.secondary)
                        .scaleEffect(0.8)
                    Text("Loading splits...")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
    }

    /// Normalizes a split's time to a bar length: the fastest mile fills the
    /// bar, the slowest reads at 35% so every mile stays visible. A run with
    /// one split (or identical splits) fills fully.
    private func splitBarFraction(time: Double, fastest: Double, slowest: Double) -> CGFloat {
        guard slowest > fastest else { return 1 }
        let normalized = (time - fastest) / (slowest - fastest) // 0 fastest → 1 slowest
        return CGFloat(1 - normalized * 0.65)
    }

    // MARK: - Route Map

    @ViewBuilder
    private var routeMapSection: some View {
        if let routeCoordinates, !routeCoordinates.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                sectionHeader("map.fill", "Route")

                WorkoutRouteMapView(
                    coordinates: routeCoordinates,
                    routeColor: workoutColor
                )
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        } else if isLoadingRoute {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                sectionHeader("map.fill", "Route")

                HStack(spacing: MADTheme.Spacing.sm) {
                    ProgressView()
                        .tint(.secondary)
                        .scaleEffect(0.8)
                    Text("Loading route...")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
    }

    // MARK: - Data Fetching

    private func fetchRouteData() async {
        isLoadingRoute = true
        let locations = await healthManager.fetchAllRouteLocations(for: workout)
        routeCoordinates = locations.isEmpty ? nil : locations.map { $0.coordinate }
        isLoadingRoute = false
    }

    private func fetchSplitTimes() async {
        isLoadingSplits = true

        let healthManager = HealthKitManager()

        await withCheckedContinuation { continuation in
            healthManager.getWorkoutSplitTimes(for: workout) { splits in
                DispatchQueue.main.async {
                    self.splitTimes = splits
                    self.isLoadingSplits = false
                }
                continuation.resume()
            }
        }
    }

    private func formatSplitTime(_ splitTime: TimeInterval) -> String {
        let totalMinutes = splitTime
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)

        return String(format: "%d:%02d", minutes, seconds)
    }

    private func fetchCalories() async {
        let healthStore = HKHealthStore()
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        let query = HKStatisticsQuery(
            quantityType: energyType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, error in
            guard let result = result,
                  let sum = result.sumQuantity() else {
                return
            }

            let calories = sum.doubleValue(for: HKUnit.kilocalorie())
            DispatchQueue.main.async {
                self.calories = calories
            }
        }

        healthStore.execute(query)
    }
}

// MARK: - Supporting Components

struct DashboardStatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
            }

            Text(value)
                .font(MADTheme.Typography.headline)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.md)
        .padding(.horizontal, MADTheme.Spacing.sm)
        .madLiquidGlass()
    }
}

struct DetailRow: View {
    var icon: String? = nil
    var iconColor: Color = .secondary
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 20)
            }

            Text(title)
                .font(MADTheme.Typography.body)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(MADTheme.Typography.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(.vertical, MADTheme.Spacing.xs)
    }
}

// MARK: - Split Bar Row

/// One mile's split as a labelled bar — length encodes relative pace (the
/// fastest mile fills the bar). The fastest split is called out in green so a
/// glance reads the run's shape without parsing a column of times.
struct SplitBarRow: View {
    let mile: Int
    let timeLabel: String
    let fraction: CGFloat
    let isFastest: Bool
    let color: Color

    /// Animate the bar growing in the first time it appears.
    @State private var grown = false

    private var barColor: Color {
        isFastest ? MADTheme.Colors.success : color
    }

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Text("Mile \(mile)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 52, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [barColor.opacity(0.85), barColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * fraction * (grown ? 1 : 0)))
                }
            }
            .frame(height: 10)

            HStack(spacing: 5) {
                if isFastest {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(MADTheme.Colors.success)
                }
                Text(timeLabel)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(isFastest ? MADTheme.Colors.success : .primary)
            }
            .frame(width: 74, alignment: .trailing)
        }
        .onAppear {
            // All bars grow together — the old per-mile delay made them ripple
            // unevenly, which is what felt clunky.
            withAnimation(.easeOut(duration: 0.5)) {
                grown = true
            }
        }
    }
}
