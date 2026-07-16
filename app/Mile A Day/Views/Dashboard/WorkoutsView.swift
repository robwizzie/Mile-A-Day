import SwiftUI
import HealthKit

/// A dedicated home for a user's runs: a month calendar (completed days lit in
/// the same language as the streak calendar) plus the selected day's workouts.
/// Tapping a workout opens a swipeable detail (WorkoutPagerView) so you can flick
/// through that day's runs. Reached from the Dashboard's "Recent Workouts" card.
struct WorkoutsView: View {
    @ObservedObject var healthManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss

    private enum Mode: Hashable { case calendar, list }
    @State private var mode: Mode = .calendar
    @State private var month: Date = Date()
    @State private var selectedDay: Date?
    @State private var selectedWorkout: IdentifiableWorkout?
    /// workoutId → linked post, batched once so tapping a run shows its photo
    /// instantly and the calendar rows can badge photos.
    @State private var postsByWorkout: [String: PostItem] = [:]
    @State private var didPickDefaultDay = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        Picker("View", selection: $mode) {
                            Text("Calendar").tag(Mode.calendar)
                            Text("List").tag(Mode.list)
                        }
                        .pickerStyle(.segmented)

                        if mode == .calendar {
                            calendarCard
                            selectedDaySection
                        } else {
                            RecentWorkoutsView(workouts: healthManager.recentWorkouts)
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(MADTheme.Colors.madRed)
                        .fontWeight(.semibold)
                }
            }
            .task {
                pickDefaultDayIfNeeded()
                await loadLinkedPosts()
            }
            .sheet(item: $selectedWorkout) { identifiable in
                let list = workouts(on: selectedDay ?? Date())
                WorkoutPagerView(
                    workouts: list,
                    startIndex: list.firstIndex { $0.uuid == identifiable.workout.uuid } ?? 0,
                    preloadedPosts: postsByWorkout
                )
            }
        }
        // Keep the shared HealthKit manager available to WorkoutRow / the pager's
        // detail views regardless of how this screen was presented.
        .environmentObject(healthManager)
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack {
                Button { changeMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                }
                Spacer()
                Text(monthTitle)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Button { changeMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(canGoNext ? .white : .white.opacity(0.2))
                        .frame(width: 36, height: 36)
                }
                .disabled(!canGoNext)
            }

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, sym in
                    Text(sym)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cell in
                    if let date = cell {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    private func dayCell(_ date: Date) -> some View {
        let status = dayStatus(date)
        let isToday = calendar.isDateInToday(date)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedDay = date }
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(status == .none ? .white.opacity(0.45) : .white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(status.fill))
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? Color.white : (isToday ? MADTheme.Colors.madRed : .clear),
                        lineWidth: isSelected ? 2 : 1.5
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected day

    @ViewBuilder
    private var selectedDaySection: some View {
        let day = selectedDay ?? Date()
        let dayWorkouts = workouts(on: day)
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "figure.run")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text(dayTitle(day))
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
                Spacer()
                if !dayWorkouts.isEmpty {
                    Text(milesText(for: day))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }

            if dayWorkouts.isEmpty {
                VStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.white.opacity(0.25))
                    Text("No workouts this day")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, MADTheme.Spacing.lg)
            } else {
                ForEach(dayWorkouts, id: \.uuid) { workout in
                    Button {
                        selectedWorkout = IdentifiableWorkout(workout: workout)
                    } label: {
                        WorkoutRow(
                            workout: workout,
                            showDate: false,
                            hasPhoto: hasRealPhoto(postsByWorkout[workout.uuid.uuidString])
                        )
                        .padding(MADTheme.Spacing.md)
                        .madLiquidGlass()
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Data

    /// The workouts on a given local day, mapped from the timezone-aware index
    /// (falls back to filtering the cache by corrected local time).
    private func workouts(on day: Date) -> [HKWorkout] {
        if let index = healthManager.workoutIndex {
            let ids = Set(index.workouts(for: day).map { $0.id })
            if !ids.isEmpty {
                return healthManager.cachedWorkouts
                    .filter { ids.contains($0.uuid.uuidString) }
                    .sorted { $0.endDate < $1.endDate }
            }
        }
        return healthManager.cachedWorkouts
            .filter { calendar.isDate(healthManager.getCorrectedLocalTime(for: $0), inSameDayAs: day) }
            .sorted { $0.endDate < $1.endDate }
    }

    private func miles(on day: Date) -> Double {
        if let index = healthManager.workoutIndex {
            return index.totalMiles(for: day)
        }
        return workouts(on: day).reduce(0) { $0 + ($1.totalDistance?.doubleValue(for: .mile()) ?? 0) }
    }

    private func milesText(for day: Date) -> String {
        String(format: "%.2f mi", miles(on: day))
    }

    private enum DayStatus: Equatable {
        case none, partial, complete
        var fill: Color {
            switch self {
            case .none: return Color.white.opacity(0.06)
            case .partial: return MADTheme.Colors.warning.opacity(0.55)
            case .complete: return MADTheme.Colors.success
            }
        }
    }

    private func dayStatus(_ date: Date) -> DayStatus {
        let m = miles(on: date)
        if m <= 0 { return .none }
        let goal = UserManager.shared.currentUser.goalMiles
        return ProgressCalculator.isGoalCompleted(current: m, goal: goal) ? .complete : .partial
    }

    private func hasRealPhoto(_ post: PostItem?) -> Bool {
        guard let post else { return false }
        if post.storyPhotoURL != nil { return true }
        return post.is_auto != true && !post.media_url.isEmpty
    }

    private func loadLinkedPosts() async {
        guard postsByWorkout.isEmpty,
              let uid = UserManager.shared.currentUser.backendUserId else { return }
        var map: [String: PostItem] = [:]
        var before: String? = nil
        // Three pages here (vs two on the dashboard): the calendar reaches
        // further back than the recent list, so cover a bit more history.
        for _ in 0..<3 {
            guard let page = try? await PostService.fetchUserPosts(
                userId: uid, before: before, includeStories: true
            ) else { break }
            for post in page.items {
                guard let wid = post.workout_id, map[wid] == nil else { continue }
                map[wid] = post
            }
            guard let next = page.next_before else { break }
            before = next
        }
        let resolved = map
        await MainActor.run { postsByWorkout = resolved }
    }

    // MARK: - Calendar math

    private func pickDefaultDayIfNeeded() {
        guard !didPickDefaultDay else { return }
        didPickDefaultDay = true
        if let recent = healthManager.recentWorkouts.first {
            let day = calendar.startOfDay(for: healthManager.getCorrectedLocalTime(for: recent))
            selectedDay = day
            month = startOfMonth(for: day)
        } else {
            selectedDay = calendar.startOfDay(for: Date())
            month = startOfMonth(for: Date())
        }
    }

    private func startOfMonth(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func changeMonth(_ delta: Int) {
        if delta > 0 && !canGoNext { return }
        if let d = calendar.date(byAdding: .month, value: delta, to: month) {
            withAnimation(.easeInOut(duration: 0.2)) { month = startOfMonth(for: d) }
        }
    }

    private var canGoNext: Bool {
        month < startOfMonth(for: Date())
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: month)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var monthCells: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let first = monthInterval.start
        let daysCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: first)
        let pad = ((firstWeekday - calendar.firstWeekday) % 7 + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: pad)
        for offset in 0..<daysCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: first))
        }
        return cells
    }

    private func dayTitle(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: day)
    }
}
