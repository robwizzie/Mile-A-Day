import SwiftUI

// Detail view for Fastest Pace
struct FastestPaceDetailView: View {
    @ObservedObject var healthManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWorkout: IdentifiableWorkout?
    
    var formattedPace: String {
        guard healthManager.fastestMilePace > 0 else { return "Not yet recorded" }
        
        let totalMinutes = healthManager.fastestMilePace
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)
        
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
    
    var speedMph: String {
        guard healthManager.fastestMilePace > 0 else { return "0.0 mph" }
        return String(format: "%.1f mph", 60 / healthManager.fastestMilePace)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Top banner
                    VStack(spacing: MADTheme.Spacing.md) {
                        Text("Personal Record")
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                        
                        Text("Fastest Mile Pace")
                            .font(MADTheme.Typography.title1)
                            .fontWeight(.bold)
                            .foregroundColor(MADTheme.Colors.primaryText)
                        
                        Text(formattedPace)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(MADTheme.Colors.success)
                            .padding(.top, MADTheme.Spacing.sm)
                    }
                    .padding(MADTheme.Spacing.xl)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .fill(MADTheme.Colors.success.opacity(0.1))
                    )
                    .madCard(hasShadow: false)
                    
                    // Stats grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: MADTheme.Spacing.lg) {
                        StatBox(
                            title: "Pace",
                            value: formattedPace,
                            icon: "hare.fill",
                            color: MADTheme.Colors.success
                        )
                        StatBox(
                            title: "Speed",
                            value: speedMph,
                            icon: "speedometer",
                            color: Color.blue
                        )
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    
                    // Performance categories
                    if healthManager.fastestMilePace > 0 {
                        performanceSection
                    }
                    
                    // Workouts that achieved the fastest mile
                    if !healthManager.fastestMileWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                            Text("Fastest Mile Workouts")
                                .font(MADTheme.Typography.title3)
                                .fontWeight(.bold)
                                .foregroundColor(MADTheme.Colors.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            ForEach(healthManager.fastestMileWorkouts, id: \.uuid) { workout in
                                Button {
                                    selectedWorkout = IdentifiableWorkout(workout: workout)
                                } label: {
                                    WorkoutRow(workout: workout)
                                        .padding(MADTheme.Spacing.lg)
                                        .madCard()
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, MADTheme.Spacing.lg)
                    }
                    
                    // Tips and achievements
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                        Text("Achievements")
                            .font(MADTheme.Typography.title3)
                            .fontWeight(.bold)
                            .foregroundColor(MADTheme.Colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(spacing: MADTheme.Spacing.lg) {
                            Image(systemName: "stopwatch.fill")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                                Text("Your fastest pace!")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(MADTheme.Colors.primaryText)
                                
                                Text("You've run a mile at \(formattedPace). Great job!")
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(MADTheme.Colors.secondaryText)
                            }
                        }
                        .padding(MADTheme.Spacing.lg)
                        .madCard()
                        
                        // Tips for improving pace
                        HStack(spacing: MADTheme.Spacing.lg) {
                            Image(systemName: "bolt.fill")
                                .font(.largeTitle)
                                .foregroundColor(.yellow)
                            
                            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                                Text("Improve your pace!")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(MADTheme.Colors.primaryText)
                                
                                Text("Try interval training and tempo runs to increase your speed over time.")
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(MADTheme.Colors.secondaryText)
                            }
                        }
                        .padding(MADTheme.Spacing.lg)
                        .madCard()
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)
                }
                .padding(MADTheme.Spacing.lg)
            }
            .background(MADTheme.Colors.secondaryBackground)
            .navigationTitle("Pace Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .madTertiaryButton()
                }
            }
            .sheet(item: $selectedWorkout) { identifiableWorkout in
                WorkoutDetailView(workout: identifiableWorkout.workout)
            }
        }
    }
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
            Text("Performance Category")
                .font(MADTheme.Typography.title3)
                .fontWeight(.bold)
                .foregroundColor(MADTheme.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: MADTheme.Spacing.md) {
                PerformanceCategoryRow(
                    category: "Elite",
                    paceRange: "< 5:00",
                    isActive: healthManager.fastestMilePace < 5.0,
                    color: .purple
                )
                
                PerformanceCategoryRow(
                    category: "Competitive",
                    paceRange: "5:00 - 6:30",
                    isActive: healthManager.fastestMilePace >= 5.0 && healthManager.fastestMilePace < 6.5,
                    color: MADTheme.Colors.madRed
                )
                
                PerformanceCategoryRow(
                    category: "Recreational",
                    paceRange: "6:30 - 8:00",
                    isActive: healthManager.fastestMilePace >= 6.5 && healthManager.fastestMilePace < 8.0,
                    color: Color.blue
                )
                
                PerformanceCategoryRow(
                    category: "Fitness",
                    paceRange: "8:00 - 10:00",
                    isActive: healthManager.fastestMilePace >= 8.0 && healthManager.fastestMilePace < 10.0,
                    color: MADTheme.Colors.success
                )
                
                PerformanceCategoryRow(
                    category: "Beginner",
                    paceRange: "10:00+",
                    isActive: healthManager.fastestMilePace >= 10.0,
                    color: MADTheme.Colors.warning
                )
            }
        }
        .padding(.horizontal, MADTheme.Spacing.lg)
    }
}

struct PerformanceCategoryRow: View {
    let category: String
    let paceRange: String
    let isActive: Bool
    let color: Color
    
    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(isActive ? color.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: 12, height: 12)
                
                if isActive {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
            }
            
            Text(category)
                .font(MADTheme.Typography.body)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundColor(isActive ? MADTheme.Colors.primaryText : MADTheme.Colors.secondaryText)
            
            Spacer()
            
            Text(paceRange)
                .font(MADTheme.Typography.callout)
                .foregroundColor(MADTheme.Colors.secondaryText)
        }
        .padding(.vertical, MADTheme.Spacing.xs)
        .opacity(isActive ? 1.0 : 0.6)
    }
}

#Preview {
    FastestPaceDetailView(healthManager: HealthKitManager())
}