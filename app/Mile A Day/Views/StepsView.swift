import SwiftUI
import HealthKit

struct StepsView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @State private var selectedDate: Date?
    @State private var showingDateDetail = false
    @State private var currentMonth = Date()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Today's Steps Card
                TodaysStepsCard(steps: healthManager.todaysSteps)
                
                // Calendar View
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
                
                // Color Legend
                StepsLegendView()
            }
            .padding()
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.large)
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
                // Pre-fetch data for the selected date
                healthManager.getWorkoutsForDate(selectedDate) { _ in }
            }
        }
    }
}

// MARK: - Today's Steps Card
struct TodaysStepsCard: View {
    let steps: Int
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "figure.walk")
                    .font(.title2)
                    .foregroundColor(.primary)
                Text("Today's Steps")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            HStack(alignment: .bottom, spacing: 8) {
                Text("\(steps)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("steps")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
            

            
            // Progress bar (same style as calendar days)
            let goal: Double = 10000
            let progress = min(Double(steps) / goal, 1.0)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Goal: 10,000 steps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)
                        
                        // Progress bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(getStepColor(steps: steps))
                            .frame(width: progress * geometry.size.width, height: 4)
                            .animation(.easeInOut, value: progress)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
    
    private func getStepColor(steps: Int) -> Color {
        if steps >= 10000 {
            return .green
        } else if steps >= 7500 {
            return .orange
        } else if steps >= 5000 {
            return .yellow
        } else if steps > 0 {
            return .gray
        } else {
            return .clear
        }
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Month navigation header
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text(monthYearString)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: daysInWeek), spacing: 8) {
                // Day headers
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(height: 24)
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
                            .frame(height: 32)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }
    
    private func previousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newMonth
        }
    }
    
    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newMonth
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
    
    private let calendar = Calendar.current
    private let stepGoal: Double = 10000
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : (isCurrentMonth ? .primary : .secondary))
                
                // Step progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)
                        
                        // Progress bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(getStepColor())
                            .frame(width: min(CGFloat(steps) / stepGoal * geometry.size.width, geometry.size.width), height: 4)
                    }
                }
                .frame(height: 4)
                
                // Mile goal indicator
                if mileGoalReached {
                    Image(systemName: "figure.run")
                        .font(.system(size: 8))
                        .foregroundColor(.green)
                }
            }
            .frame(width: 32, height: 40)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color("appPrimary") : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    

    
    private func getStepColor() -> Color {
        if steps >= 10000 {
            return .green
        } else if steps >= 7500 {
            return .orange
        } else if steps >= 5000 {
            return .yellow
        } else if steps > 0 {
            return .gray
        } else {
            return .clear
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
    
    init(date: Date, healthManager: HealthKitManager, userManager: UserManager) {
        self.date = date
        self.healthManager = healthManager
        self.userManager = userManager
        self._currentDate = State(initialValue: date)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Date header with navigation
                    VStack(spacing: 12) {
                        HStack {
                            Button {
                                navigateToPreviousDay()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                            
                            Text(calendar.isDateInToday(currentDate) ? "Today" : formatDate(currentDate))
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button {
                                navigateToNextDay()
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        // Steps with progress bar
                        VStack(spacing: 8) {
                            HStack {
                                Text("\(totalSteps)")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                
                                Text("steps")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("\(Int(getStepProgress(steps: totalSteps) * 100))%")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                            }
                            
                            // Progress bar (same style as calendar)
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 4)
                                    
                                    // Progress bar
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(getStepColor(steps: totalSteps))
                                        .frame(width: getStepProgress(steps: totalSteps) * geometry.size.width, height: 4)
                                        .animation(.easeInOut, value: totalSteps)
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                    .padding()
                    
                    // Workouts for this day
                    if workouts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            
                            Text("No workouts recorded")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Complete your workout with Apple Fitness to see it here")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Workouts")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .padding(.horizontal)
                            
                            ForEach(workouts, id: \.uuid) { workout in
                                Button {
                                    selectedWorkout = IdentifiableWorkout(workout: workout)
                                } label: {
                                    WorkoutRow(workout: workout)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
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
        // Get steps for this date
        let startOfDay = calendar.startOfDay(for: currentDate)
        totalSteps = healthManager.dailyStepsData[startOfDay] ?? 0
        
        // If steps data is not available, try to fetch it
        if totalSteps == 0 {
            // This will trigger a refresh of the monthly data
            healthManager.fetchMonthlyStepsData(for: currentDate) {
                DispatchQueue.main.async {
                    self.totalSteps = self.healthManager.dailyStepsData[startOfDay] ?? 0
                }
            }
        }
        
        // Get workouts for this date
        healthManager.getWorkoutsForDate(currentDate) { workoutList in
            DispatchQueue.main.async {
                self.workouts = workoutList
            }
        }
    }
    
    private func navigateToPreviousDay() {
        if let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) {
            currentDate = previousDay
        }
    }
    
    private func navigateToNextDay() {
        if let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) {
            currentDate = nextDay
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func getStepProgress(steps: Int) -> Double {
        let goal: Double = 10000
        return min(Double(steps) / goal, 1.0)
    }
    
    private func getStepColor(steps: Int) -> Color {
        if steps >= 10000 {
            return .green
        } else if steps >= 7500 {
            return .orange
        } else if steps >= 5000 {
            return .yellow
        } else if steps > 0 {
            return .gray
        } else {
            return .clear
        }
    }
}

// MARK: - Steps Legend View
struct StepsLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Step Goal Legend
            VStack(alignment: .leading, spacing: 8) {
                Text("Step Goal Legend")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                VStack(spacing: 6) {
                    LegendItem(color: .green, text: "10,000+ steps (Goal achieved)")
                    LegendItem(color: .orange, text: "7,500-9,999 steps (Close to goal)")
                    LegendItem(color: .yellow, text: "5,000-7,499 steps (Moderate activity)")
                    LegendItem(color: .gray, text: "1-4,999 steps (Low activity)")
                    LegendItem(color: .clear, text: "0 steps (No data)")
                }
            }
            
            Divider()
            
            // Mile Goal Legend
            VStack(alignment: .leading, spacing: 8) {
                Text("Mile Goal Legend")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                HStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                        .frame(width: 12, height: 12)
                    
                    Text("Mile goal reached")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

struct LegendItem: View {
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
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