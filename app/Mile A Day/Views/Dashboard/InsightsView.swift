import SwiftUI
import HealthKit

struct InsightsView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @Binding var showWorkouts: Bool

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea()
            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    RoadToMilestoneCard(
                        streak: userManager.currentUser.streak,
                        goalMiles: userManager.currentUser.goalMiles,
                        healthManager: healthManager
                    )

                    WeeklyMileChartView(healthManager: healthManager, userManager: userManager)
                    WeeklyTrendCard(healthManager: healthManager, userManager: userManager)

                    StatsGridView(user: userManager.currentUser, healthManager: healthManager)
                    RecentWorkoutsPreviewCard(healthManager: healthManager, showWorkouts: $showWorkouts)
                }
                .padding(MADTheme.Spacing.md)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Road to milestone

/// A scrollable map of the streak: every day is a dot on the road, today is the
/// oversized live node, future days climb toward the next club, and major clubs
/// appear as floating goal markers along the path.
private struct RoadToMilestoneCard: View {
    let streak: Int
    let goalMiles: Double
    @ObservedObject var healthManager: HealthKitManager

    private var goal: RoadMilestoneGoal? {
        RoadMilestoneGoal.next(after: streak)
    }

    /// Highest major milestone the runner has already passed (0 if none yet).
    private var prevReachedDay: Int {
        StreakMilestone.displayLadder
            .filter { $0 <= streak }
            .max() ?? 0
    }

    var body: some View {
        NavigationLink {
            RoadToMilestoneDetailView(
                streak: streak,
                goal: goal,
                headerSubtitle: headerSubtitle,
                goalProgress: goalProgress,
                nodes: nodes
            )
        } label: {
            compactCard
        }
        .buttonStyle(.plain)
    }

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("THE ROAD TO \(goal?.value ?? max(streak, 1))")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(.white)
                    Text(headerSubtitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                progressRing
            }

            CompactRoadPreview(nodes: previewNodes)
                .frame(height: 86)

            HStack(spacing: 10) {
                compactLegend
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Text("Open road")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(.orange)
            }
        }
        .padding(18)
        .background(roadCardBackground(cornerRadius: 24))
    }

    private var previewNodes: [RoadDayNode] {
        Array(nodes.drop(while: { $0.isFuture }).prefix(5))
    }

    private var compactLegend: some View {
        HStack(spacing: 10) {
            RoadLegendItem(color: MADTheme.Colors.madRed, label: "Run")
            RoadLegendItem(color: MADTheme.Colors.walkBlue, label: "Walk")
            RoadLegendSplitItem(label: "Both")
        }
    }

    private func roadCardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.025, green: 0.024, blue: 0.034),
                        Color(red: 0.055, green: 0.035, blue: 0.05),
                        Color(red: 0.025, green: 0.022, blue: 0.032)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RadialGradient(
                    colors: [MADTheme.Colors.madRed.opacity(0.16), Color.clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 260
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("THE ROAD TO \(goal?.value ?? max(streak, 1))")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .tracking(1.6)
                    .foregroundColor(.white)
                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(spacing: 7) {
                progressRing
                if let goal {
                    Text("\(goal.daysToGo)d")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(.orange.opacity(0.82))
                }
            }
        }
    }

    private var headerSubtitle: String {
        guard let goal else { return "Every club conquered — you're in legendary territory." }
        let daysToGo = goal.daysToGo
        if daysToGo == 0 { return "You just hit Day \(goal.value) — keep the fire alive." }
        return "\(daysToGo) day\(daysToGo == 1 ? "" : "s") to Day \(goal.value)"
    }

    private var progressRing: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 5)
            Circle()
                .trim(from: 0, to: goalProgress)
                .stroke(
                    LinearGradient(colors: [MADTheme.Colors.madRed, .orange], startPoint: .top, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: MADTheme.Colors.madRed.opacity(0.4), radius: 5)
            Image(systemName: "flag.checkered")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.orange)
        }
        .frame(width: 48, height: 48)
    }

    private var goalProgress: CGFloat {
        guard let goal else { return 1 }
        let span = max(goal.value - prevReachedDay, 1)
        return CGFloat(max(0, min(Double(streak - prevReachedDay) / Double(span), 1)))
    }

    // MARK: Road model

    private var topDay: Int {
        max(goal?.value ?? streak, max(streak, 1))
    }

    private var nodes: [RoadDayNode] {
        let milestones = Dictionary(uniqueKeysWithValues: StreakMilestone.allCases.map { ($0.days, $0) })
        let today = Calendar.current.startOfDay(for: Date())
        let current = max(streak, 0)
        let bottomDay = current == 0 ? 0 : 1

        return stride(from: topDay, through: bottomDay, by: -1).map { day in
            let isFuture = day > current
            let date = isFuture ? nil : Calendar.current.date(byAdding: .day, value: day - current, to: today)
            let resolved = date.map { dayData(for: $0, dayNumber: day) } ?? RoadDayData(distance: 0, activity: .future, workouts: [])
            let milestone = milestones[day]

            return RoadDayNode(
                day: day,
                date: date,
                distance: resolved.distance,
                activity: isFuture ? .future : resolved.activity,
                workouts: resolved.workouts,
                milestone: milestone,
                isCurrent: day == current,
                isFuture: isFuture,
                isGoal: day == goal?.value,
                daysFromCurrent: day - current,
                goalMiles: goalMiles
            )
        }
    }

    private func dayData(for date: Date, dayNumber: Int) -> RoadDayData {
        let records = healthManager.workoutIndex?.workouts(for: date) ?? []
        let workouts = workouts(on: date, matching: records)
        let workoutDistance = workouts.reduce(0.0) { total, workout in
            total + (workout.totalDistance?.doubleValue(for: .mile()) ?? 0)
        }
        let indexedDistance = records.reduce(0) { $0 + $1.distance }
        let todaysDistance = dayNumber == streak ? healthManager.todaysDistance : 0
        let measuredDistance = max(workoutDistance, indexedDistance, todaysDistance)
        let distance = measuredDistance > 0 ? measuredDistance : (dayNumber < streak ? goalMiles : 0)
        let activity = activityType(for: dayNumber, records: records, workouts: workouts, distance: distance)

        return RoadDayData(distance: distance, activity: activity, workouts: workouts)
    }

    private func workouts(on date: Date, matching records: [WorkoutRecord]) -> [HKWorkout] {
        let ids = Set(records.map(\.id))
        if !ids.isEmpty {
            let matched = healthManager.cachedWorkouts.filter { ids.contains($0.uuid.uuidString) }
            if !matched.isEmpty { return matched }
        }

        let calendar = Calendar.current
        return healthManager.cachedWorkouts.filter {
            calendar.isDate(healthManager.getCorrectedLocalTime(for: $0), inSameDayAs: date)
        }
    }

    private func activityType(for day: Int, records: [WorkoutRecord], workouts: [HKWorkout], distance: Double) -> RoadActivity {
        var hasRun = records.contains { $0.workoutType.lowercased() == "running" }
        var hasWalk = records.contains { $0.workoutType.lowercased() == "walking" }

        hasRun = hasRun || workouts.contains { $0.workoutActivityType == .running }
        hasWalk = hasWalk || workouts.contains { $0.workoutActivityType == .walking }

        if day == streak {
            hasRun = hasRun || healthManager.todaysWorkouts.contains { $0.workoutActivityType == .running }
            hasWalk = hasWalk || healthManager.todaysWorkouts.contains { $0.workoutActivityType == .walking }
        }

        if hasRun && hasWalk { return .both }
        if hasRun { return .run }
        if hasWalk { return .walk }
        if day == streak { return distance >= max(goalMiles * 0.95, 0.95) ? .walk : .today }
        return day <= streak ? .walk : .future
    }
}

private struct RoadDayData {
    let distance: Double
    let activity: RoadActivity
    let workouts: [HKWorkout]
}

private struct RoadMilestoneGoal {
    let value: Int
    let progress: Double
    let daysToGo: Int

    static func next(after streak: Int) -> RoadMilestoneGoal? {
        guard let next = StreakMilestone.next(after: streak) else { return nil }
        return RoadMilestoneGoal(value: next.value, progress: next.progress, daysToGo: next.daysToGo)
    }
}

private enum RoadActivity {
    case run, walk, both, today, future
}

private struct RoadDayNode: Identifiable {
    var id: Int { day }
    let day: Int
    let date: Date?
    let distance: Double
    let activity: RoadActivity
    let workouts: [HKWorkout]
    let milestone: StreakMilestone?
    let isCurrent: Bool
    let isFuture: Bool
    let isGoal: Bool
    let daysFromCurrent: Int
    let goalMiles: Double

    var activityLabel: String {
        switch activity {
        case .run: return "Run"
        case .walk: return "Walk"
        case .both: return "Run + walk"
        case .today: return "In progress"
        case .future: return "Locked"
        }
    }

    var title: String {
        if isCurrent { return "Today" }
        if let milestone, milestone.isMajor { return "\(milestone.days) Club" }
        if isFuture { return "Day \(day)" }
        return "Day \(day)"
    }

    var subtitle: String {
        if isFuture {
            return isGoal ? "Next goal" : "Ahead"
        }
        if let date {
            return RoadDateFormatter.short.string(from: date)
        }
        return "Current road"
    }

    var distanceToken: String {
        if distance >= 10 {
            return String(format: "%.0f", distance)
        }
        return String(format: "%.1f", distance)
    }

}

private enum RoadDateFormatter {
    static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static let year: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
}

private struct RoadToMilestoneDetailView: View {
    let streak: Int
    let goal: RoadMilestoneGoal?
    let headerSubtitle: String
    let goalProgress: CGFloat
    let nodes: [RoadDayNode]

    @State private var selectedDay: RoadDayNode?

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.034, blue: 0.045).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                detailHeader
                detailLegend
                futureGoalsStrip

                RoadMapViewport(nodes: nodes, streak: streak, selectedDay: $selectedDay)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .navigationTitle("Road")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $selectedDay) { day in
            RoadDayDetailSheet(day: day)
                .presentationDetents(day.workouts.isEmpty ? [.height(300)] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var detailHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("THE ROAD TO \(goal?.value ?? max(streak, 1))")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.62))
            }

            Spacer(minLength: 10)

            VStack(spacing: 5) {
                RoadProgressRing(progress: goalProgress)
                    .frame(width: 48, height: 48)
                if let goal {
                    Text("\(goal.daysToGo)d")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(.orange.opacity(0.82))
                }
            }
        }
        .padding(18)
        .background(roadPanelBackground(cornerRadius: 22))
    }

    private var detailLegend: some View {
        HStack(spacing: 12) {
            RoadLegendItem(color: MADTheme.Colors.madRed, label: "Run")
            RoadLegendItem(color: MADTheme.Colors.walkBlue, label: "Walk")
            RoadLegendSplitItem(label: "Both")
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 4)
    }

    private var futureGoalsStrip: some View {
        let futureGoals = StreakMilestone.displayLadder
            .filter { $0 > streak }
            .prefix(4)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(futureGoals), id: \.self) { milestoneDay in
                    HStack(spacing: 7) {
                        Image(systemName: milestoneDay == goal?.value ? "flag.fill" : "lock.open.fill")
                            .font(.system(size: 10, weight: .black))
                        Text("\(milestoneDay)")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                        Text(milestoneDay == goal?.value ? "next" : "ahead")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .foregroundColor(milestoneDay == goal?.value ? .orange : .white.opacity(0.72))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(milestoneDay == goal?.value ? 0.08 : 0.045)))
                    .overlay(Capsule().strokeBorder((milestoneDay == goal?.value ? Color.orange : Color.white).opacity(0.16), lineWidth: 1))
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 34)
    }
}

private struct CompactRoadPreview: View {
    let nodes: [RoadDayNode]

    var body: some View {
        GeometryReader { geo in
            let points = previewPoints(in: geo.size)
            ZStack {
                previewPath(points)
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange, MADTheme.Colors.madRed],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: MADTheme.Colors.madRed.opacity(0.22), radius: 8, y: 4)

                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    CompactRoadDot(node: node)
                        .position(points[index])
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func previewPoints(in size: CGSize) -> [CGPoint] {
        guard !nodes.isEmpty else { return [] }
        let step = nodes.count == 1 ? 0 : size.width / CGFloat(nodes.count - 1)
        return nodes.indices.map { index in
            let x = CGFloat(index) * step
            let y = size.height * (0.54 + CGFloat(sin(Double(index) * 1.05)) * 0.22)
            return CGPoint(x: min(max(x, 16), size.width - 16), y: y)
        }
    }

    private func previewPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: current, control: CGPoint(x: mid.x, y: previous.y))
        }
        return path
    }
}

private struct CompactRoadDot: View {
    let node: RoadDayNode

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                compactFill
                    .frame(width: node.isCurrent ? 42 : 34, height: node.isCurrent ? 42 : 34)
                    .overlay(Circle().strokeBorder(Color.white.opacity(node.isCurrent ? 0.92 : 0.42), lineWidth: node.isCurrent ? 2.4 : 1.4))

                Text(node.isFuture ? "" : node.distanceToken)
                    .font(.system(size: node.isCurrent ? 11 : 10, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .shadow(color: compactShadow, radius: node.isCurrent ? 9 : 4, y: 2)

            Text(node.isCurrent ? "Today" : "\(node.day)")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundColor(node.isCurrent ? .white.opacity(0.78) : .white.opacity(0.42))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var compactFill: some View {
        if node.activity == .both {
            HStack(spacing: 0) {
                MADTheme.Colors.madRed
                MADTheme.Colors.walkBlue
            }
            .clipShape(Circle())
        } else {
            Circle().fill(compactColor)
        }
    }

    private var compactColor: Color {
        switch node.activity {
        case .run: return MADTheme.Colors.madRed
        case .walk: return MADTheme.Colors.walkBlue
        case .both: return .orange
        case .today: return .orange
        case .future: return .white.opacity(0.16)
        }
    }

    private var compactShadow: Color {
        switch node.activity {
        case .run: return MADTheme.Colors.madRed.opacity(0.32)
        case .walk: return MADTheme.Colors.walkBlue.opacity(0.32)
        case .both: return Color.orange.opacity(0.32)
        case .today: return MADTheme.Colors.madRed.opacity(0.26)
        case .future: return .clear
        }
    }
}

private struct RoadProgressRing: View {
    let progress: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [MADTheme.Colors.madRed, .orange], startPoint: .top, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: MADTheme.Colors.madRed.opacity(0.4), radius: 5)
            Image(systemName: "flag.checkered")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.orange)
        }
    }
}

private func roadPanelBackground(cornerRadius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.024, blue: 0.034),
                    Color(red: 0.055, green: 0.035, blue: 0.05),
                    Color(red: 0.025, green: 0.022, blue: 0.032)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
}

private struct RoadMapViewport: View {
    let nodes: [RoadDayNode]
    let streak: Int
    @Binding var selectedDay: RoadDayNode?
    @State private var focusedDateMarker: RoadDateMarker?

    private let rowSpacing: CGFloat = 66
    private let todayGap: CGFloat = 164
    private let topInset: CGFloat = 130
    private let dateRailWidth: CGFloat = 140

    private var currentID: Int {
        nodes.first(where: \.isCurrent)?.id ?? streak
    }

    private var currentIndex: Int {
        nodes.firstIndex(where: \.isCurrent) ?? 0
    }

    private var todayScrollTargetY: CGFloat {
        max(0, topInset + yOffset(for: currentIndex) - 92)
    }

    private var currentDateMarker: RoadDateMarker? {
        guard let node = nodes.first(where: \.isCurrent), let date = node.date else { return nil }
        return RoadDateMarker(day: node.day, date: date, isCurrent: true, minY: 0)
    }

    private var shouldShowTodayButton: Bool {
        guard let marker = focusedDateMarker else { return false }
        return marker.day != currentID
    }

    var body: some View {
        GeometryReader { viewport in
            let viewportHeight = max(viewport.size.height, 1)
            let contentHeight = mapHeight(for: viewportHeight)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        GeometryReader { geo in
                            let points = points(in: geo.size.width)
                            ZStack(alignment: .topLeading) {
                                RoadPathLayer(nodes: nodes, points: points)

                                ForEach(nodes) { node in
                                    if let point = point(for: node, in: points) {
                                        RoadDayButton(node: node) {
                                            selectedDay = node
                                        }
                                        .position(point)
                                    }
                                }

                                ForEach(nodes.filter { !$0.isFuture && $0.date != nil }) { node in
                                    if let point = point(for: node, in: points) {
                                        RoadDateMarkerProbe(node: node)
                                            .position(x: 1, y: point.y)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                        }
                        .frame(height: contentHeight)

                        VStack(spacing: 0) {
                            Color.clear.frame(height: todayScrollTargetY)
                            Color.clear
                                .frame(width: 1, height: 1)
                                .id("today-scroll-target")
                            Color.clear.frame(height: max(contentHeight - todayScrollTargetY - 1, 0))
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(height: contentHeight)
                }
                .coordinateSpace(name: RoadScrollSpace.name)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.24))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let marker = focusedDateMarker ?? currentDateMarker {
                        RoadDateScrubberPill(marker: marker)
                            .padding(.top, 12)
                            .padding(.trailing, 10)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if shouldShowTodayButton {
                        Button {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                proxy.scrollTo("today-scroll-target", anchor: .top)
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 12, weight: .black))
                                Text("Today")
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [MADTheme.Colors.madRed, Color.orange],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                            .shadow(color: MADTheme.Colors.madRed.opacity(0.35), radius: 14, y: 6)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .onPreferenceChange(RoadDateMarkerPreferenceKey.self) { markers in
                    focusedDateMarker = focusedMarker(from: markers, viewportHeight: viewportHeight)
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo("today-scroll-target", anchor: .top)
                    }
                }
                .task(id: currentID) {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    await MainActor.run {
                        proxy.scrollTo("today-scroll-target", anchor: .top)
                    }
                }
            }
        }
    }

    private func bottomInset(for viewportHeight: CGFloat) -> CGFloat {
        min(max(viewportHeight * 0.24, 180), 300)
    }

    private func mapHeight(for viewportHeight: CGFloat) -> CGFloat {
        topInset + bottomInset(for: viewportHeight) + yOffset(for: max(nodes.count - 1, 0))
    }

    private func points(in width: CGFloat) -> [Int: CGPoint] {
        var output: [Int: CGPoint] = [:]
        let minX: CGFloat = 48
        let railWidth = min(dateRailWidth, max(126, width * 0.34))
        let maxX = max(minX, width - railWidth)
        let center = (minX + maxX) / 2
        let amplitude = max(38, min(88, (maxX - minX) * 0.42))

        for (index, node) in nodes.enumerated() {
            let phase = Double(index) * 0.48
            let drift = sin(phase) * amplitude + sin(Double(index) * 0.13) * 18
            let x = max(minX, min(maxX, center + drift))
            let y = topInset + yOffset(for: index)
            output[node.id] = CGPoint(x: x, y: y)
        }
        return output
    }

    private func yOffset(for index: Int) -> CGFloat {
        guard index > currentIndex else {
            return CGFloat(index) * rowSpacing
        }

        let pastIndex = index - currentIndex
        return CGFloat(currentIndex) * rowSpacing + todayGap + CGFloat(max(pastIndex - 1, 0)) * rowSpacing
    }

    private func point(for node: RoadDayNode, in points: [Int: CGPoint]) -> CGPoint? {
        points[node.id]
    }

    private func focusedMarker(from markers: [RoadDateMarker], viewportHeight: CGFloat) -> RoadDateMarker? {
        let visible = markers.filter { $0.minY > -80 && $0.minY < viewportHeight + 80 }
        if let current = visible.first(where: \.isCurrent) {
            return current
        }
        return (visible.isEmpty ? markers : visible)
            .max { $0.minY < $1.minY }
    }

}

private enum RoadScrollSpace {
    static let name = "road-map-scroll-space"
}

private struct RoadDateMarker: Equatable {
    let day: Int
    let date: Date
    let isCurrent: Bool
    let minY: CGFloat
}

private struct RoadDateMarkerPreferenceKey: PreferenceKey {
    static var defaultValue: [RoadDateMarker] = []

    static func reduce(value: inout [RoadDateMarker], nextValue: () -> [RoadDateMarker]) {
        value.append(contentsOf: nextValue())
    }
}

private struct RoadDateMarkerProbe: View {
    let node: RoadDayNode

    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: RoadDateMarkerPreferenceKey.self,
                value: marker(in: geo)
            )
        }
        .frame(width: 1, height: 1)
    }

    private func marker(in geo: GeometryProxy) -> [RoadDateMarker] {
        guard let date = node.date else { return [] }
        return [
            RoadDateMarker(
                day: node.day,
                date: date,
                isCurrent: node.isCurrent,
                minY: geo.frame(in: .named(RoadScrollSpace.name)).minY
            )
        ]
    }
}

private struct RoadDateScrubberPill: View {
    let marker: RoadDateMarker

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(marker.isCurrent ? "Today" : RoadDateFormatter.weekday.string(from: marker.date))
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(0.7)
                .foregroundColor(.white.opacity(0.58))
                .lineLimit(1)

            Text(RoadDateFormatter.monthDay.string(from: marker.date))
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(RoadDateFormatter.year.string(from: marker.date))
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
                .lineLimit(1)
        }
        .frame(width: 86, alignment: .trailing)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.black.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder((marker.isCurrent ? MADTheme.Colors.madRed : Color.white).opacity(marker.isCurrent ? 0.26 : 0.10), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 12, y: 6)
    }
}

private struct RoadPathLayer: View {
    let nodes: [RoadDayNode]
    let points: [Int: CGPoint]

    var body: some View {
        let ordered = nodes.compactMap { points[$0.id] }
        let currentIndex = nodes.firstIndex(where: \.isCurrent) ?? 0
        let futurePoints = Array(ordered.prefix(currentIndex + 1))
        let travelledPoints = Array(ordered.suffix(max(ordered.count - currentIndex, 0)))

        ZStack {
            path(ordered)
                .stroke(Color.white.opacity(0.11), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [2, 12]))

            path(futurePoints)
                .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [2, 12]))

            path(travelledPoints)
                .stroke(MADTheme.Colors.madRed.opacity(0.20), style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                .blur(radius: 9)

            path(travelledPoints)
                .stroke(
                    LinearGradient(
                        colors: [Color.orange, MADTheme.Colors.madRed, Color(red: 0.95, green: 0.25, blue: 0.52)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
        }
    }

    private func path(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        guard points.count > 1 else { return path }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: CGPoint(x: previous.x, y: mid.y))
            path.addQuadCurve(to: current, control: CGPoint(x: current.x, y: mid.y))
        }
        return path
    }
}

private struct RoadDayButton: View {
    let node: RoadDayNode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoadDayDot(node: node)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if node.isFuture {
            return "Day \(node.day), locked"
        }
        return "Day \(node.day), \(node.activityLabel), \(String(format: "%.2f", node.distance)) miles"
    }
}

private struct RoadDayDot: View {
    let node: RoadDayNode

    private var diameter: CGFloat {
        if node.isCurrent { return 92 }
        if node.isGoal { return 42 }
        if node.milestone?.isMajor == true { return 46 }
        if node.isFuture { return 22 }
        return max(34, min(52, 30 + CGFloat(sqrt(max(node.distance, 0))) * 8))
    }

    private var distanceFontSize: CGFloat {
        diameter >= 46 ? 12 : 10
    }

    var body: some View {
        ZStack {
            if node.isCurrent {
                Circle()
                    .fill(currentGlowColor.opacity(0.35))
                    .frame(width: diameter + 36, height: diameter + 36)
                    .blur(radius: 14)
            }

            dotBody
                .frame(width: diameter, height: diameter)

            if node.isCurrent {
                currentLabel
            } else if let milestone = node.milestone, milestone.isMajor, !node.isFuture {
                distanceLabel
            } else if node.isGoal {
                Image(systemName: "flag.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(.orange)
            } else if !node.isFuture {
                distanceLabel
            }
        }
        .overlay(alignment: .bottom) {
            if shouldShowDayLabel {
                Text(dayLabel)
                    .font(.system(size: node.isCurrent ? 10 : 9, weight: .black, design: .rounded))
                    .foregroundColor(node.isCurrent ? .white.opacity(0.72) : .white.opacity(0.42))
                    .offset(y: node.isCurrent ? 18 : 17)
                    .lineLimit(1)
            }
        }
        .shadow(color: shadowColor, radius: node.isFuture ? 0 : (node.isCurrent ? 22 : 8), y: 3)
    }

    @ViewBuilder
    private var dotBody: some View {
        if node.isFuture {
            Circle()
                .fill(Color.black.opacity(0.45))
                .overlay(Circle().strokeBorder(Color.white.opacity(node.isGoal ? 0.26 : 0.15), style: StrokeStyle(lineWidth: 2, dash: [4, 4])))
        } else if node.activity == .both {
            ZStack {
                HStack(spacing: 0) {
                    MADTheme.Colors.madRed
                    MADTheme.Colors.walkBlue
                }
                .clipShape(Circle())
                Circle().strokeBorder(Color.white.opacity(node.isCurrent ? 0.92 : 0.38), lineWidth: node.isCurrent ? 3 : 1.8)
            }
        } else {
            Circle()
                .fill(dotFill)
                .overlay(Circle().strokeBorder(Color.white.opacity(node.isCurrent ? 0.92 : 0.34), lineWidth: node.isCurrent ? 3 : 1.5))
        }
    }

    private var dotFill: AnyShapeStyle {
        switch node.activity {
        case .run:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.44, blue: 0.30), MADTheme.Colors.madRed], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .walk:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.35, green: 0.82, blue: 1.0), MADTheme.Colors.walkBlue], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .today:
            return AnyShapeStyle(LinearGradient(colors: [Color.orange, MADTheme.Colors.madRed], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .both:
            return AnyShapeStyle(Color.orange)
        case .future:
            return AnyShapeStyle(Color.white.opacity(0.08))
        }
    }

    private var currentLabel: some View {
        VStack(spacing: 1) {
            Text("TODAY")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.78))
            Text(String(format: "%.2f", node.distance))
                .font(.system(size: 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
            Text("MI")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.72))
        }
    }

    private var distanceLabel: some View {
        VStack(spacing: -1) {
            Text(node.distanceToken)
                .font(.system(size: distanceFontSize, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text("MI")
                .font(.system(size: 6.5, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.68))
        }
    }

    private var currentGlowColor: Color {
        switch node.activity {
        case .walk: return MADTheme.Colors.walkBlue
        case .both: return .orange
        default: return MADTheme.Colors.madRed
        }
    }

    private var shadowColor: Color {
        switch node.activity {
        case .run: return MADTheme.Colors.madRed.opacity(0.45)
        case .walk: return MADTheme.Colors.walkBlue.opacity(0.45)
        case .both: return Color.orange.opacity(0.48)
        case .today: return MADTheme.Colors.madRed.opacity(0.45)
        case .future: return .clear
        }
    }

    private var shouldShowDayLabel: Bool {
        node.isGoal || node.milestone?.isMajor == true || (!node.isCurrent && node.day % 25 == 0)
    }

    private var dayLabel: String {
        if node.isGoal { return "GOAL" }
        if let milestone = node.milestone, milestone.isMajor { return "\(milestone.days)" }
        return "\(node.day)"
    }
}

private struct RoadLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.58))
        }
    }
}

private struct RoadLegendSplitItem: View {
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 0) {
                MADTheme.Colors.madRed
                MADTheme.Colors.walkBlue
            }
            .clipShape(Circle())
            .frame(width: 8, height: 8)

            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.58))
        }
    }
}

private struct RoadDayDetailSheet: View {
    let day: RoadDayNode
    @State private var selectedWorkoutIndex: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.045, blue: 0.06).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .center, spacing: 14) {
                            RoadDayDot(node: day)
                                .frame(width: 96, height: 96)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(day.title.uppercased())
                                    .font(.system(size: 19, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                Text(day.subtitle)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.58))
                            }
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            RoadDetailStat(title: "Distance", value: day.isFuture ? "--" : String(format: "%.2f mi", day.distance))
                            RoadDetailStat(title: "Type", value: day.activityLabel)
                        }

                        if !day.workouts.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(day.workouts.count == 1 ? "Workout" : "Workouts")
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .tracking(1.1)
                                    .foregroundColor(.white.opacity(0.46))

                                ForEach(Array(day.workouts.enumerated()), id: \.element.uuid) { index, workout in
                                    Button {
                                        selectedWorkoutIndex = index
                                    } label: {
                                        RoadWorkoutSummaryRow(workout: workout)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else if !day.isFuture && !day.isCurrent {
                            RoadNoWorkoutDetailNote()
                        }
                    }
                    .padding(22)
                }
            }
            .navigationTitle(day.isCurrent ? "Today" : day.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { selectedWorkoutIndex != nil },
                set: { isPresented in
                    if !isPresented { selectedWorkoutIndex = nil }
                }
            )
        ) {
            if let selectedWorkoutIndex {
                WorkoutPagerView(workouts: day.workouts, startIndex: selectedWorkoutIndex)
            }
        }
    }
}

private struct RoadWorkoutSummaryRow: View {
    let workout: HKWorkout

    private var typeKey: String {
        workout.workoutActivityType.madTypeKey
    }

    private var typeTitle: String {
        switch workout.workoutActivityType {
        case .running: return "Run"
        case .walking: return "Walk"
        default: return "Workout"
        }
    }

    private var distance: Double {
        workout.totalDistance?.doubleValue(for: .mile()) ?? 0
    }

    private var durationText: String {
        let total = Int(workout.duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var paceText: String {
        guard distance > 0 else { return "--" }
        let secondsPerMile = workout.duration / distance
        let minutes = Int(secondsPerMile) / 60
        let seconds = Int(secondsPerMile) % 60
        return String(format: "%d'%02d\"/mi", minutes, seconds)
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: workout.startDate)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(MADTheme.workoutColor(typeKey).opacity(0.18))
                Image(systemName: workout.workoutActivityType == .running ? "figure.run" : "figure.walk")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(MADTheme.workoutColor(typeKey))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(typeTitle)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.2f mi", distance))
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(MADTheme.workoutColor(typeKey))
                }

                HStack(spacing: 10) {
                    RoadMiniMetric(text: timeText, icon: "clock")
                    RoadMiniMetric(text: durationText, icon: "timer")
                    RoadMiniMetric(text: paceText, icon: "speedometer")
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .black))
                .foregroundColor(.white.opacity(0.28))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}

private struct RoadMiniMetric: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundColor(.white.opacity(0.55))
    }
}

private struct RoadNoWorkoutDetailNote: View {
    var body: some View {
        Text("This day counted toward your streak, but the local workout detail is still syncing.")
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.52))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            )
    }
}

private struct RoadDetailStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}
