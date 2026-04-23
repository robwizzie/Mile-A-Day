import SwiftUI

/// Full list of every daily challenge the user has completed, grouped by date descending.
/// Header shows a per-challenge-type breakdown so the user can see which challenges they complete most.
struct CompletedChallengesListView: View {
    @State private var completions: [ChallengeCompletion] = ChallengeService.shared.allCompletions()

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
                    CompletionRow(completion: completion)
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

            VStack(alignment: .leading, spacing: 3) {
                Text(completion.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(completion.description)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
            }

            Spacer()

            Text(completion.date.formattedShortDate)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
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
    }
}
