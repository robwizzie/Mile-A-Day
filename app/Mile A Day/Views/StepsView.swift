import SwiftUI
import HealthKit

// MARK: - Shared Helpers

private func getStepColor(steps: Int) -> Color {
    if steps >= 10000 {
        return MADTheme.Colors.success
    } else if steps >= 7500 {
        return MADTheme.Colors.warning
    } else if steps >= 5000 {
        return .yellow
    } else if steps > 0 {
        return .gray
    } else {
        return .clear
    }
}

private func stepProgress(_ steps: Int, goal: Double = 10000) -> Double {
    min(Double(steps) / goal, 1.0)
}

// MARK: - Steps View

struct StepsView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @State private var selectedDate: Date?
    @State private var showingDateDetail = false
    @State private var currentMonth = Date()

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea(.all)

            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    TodaysStepsCard(steps: healthManager.todaysSteps)

                    StepsCalendarView(
                        dailyStepsData: healthManager.dailyStepsData,
                        dailyMileGoals: healthManager.dailyMileGoals,
                        selectedDate: $selectedDate,
                        currentMonth: $currentMonth,
                        onDateSelected: { date in
                            selectedDate = date
                            showingDateDetail = true
                        }
                    )

                    StepsLegendView()
                }
                .padding(MADTheme.Spacing.md)
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingDateDetail) {
            if let date = selectedDate {
                DateDetailView(
                    date: date,
                    healthManager: healthManager,
                    userManager: userManager
                )
            }
        }
        .onAppear {
            healthManager.fetchTodaysSteps()
            healthManager.fetchMonthlyStepsData(for: currentMonth)
        }
        .onChange(of: currentMonth) { oldValue, newValue in
            healthManager.fetchMonthlyStepsData(for: newValue)
        }
        .onChange(of: showingDateDetail) { _, isShowing in
            if isShowing, let selectedDate = selectedDate {
                healthManager.getWorkoutsForDate(selectedDate) { _ in }
            }
        }
    }
}

// MARK: - Today's Steps Card

struct TodaysStepsCard: View {
    let steps: Int

    private var progress: Double { stepProgress(steps) }
    private var color: Color { getStepColor(steps: steps) }

    var body: some View {
        HStack(spacing: MADTheme.Spacing.lg) {
            // Circular progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 5)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(MADTheme.Animation.standard, value: progress)

                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(MADTheme.Colors.redGradient)
            }
            .frame(width: 72, height: 72)

            // Text content
            VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                Text("Today's Steps")
                    .font(MADTheme.Typography.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text("\(steps)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                    .animation(MADTheme.Animation.standard, value: steps)

                HStack(spacing: MADTheme.Spacing.xs) {
                    Text("\(Int(progress * 100))% of 10k goal")
                        .font(MADTheme.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(color)
                }
            }

            Spacer()
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }
}

// MARK: - Steps Calendar View

struct StepsCalendarView: View {
    let dailyStepsData: [Date: Int]
    let dailyMileGoals: [Date: Bool]
    @Binding var selectedDate: Date?
    @Binding var currentMonth: Date
    let onDateSelected: (Date) -> Void

    private let calendar = Calendar.current
    private let daysInWeek = 7
    private let weeksToShow = 6

    private var isViewingCurrentMonth: Bool {
        calendar.isDate(currentMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            // Month navigation header
            HStack {
                Button(action: { goToPreviousMonth() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(MADTheme.Colors.madRed.opacity(0.15))
                        )
                }

                Spacer()

                VStack(spacing: MADTheme.Spacing.xs) {
                    Text(monthYearString)
                        .font(MADTheme.Typography.title3)
                        .foregroundColor(.primary)

                    // "Today" pill button when not on current month
                    if !isViewingCurrentMonth {
                        Button {
                            withAnimation(MADTheme.Animation.standard) {
                                currentMonth = Date()
                            }
                        } label: {
                            Text("Today")
                                .font(MADTheme.Typography.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(MADTheme.Colors.madRed)
                                .padding(.horizontal, MADTheme.Spacing.sm)
                                .padding(.vertical, MADTheme.Spacing.xs)
                                .background(
                                    Capsule()
                                        .fill(MADTheme.Colors.madRed.opacity(0.15))
                                )
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }

                Spacer()

                Button(action: { goToNextMonth() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(MADTheme.Colors.madRed.opacity(0.15))
                        )
                }
            }
            .padding(.horizontal, MADTheme.Spacing.xs)

            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: daysInWeek), spacing: MADTheme.Spacing.sm) {
                // Day headers
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(MADTheme.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(height: 20)
                }

                // Calendar days
                ForEach(0..<(weeksToShow * daysInWeek), id: \.self) { index in
                    let date = getDateForIndex(index)
                    if let date = date {
                        CalendarDayView(
                            date: date,
                            steps: dailyStepsData[date] ?? 0,
                            mileGoalReached: dailyMileGoals[date] ?? false,
                            isSelected: selectedDate == date,
                            isCurrentMonth: calendar.isDate(date, equalTo: currentMonth, toGranularity: .month),
                            onTap: {
                                onDateSelected(date)
                            }
                        )
                    } else {
                        Color.clear
                            .frame(height: 56)
                    }
                }
            }
            .id(currentMonth)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }

    private func goToPreviousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            withAnimation(MADTheme.Animation.standard) {
                currentMonth = newMonth
            }
        }
    }

    private func goToNextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            withAnimation(MADTheme.Animation.standard) {
                currentMonth = newMonth
            }
        }
    }

    private func getDateForIndex(_ index: Int) -> Date? {
        let startOfMonth = calendar.dateInterval(of: .month, for: currentMonth)?.start ?? currentMonth
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let offsetDays = firstWeekday - calendar.firstWeekday

        let dayOfMonth = index - offsetDays + 1
        return calendar.date(byAdding: .day, value: dayOfMonth - 1, to: startOfMonth)
    }
}

// MARK: - Calendar Day View

struct CalendarDayView: View {
    let date: Date
    let steps: Int
    let mileGoalReached: Bool
    let isSelected: Bool
    let isCurrentMonth: Bool
    let onTap: () -> Void

    @State private var isPulsing = false

    private let calendar = Calendar.current
    private var isToday: Bool { calendar.isDateInToday(date) }
    private var progress: Double { stepProgress(steps) }
    private var color: Color { getStepColor(steps: steps) }
    private var hasActivity: Bool { steps > 0 }
    private var reachedStepGoal: Bool { steps >= 10000 }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            VStack(spacing: 2) {
                // Day number
                Text("\(calendar.component(.day, from: date))")
                    .font(MADTheme.Typography.caption)
                    .fontWeight(isToday ? .bold : .medium)
                    .foregroundColor(dayNumberColor)

                // Circular indicator
                ZStack {
                    // Base track
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                        .frame(width: 34, height: 34)

                    if mileGoalReached {
                        // Mile goal reached — show step progress arc behind green fill
                        // Subtle green fill
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [MADTheme.Colors.success.opacity(0.25), MADTheme.Colors.success.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 34, height: 34)

                        // Step progress arc (still visible on completed days)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                LinearGradient(
                                    colors: [MADTheme.Colors.success, MADTheme.Colors.success.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                            )
                            .frame(width: 34, height: 34)
                            .rotationEffect(.degrees(-90))

                        // Runner icon
                        Image(systemName: "figure.run")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MADTheme.Colors.success)
                    } else if hasActivity {
                        // Has steps but no mile goal — show subtle fill + progress arc
                        Circle()
                            .fill(color.opacity(0.15))
                            .frame(width: 34, height: 34)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                LinearGradient(
                                    colors: [color, color.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                            )
                            .frame(width: 34, height: 34)
                            .rotationEffect(.degrees(-90))
                    }

                    // 10k step goal badge
                    if reachedStepGoal {
                        Image(systemName: "shoeprints.fill")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .cyan],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .offset(x: 13, y: -13)
                    }

                    // Today highlight ring
                    if isToday {
                        Circle()
                            .stroke(MADTheme.Colors.madRed, lineWidth: 2)
                            .frame(width: 39, height: 39)
                            .scaleEffect(isPulsing ? 1.08 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                value: isPulsing
                            )
                    }

                    // Selected state — use a white ring so it stands out on any color
                    if isSelected {
                        Circle()
                            .stroke(Color.white, lineWidth: 2.5)
                            .frame(width: 39, height: 39)

                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 39, height: 39)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .opacity(isCurrentMonth ? 1.0 : 0.3)
        }
        .buttonStyle(ScaleButtonStyle())
        .onAppear {
            if isToday {
                isPulsing = true
            }
        }
    }

    private var dayNumberColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return MADTheme.Colors.madRed
        } else if isCurrentMonth {
            return .primary
        } else {
            return .secondary
        }
    }
}

// MARK: - Date Detail View

struct DateDetailView: View {
    let date: Date
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss
    @State private var workouts: [HKWorkout] = []
    @State private var totalSteps: Int = 0
    @State private var selectedWorkout: IdentifiableWorkout?
    @State private var currentDate: Date

    private let calendar = Calendar.current

    private var progress: Double { stepProgress(totalSteps) }
    private var color: Color { getStepColor(steps: totalSteps) }

    init(date: Date, healthManager: HealthKitManager, userManager: UserManager) {
        self.date = date
        self.healthManager = healthManager
        self.userManager = userManager
        self._currentDate = State(initialValue: date)
    }

    var body: some View {
        NavigationView {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        // Date header card
                        VStack(spacing: MADTheme.Spacing.md) {
                            // Date navigation
                            HStack {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    navigateToPreviousDay()
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 36, height: 36)
                                        .background(
                                            Circle()
                                                .fill(MADTheme.Colors.madRed.opacity(0.2))
                                        )
                                }

                                Spacer()

                                Text(calendar.isDateInToday(currentDate) ? "Today" : formatDate(currentDate))
                                    .font(MADTheme.Typography.title2)
                                    .foregroundColor(.primary)

                                Spacer()

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    navigateToNextDay()
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 36, height: 36)
                                        .background(
                                            Circle()
                                                .fill(MADTheme.Colors.madRed.opacity(0.2))
                                        )
                                }
                            }

                            // Steps ring + count
                            HStack(spacing: MADTheme.Spacing.lg) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.1), lineWidth: 5)

                                    Circle()
                                        .trim(from: 0, to: progress)
                                        .stroke(
                                            LinearGradient(
                                                colors: [color, color.opacity(0.7)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                                        )
                                        .rotationEffect(.degrees(-90))
                                        .animation(MADTheme.Animation.standard, value: progress)

                                    Image(systemName: "shoeprints.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(MADTheme.Colors.redGradient)
                                }
                                .frame(width: 64, height: 64)

                                VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                                    Text("\(totalSteps)")
                                        .font(.system(size: 32, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                        .contentTransition(.numericText())
                                        .animation(MADTheme.Animation.standard, value: totalSteps)

                                    Text("steps")
                                        .font(MADTheme.Typography.headline)
                                        .foregroundColor(.secondary)

                                    Text("\(Int(progress * 100))% of goal")
                                        .font(MADTheme.Typography.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(color)
                                }

                                Spacer()
                            }
                        }
                        .padding(MADTheme.Spacing.md)
                        .madLiquidGlass()

                        // Workouts section
                        if workouts.isEmpty {
                            VStack(spacing: MADTheme.Spacing.md) {
                                Image(systemName: "figure.walk")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)

                                Text("No workouts recorded")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(.secondary)

                                Text("Complete your workout with Apple Fitness to see it here")
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(MADTheme.Spacing.xl)
                            .frame(maxWidth: .infinity)
                            .madLiquidGlass()
                        } else {
                            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                                Text("Workouts")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, MADTheme.Spacing.xs)

                                ForEach(workouts, id: \.uuid) { workout in
                                    Button {
                                        selectedWorkout = IdentifiableWorkout(workout: workout)
                                    } label: {
                                        WorkoutRow(workout: workout)
                                            .padding(MADTheme.Spacing.md)
                                            .madLiquidGlass()
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                }
                            }
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(MADTheme.Colors.madRed)
                    .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: $selectedWorkout) { identifiableWorkout in
            WorkoutDetailView(workout: identifiableWorkout.workout)
        }
        .onAppear {
            loadData()
        }
        .onChange(of: currentDate) { _, _ in
            loadData()
        }
    }

    private func loadData() {
        let startOfDay = calendar.startOfDay(for: currentDate)
        totalSteps = healthManager.dailyStepsData[startOfDay] ?? 0

        if totalSteps == 0 {
            healthManager.fetchMonthlyStepsData(for: currentDate) {
                DispatchQueue.main.async {
                    self.totalSteps = self.healthManager.dailyStepsData[startOfDay] ?? 0
                }
            }
        }

        healthManager.getWorkoutsForDate(currentDate) { workoutList in
            DispatchQueue.main.async {
                self.workouts = workoutList
            }
        }
    }

    private func navigateToPreviousDay() {
        if let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) {
            withAnimation(MADTheme.Animation.standard) {
                currentDate = previousDay
            }
        }
    }

    private func navigateToNextDay() {
        if let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) {
            withAnimation(MADTheme.Animation.standard) {
                currentDate = nextDay
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Steps Legend View

struct StepsLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Legend")
                .font(MADTheme.Typography.headline)
                .foregroundColor(.primary)

            // Step colors
            VStack(spacing: MADTheme.Spacing.sm) {
                LegendItem(color: MADTheme.Colors.success, text: "10,000+ steps")
                LegendItem(color: MADTheme.Colors.warning, text: "7,500 – 9,999 steps")
                LegendItem(color: .yellow, text: "5,000 – 7,499 steps")
                LegendItem(color: .gray, text: "Under 5,000 steps")
            }

            Divider()
                .overlay(Color.white.opacity(0.1))

            // Mile goal
            HStack(spacing: MADTheme.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [MADTheme.Colors.success, MADTheme.Colors.success.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 16, height: 16)

                    Image(systemName: "figure.run")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                }

                Text("Mile goal reached")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }
}

struct LegendItem: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 16, height: 16)

                Circle()
                    .fill(color.opacity(0.8))
                    .frame(width: 12, height: 12)
            }

            Text(text)
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}

#Preview {
    NavigationView {
        StepsView(
            healthManager: HealthKitManager(),
            userManager: UserManager()
        )
    }
}
