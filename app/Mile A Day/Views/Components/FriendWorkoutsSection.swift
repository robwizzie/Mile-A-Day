//
//  FriendWorkoutsSection.swift
//  Mile A Day
//
//  Component for displaying a friend's recent workouts
//

import SwiftUI

struct FriendWorkoutsSection: View {
    let workouts: [FriendWorkout]
    var onWorkoutTap: ((FriendWorkout) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            // Section Header
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.title3)
                    .foregroundColor(MADTheme.Colors.madRed)
                Text("Recent Workouts")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(MADTheme.Colors.primaryText)
                Spacer()
                Text("\(workouts.count)")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .padding(.top, MADTheme.Spacing.md)

            // Workouts List
            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(workouts) { workout in
                    if let onTap = onWorkoutTap {
                        Button {
                            onTap(workout)
                        } label: {
                            FriendWorkoutRow(workout: workout, showChevron: true)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    } else {
                        FriendWorkoutRow(workout: workout)
                    }
                }
            }
            .padding(.bottom, MADTheme.Spacing.md)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .madLiquidGlass()
    }
}

struct FriendWorkoutRow: View {
    let workout: FriendWorkout
    var showChevron: Bool = false

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            // Workout Icon in colored circle
            ZStack {
                Circle()
                    .fill(workoutColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: workoutIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(workoutColor)
            }

            // Workout Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(workout.formattedDate)
                        .font(MADTheme.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(MADTheme.Colors.primaryText)

                    Text(workout.workoutType.capitalized)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(workoutColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(workoutColor.opacity(0.15))
                        )
                }

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundColor(MADTheme.Colors.secondaryText)
                        Text(workout.formattedDistance)
                            .font(MADTheme.Typography.caption)
                            .fontWeight(.medium)
                            .foregroundColor(MADTheme.Colors.primaryText)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(MADTheme.Colors.secondaryText)
                        Text(workout.formattedDuration)
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                    }
                }
            }

            Spacer()

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MADTheme.Colors.secondaryText)
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(Color.white.opacity(0.05))
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
