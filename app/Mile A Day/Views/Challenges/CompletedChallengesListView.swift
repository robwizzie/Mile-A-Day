import SwiftUI

/// Full list of every daily challenge the user has completed, grouped by date descending.
/// Header shows a per-challenge-type breakdown so the user can see which challenges they complete most.
struct CompletedChallengesListView: View {
    @ObservedObject var healthManager: HealthKitManager
    @State private var completions: [ChallengeCompletion] = ChallengeService.shared.allCompletions()
    @State private var selectedCompletion: ChallengeCompletion?

    private var sorted: [ChallengeCompletion] {
        completions.sorted { $0.date > $1.date }
    }

    private var countsByKey: [(key: String, title: String, icon: String, count: Int)] {
        let groups = Dictionary(grouping: completions, by: { $0.challengeKey })
        return groups.compactMap { key, group -> (String, String, String, Int)? in
            guard let first = group.first else { return nil }
            return (key, first.title, first.icon, group.count)
        }
        .sorted { $0.3 > $1.3 }
    }

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            if completions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        summaryHeader
                        breakdownSection
                        listSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle("All Completions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ChallengeService.changedNotification)) { _ in
            refresh()
        }
        .sheet(item: $selectedCompletion) { completion in
            CompletionWorkoutSheet(completion: completion, healthManager: healthManager)
                .presentationDetents([.medium, .large])
        }
    }

    private func refresh() {
        completions = ChallengeService.shared.allCompletions()
    }

    // MARK: - Summary

    private var summaryHeader: some View {
        VStack(spacing: 6) {
            Text("\(completions.count)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(completions.count == 1 ? "Challenge Completed" : "Challenges Completed")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(1.2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [MADTheme.Colors.madRed.opacity(0.15), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    // MARK: - Breakdown

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BY CHALLENGE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.6))

            VStack(spacing: 8) {
                ForEach(countsByKey, id: \.key) { row in
                    HStack(spacing: 12) {
                        Image(systemName: row.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.yellow)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle().fill(Color.white.opacity(0.08))
                            )

                        Text(row.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)

                        Spacer()

                        Text("\(row.count)×")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.05))
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - List

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HISTORY")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.6))

            VStack(spacing: 10) {
                ForEach(sorted) { completion in
                    Button {
                        selectedCompletion = completion
                    } label: {
                        CompletionRow(completion: completion)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "trophy")
                .font(.system(size: 56))
                .foregroundColor(.white.opacity(0.3))
            Text("No challenges completed yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Finish today's challenge to see it here.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(40)
    }
}

private struct CompletionRow: View {
    let completion: ChallengeCompletion

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                Image(systemName: completion.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            // Title is the only text — empty description was reserving 2 blank lines and
            // visually shoving the title above the icon. Use a single label so HStack
            // .center alignment keeps it vertically aligned with the icon.
            Text(completion.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()

            Text(completion.date.formattedShortDate)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Workout Sheet
//
// Tapping a completion opens this sheet. We look up the day's workouts in the
// local `WorkoutIndex` (HealthKitManager.workoutIndex) and surface stats so the
// user can see the run/walk that earned the challenge.

private struct CompletionWorkoutSheet: View {
    let completion: ChallengeCompletion
    @ObservedObject var healthManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss

    private var workouts: [WorkoutRecord] {
        healthManager.workoutIndex?.workouts(for: completion.date) ?? []
    }

    private var totalDistance: Double {
        workouts.reduce(0) { $0 + $1.distance }
    }

    private var totalDuration: TimeInterval {
        workouts.reduce(0) { $0 + $1.duration }
    }

    private var averagePace: TimeInterval? {
        guard totalDistance > 0 else { return nil }
        return (totalDuration / 60.0) / totalDistance // min/mi
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    challengeHeader
                    if workouts.isEmpty {
                        emptyWorkoutState
                    } else {
                        daySummaryCard
                        workoutsListSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
        }
    }

    private var challengeHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green, Color(red: 0.18, green: 0.78, blue: 0.42)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                Image(systemName: completion.icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(completion.title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(completion.date.formattedShortDate)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private var daySummaryCard: some View {
        HStack(spacing: 12) {
            statTile(value: formatMiles(totalDistance), label: "Miles", icon: "figure.run")
            statTile(value: formatDuration(totalDuration), label: "Time", icon: "clock.fill")
            if let pace = averagePace {
                statTile(value: formatPace(pace), label: "Avg pace", icon: "speedometer")
            } else {
                statTile(value: "—", label: "Avg pace", icon: "speedometer")
            }
        }
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.green)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var workoutsListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WORKOUTS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text("\(workouts.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            VStack(spacing: 8) {
                ForEach(workouts.sorted(by: { $0.localEndTime > $1.localEndTime }), id: \.id) { record in
                    workoutRow(record)
                }
            }
        }
    }

    private func workoutRow(_ record: WorkoutRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconFor(record.workoutType))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.green)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.green.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(record.workoutType.capitalized)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(formatTimeOfDay(record.localEndTime))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatMiles(record.distance))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(formatDuration(record.duration))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.05))
        )
    }

    private var emptyWorkoutState: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.3))
            Text("No workout details for this day")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            Text("HealthKit history may not be cached this far back.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.05))
        )
    }

    // MARK: - Formatting helpers

    private func iconFor(_ type: String) -> String {
        switch type.lowercased() {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "figure.outdoor.cycle"
        case "hiking": return "figure.hiking"
        default: return "figure.mixed.cardio"
        }
    }

    private func formatMiles(_ miles: Double) -> String {
        String(format: "%.2f mi", miles)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func formatPace(_ minPerMi: Double) -> String {
        let m = Int(minPerMi)
        let s = Int(round((minPerMi - Double(m)) * 60))
        let ss = s < 10 ? "0\(s)" : "\(s)"
        return "\(m):\(ss)/mi"
    }

    private func formatTimeOfDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
