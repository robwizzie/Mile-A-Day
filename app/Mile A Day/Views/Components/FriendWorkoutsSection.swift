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
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(MADTheme.Colors.madRed)
                Text("Recent Workouts")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(MADTheme.Colors.primaryText)
                Spacer()
            }
            .padding(.horizontal, MADTheme.Spacing.md)

            // Workouts List
            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(workouts.prefix(10)) { workout in
                    FriendWorkoutRow(workout: workout)
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .madCard()
    }
}

struct FriendWorkoutRow: View {
    let workout: FriendWorkout

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            // Workout Icon
            Image(systemName: workoutIcon)
                .font(.title2)
                .foregroundColor(MADTheme.Colors.madRed)
                .frame(width: 40)

            // Workout Details
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.formattedDate)
                    .font(MADTheme.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(MADTheme.Colors.primaryText)

                Text(workout.workoutType.capitalized)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.secondaryText)
            }

            Spacer()

            // Workout Stats
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                        .font(.caption)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                    Text(workout.formattedDistance)
                        .font(MADTheme.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(MADTheme.Colors.primaryText)
                }

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                    Text(workout.formattedDuration)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                }
            }
        }
        .padding(MADTheme.Spacing.sm)
        .background(MADTheme.Colors.secondaryBackground)
        .cornerRadius(MADTheme.CornerRadius.medium)
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
}

