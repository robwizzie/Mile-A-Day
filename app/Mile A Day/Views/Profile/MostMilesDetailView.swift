import SwiftUI
import HealthKit

// Detail view for Most Miles in One Day
struct MostMilesDetailView: View {
    let miles: Double
    @ObservedObject var healthManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWorkout: IdentifiableWorkout?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Top banner
                    VStack(spacing: MADTheme.Spacing.md) {
                        Text("Personal Record")
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                        
                        Text("Most Miles in One Day")
                            .font(MADTheme.Typography.title1)
                            .fontWeight(.bold)
                            .foregroundColor(MADTheme.Colors.primaryText)
                        
                        Text(miles.milesFormatted)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(Color.purple)
                            .padding(.top, MADTheme.Spacing.sm)
                    }
                    .padding(MADTheme.Spacing.xl)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .fill(Color.purple.opacity(0.1))
                    )
                    .madCard(hasShadow: false)
                    
                    // Stats grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: MADTheme.Spacing.lg) {
                        StatBox(
                            title: "Distance",
                            value: miles.milesFormatted,
                            icon: "map.fill",
                            color: Color.purple
                        )
                        StatBox(
                            title: "Steps",
                            value: String(format: "%.0f steps", miles * 2000),
                            icon: "figure.walk",
                            color: MADTheme.Colors.success
                        )
                        StatBox(
                            title: "Calories Burned",
                            value: String(format: "%.0f calories", miles * 100),
                            icon: "flame.fill",
                            color: MADTheme.Colors.warning
                        )
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    
                    // Workouts that contributed to the record
                    if !healthManager.mostMilesWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                            Text("Workouts")
                                .font(MADTheme.Typography.title3)
                                .fontWeight(.bold)
                                .foregroundColor(MADTheme.Colors.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            ForEach(healthManager.mostMilesWorkouts, id: \.uuid) { workout in
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
                        Text("Medals")
                            .font(MADTheme.Typography.title3)
                            .fontWeight(.bold)
                            .foregroundColor(MADTheme.Colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(spacing: MADTheme.Spacing.lg) {
                            Image(systemName: "trophy.fill")
                                .font(.largeTitle)
                                .foregroundColor(.yellow)
                            
                            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                                Text("Distance Record!")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(MADTheme.Colors.primaryText)
                                
                                Text("You've covered \(miles.milesFormatted) in a single day. Amazing achievement!")
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(MADTheme.Colors.secondaryText)
                            }
                        }
                        .padding(MADTheme.Spacing.lg)
                        .madCard()
                        
                        // Tips for improving distance
                        HStack(spacing: MADTheme.Spacing.lg) {
                            Image(systemName: "figure.run")
                                .font(.largeTitle)
                                .foregroundColor(MADTheme.Colors.success)
                            
                            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                                Text("Build Endurance!")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(MADTheme.Colors.primaryText)
                                
                                Text("Gradually increase your daily distance and incorporate long runs into your training.")
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
            .navigationTitle("Distance Record")
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
}

// Stat box component for detail views
struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(color)
            }
            
            VStack(spacing: MADTheme.Spacing.xs) {
                Text(value)
                    .font(MADTheme.Typography.headline)
                    .fontWeight(.bold)
                    .foregroundColor(MADTheme.Colors.primaryText)
                    .multilineTextAlignment(.center)
                
                Text(title)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.lg)
        .madCard()
    }
}

// Workout row component
struct WorkoutRow: View {
    let workout: HKWorkout
    @EnvironmentObject var healthManager: HealthKitManager
    
    // Timezone-corrected time for display
    private var correctedStartTime: Date {
        let correctedEndTime = healthManager.getCorrectedLocalTime(for: workout)
        return correctedEndTime.addingTimeInterval(-workout.duration)
    }
    
    private var workoutDistance: String {
        if let distance = workout.totalDistance {
            let miles = distance.doubleValue(for: .mile())
            return miles.milesFormatted
        }
        return "Unknown"
    }
    
    private var workoutDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: workout.duration) ?? "Unknown"
    }
    
    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(MADTheme.Colors.madRed.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: workoutIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(MADTheme.Colors.madRed)
            }
            
            VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                Text(workoutTypeString)
                    .font(MADTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(MADTheme.Colors.primaryText)
                
                HStack {
                    Text(workoutDistance)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                    
                    Text("•")
                        .foregroundColor(MADTheme.Colors.secondaryText)
                    
                    Text(workoutDuration)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                }
            }
            
            Spacer()
            
            Text(DateFormatter.shortTime.string(from: correctedStartTime))
                .font(MADTheme.Typography.caption)
                .foregroundColor(MADTheme.Colors.secondaryText)
        }
    }
    
    private var workoutTypeString: String {
        switch workout.workoutActivityType {
        case .running:
            return "Running"
        case .walking:
            return "Walking"
        case .cycling:
            return "Cycling"
        default:
            return "Workout"
        }
    }
    
    private var workoutIcon: String {
        switch workout.workoutActivityType {
        case .running:
            return "figure.run"
        case .walking:
            return "figure.walk"
        case .cycling:
            return "bicycle"
        default:
            return "figure.mixed.cardio"
        }
    }
}

// Date formatter extension
extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    MostMilesDetailView(miles: 5.2, healthManager: HealthKitManager())
}