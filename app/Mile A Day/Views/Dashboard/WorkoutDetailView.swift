import SwiftUI
import HealthKit
import MapKit

// MARK: - Workout Detail View

struct WorkoutDetailView: View {
    let workout: HKWorkout
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

    private var workoutColor: Color {
        switch workout.workoutActivityType {
        case .running: return MADTheme.Colors.madRed
        case .walking: return .blue
        case .cycling: return .green
        default: return .purple
        }
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

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        // Hero card — type, distance, date
                        heroCard

                        // Route map (only shown for outdoor workouts with GPS data)
                        routeMapSection

                        // Key stats row
                        keyStatsRow

                        // Timeline details card
                        timelineCard

                        // Performance details card
                        performanceCard

                        // Mile Splits Section
                        mileSplitsSection

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
            .task {
                await fetchCalories()
                await fetchSplitTimes()
                await fetchRouteData()
            }
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
        VStack(spacing: MADTheme.Spacing.md) {
            // Manual/edited warning banner
            if workoutSource != .healthkit {
                ManualWorkoutBanner(source: workoutSource)
            }

            // Vehicle-speed warning — surfaces a likely drive so the user can remove it.
            if vehicleSuspicion != .none {
                vehicleWarningBanner
            }

            // Workout type badge
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: workoutIcon)
                    .font(.system(size: 14, weight: .semibold))
                Text(workoutTypeString)
                    .font(MADTheme.Typography.smallBold)
            }
            .foregroundColor(workoutColor)
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.xs + 2)
            .background(
                Capsule()
                    .fill(workoutColor.opacity(0.15))
            )

            // Distance — the hero number
            Text(workout.formattedDistance)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            // Date
            Text(correctedEndTime.formattedDate)
                .font(MADTheme.Typography.body)
                .foregroundColor(.secondary)
        }
        .padding(MADTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .madLiquidGlass()
    }

    // MARK: - Key Stats Row

    private var keyStatsRow: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            DashboardStatBox(
                title: "Duration",
                value: workout.formattedDuration,
                icon: "clock.fill",
                color: .orange
            )

            DashboardStatBox(
                title: "Pace",
                value: workout.pace,
                icon: "speedometer",
                color: .green
            )

            if let calories = calories {
                DashboardStatBox(
                    title: "Calories",
                    value: "\(Int(calories))",
                    icon: "flame.fill",
                    color: MADTheme.Colors.madRed
                )
            }
        }
    }

    // MARK: - Timeline Card

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Timeline")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
            }

            DetailRow(icon: "play.fill", iconColor: .green, title: "Start", value: correctedStartTime.formattedTime)
            DetailRow(icon: "stop.fill", iconColor: MADTheme.Colors.madRed, title: "End", value: correctedEndTime.formattedTime)
            DetailRow(icon: "timer", iconColor: .orange, title: "Duration", value: workout.formattedDuration)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    // MARK: - Performance Card

    private var performanceCard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Performance")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
            }

            DetailRow(icon: "point.topleft.down.to.point.bottomright.curvepath.fill", iconColor: .blue, title: "Distance", value: workout.formattedDistance)
            DetailRow(icon: "speedometer", iconColor: .green, title: "Avg Pace", value: workout.pace)
            if let calories = calories {
                DetailRow(icon: "flame.fill", iconColor: MADTheme.Colors.madRed, title: "Calories", value: "\(Int(calories)) kcal")
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    // MARK: - Mile Splits

    @ViewBuilder
    private var mileSplitsSection: some View {
        if let splitTimes = splitTimes, !splitTimes.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text("Mile Splits")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                }

                let fastestIndex = splitTimes.enumerated().min(by: { $0.element < $1.element })?.offset

                ForEach(Array(splitTimes.enumerated()), id: \.offset) { index, splitTime in
                    let isFastest = index == fastestIndex && splitTimes.count > 1
                    HStack {
                        HStack(spacing: MADTheme.Spacing.sm) {
                            Text("Mile \(index + 1)")
                                .font(MADTheme.Typography.body)
                                .foregroundColor(.primary)

                            if isFastest {
                                Text("Fastest")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundColor(MADTheme.Colors.success)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(MADTheme.Colors.success.opacity(0.15))
                                    )
                            }
                        }

                        Spacer()

                        Text(formatSplitTime(splitTime))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(isFastest ? MADTheme.Colors.success : .primary)
                    }
                    .padding(.vertical, MADTheme.Spacing.xs)

                    if index < splitTimes.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.06))
                    }
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        } else if isLoadingSplits {
            VStack(spacing: MADTheme.Spacing.md) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text("Mile Splits")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                    Spacer()
                }

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

    // MARK: - Route Map

    @ViewBuilder
    private var routeMapSection: some View {
        if let routeCoordinates, !routeCoordinates.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text("Route")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                }

                WorkoutRouteMapView(
                    coordinates: routeCoordinates,
                    routeColor: workoutColor
                )
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        } else if isLoadingRoute {
            VStack(spacing: MADTheme.Spacing.md) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text("Route")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                    Spacer()
                }

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
