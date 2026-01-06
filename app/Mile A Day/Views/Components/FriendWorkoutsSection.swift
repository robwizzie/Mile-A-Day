//
//  FriendWorkoutsSection.swift
//  Mile A Day
//
//  Component for displaying a friend's recent workouts
//

import SwiftUI

struct FriendWorkoutsSection: View {
    let workouts: [FriendWorkout]

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            // Section Header
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.title3)
                    .foregroundColor(MADTheme.Colors.madRed)
                Text("Recent Workouts")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(MADTheme.Colors.primaryText)
                Spacer()
                Text("\(workouts.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(MADTheme.Colors.secondaryBackground)
                    )
            }
            .padding(.top, MADTheme.Spacing.md)

            // Workouts List - removed prefix(10) to show all workouts
            VStack(spacing: MADTheme.Spacing.xs) {
                ForEach(workouts) { workout in
                    FriendWorkoutRow(workout: workout)
                }
            }
            .padding(.bottom, MADTheme.Spacing.md)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .background(MADTheme.Colors.primaryBackground)
        .cornerRadius(MADTheme.CornerRadius.large)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

struct FriendWorkoutRow: View {
    let workout: FriendWorkout

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            // Workout Icon in colored circle
            ZStack {
                Circle()
                    .fill(workoutColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: workoutIcon)
                    .font(.system(size: 20))
                    .foregroundColor(workoutColor)
            }

            // Workout Details
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(workout.formattedDate)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MADTheme.Colors.primaryText)
                    
                    // Type badge
                    Text(workout.workoutType.capitalized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(workoutColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(workoutColor.opacity(0.15))
                        )
                }

                HStack(spacing: 12) {
                    // Distance
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11))
                            .foregroundColor(MADTheme.Colors.secondaryText)
                        Text(workout.formattedDistance)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MADTheme.Colors.primaryText)
                    }
                    
                    // Duration
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11))
                            .foregroundColor(MADTheme.Colors.secondaryText)
                        Text(workout.formattedDuration)
                            .font(.system(size: 13))
                            .foregroundColor(MADTheme.Colors.secondaryText)
                    }
                }
            }

            Spacer()
        }
        .padding(MADTheme.Spacing.md)
        .background(MADTheme.Colors.secondaryBackground)
        .cornerRadius(MADTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .stroke(workoutColor.opacity(0.1), lineWidth: 1)
        )
    }

    private var workoutIcon: String {
        switch workout.workoutType.lowercased() {
        case "running":
            return "figure.run"
        case "walking":
            return "figure.walk"
        case "cycling":
            return "bicycle"
        case "hiking":
            return "figure.hiking"
        default:
            return "figure.run"
        }
    }
    
    private var workoutColor: Color {
        switch workout.workoutType.lowercased() {
        case "running":
            return MADTheme.Colors.madRed
        case "walking":
            return .blue
        case "cycling":
            return .green
        case "hiking":
            return .orange
        default:
            return MADTheme.Colors.madRed
        }
    }
}

