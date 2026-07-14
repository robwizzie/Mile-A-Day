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

/// A friend's workout in the EXACT row grammar of the dashboard's own
/// WorkoutRow (accent icon chip, verb + hero distance, duration • pace,
/// date/time trailing) — a workout reads the same no matter whose it is.
struct FriendWorkoutRow: View {
    let workout: FriendWorkout
    var showChevron: Bool = false

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(workoutColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: workoutIcon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(workoutColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verb)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(MADTheme.Colors.secondaryText)
                    Text(workout.distance.milesFormatted)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(MADTheme.Colors.primaryText)
                    if workout.isManualOrEdited {
                        ManualWorkoutBadgeFromString(source: workout.source)
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                    Text(paceText == nil
                         ? workout.formattedDuration
                         : "\(workout.formattedDuration) \u{2022} \(paceText!)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(MADTheme.Colors.secondaryText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(dateLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(MADTheme.Colors.primaryText)
                if let time = startTimeLabel {
                    Text(time)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(MADTheme.Colors.secondaryText)
                }
            }

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

    /// Feed-style verb, same as WorkoutRow's headline.
    private var verb: String {
        switch workout.workoutType.lowercased() {
        case "running": return "Ran"
        case "walking": return "Walked"
        case "hiking": return "Hiked"
        case "cycling": return "Cycled"
        default: return "Moved"
        }
    }

    /// "18:27 /mi" when distance + duration allow it — same as WorkoutRow.
    private var paceText: String? {
        guard workout.distance > 0, workout.totalDuration > 0 else { return nil }
        return "\(RunStatsStickerView.paceText(workout.totalDuration / workout.distance)) /mi"
    }

    /// Start time derived the same way WorkoutRow does it: end − duration.
    private var startDate: Date? {
        guard let end = workout.deviceEndDate, let d = RelativeTime.date(from: end) else { return nil }
        return d.addingTimeInterval(-workout.totalDuration)
    }

    private var dateLabel: String {
        if let d = startDate {
            if Calendar.current.isDateInToday(d) { return "Today" }
            if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
            return DateFormatter.workoutRowDate.string(from: d)
        }
        // No device timestamp — fall back to the server's local_date.
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: workout.date) else { return workout.formattedDate }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return DateFormatter.workoutRowDate.string(from: d)
    }

    private var startTimeLabel: String? {
        guard let d = startDate else { return nil }
        return DateFormatter.shortTime.string(from: d)
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
        MADTheme.workoutColor(workout.workoutType)
    }
}
