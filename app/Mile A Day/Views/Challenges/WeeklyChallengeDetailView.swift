import SwiftUI

/// The weekly challenge in full: your progress, how your target was set, where
/// your friends are, and the weeks you've already banked.
struct WeeklyChallengeDetailView: View {
    let response: WeeklyChallengeResponse
    @ObservedObject var service: WeeklyChallengeService

    @Environment(\.dismiss) private var dismiss
    @State private var showHistory = false

    private var gradientColors: [Color] {
        [
            Color(hex: response.challenge.gradient_start),
            Color(hex: response.challenge.gradient_end)
        ]
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    ring
                    targetExplainer
                    if response.streak.current_weeks > 0 || response.streak.best_weeks > 0 {
                        streakRow
                    }
                    leaderboard
                    if let next = response.next_challenge {
                        nextWeekCard(next)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.vertical, MADTheme.Spacing.md)
            }
        }
        .navigationTitle(response.challenge.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("History") { showHistory = true }
                    .foregroundColor(MADTheme.Colors.madRed)
            }
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                WeeklyChallengeHistoryView(service: service)
            }
        }
        .task { await service.loadHistory() }
    }

    // MARK: - Ring

    private var ring: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 14)

                Circle()
                    .trim(from: 0, to: max(0.001, response.progress.percent))
                    .stroke(
                        LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text(WeeklyChallengeFormat.value(
                        response.progress.value,
                        unit: response.challenge.unit
                    ))
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                    Text("of \(WeeklyChallengeFormat.valueWithUnit(response.target, unit: response.challenge.unit))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .frame(width: 190, height: 190)
            .padding(.top, 8)

            Text(response.progress.completed
                 ? "Done for the week."
                 : WeeklyChallengeFormat.daysLeft(response.days_left))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(response.progress.completed ? .green : .white.opacity(0.6))

            Text(response.challenge.description)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Why this number

    /// A personal target reads as arbitrary unless you can see where it came
    /// from, so this always says.
    private var targetExplainer: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(gradientColors[0])

            Text(explainerText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var explainerText: String {
        if let baseline = response.baseline, baseline > 0 {
            let avg = WeeklyChallengeFormat.valueWithUnit(baseline, unit: response.challenge.unit)
            return "Everyone gets this challenge — your target is sized to you. You've averaged \(avg) a week recently."
        }
        return "Everyone gets this challenge. Targets are sized to each person's recent weeks; yours is the starting one until you've built up some history."
    }

    private var streakRow: some View {
        HStack(spacing: 0) {
            streakCell(
                value: response.streak.current_weeks,
                label: response.streak.current_weeks == 1 ? "week streak" : "week streak",
                tint: .orange
            )
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1, height: 30)
            streakCell(value: response.streak.best_weeks, label: "best run", tint: .yellow)
        }
        .padding(.vertical, MADTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func streakCell(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Leaderboard

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            CompeteSectionHeader(
                title: "Friends this week",
                systemImage: "person.2.fill",
                accent: MADTheme.Colors.madRed
            )

            if response.friends.count <= 1 {
                Text("Add friends to see how everyone's doing on this week's challenge.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(response.friends) { entry in
                        WeeklyLeaderboardRow(entry: entry, unit: response.challenge.unit)
                    }
                }

                // Everyone's target differs, so the ranking has to be explained
                // or a lower raw number sitting above a higher one looks broken.
                Text("Ranked by progress toward each person's own target.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }

    private func nextWeekCard(_ next: WeeklyChallengeResponse.NextChallenge) -> some View {
        HStack(spacing: 12) {
            Image(systemName: next.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.06)))

            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT WEEK")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.4))
                Text(next.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }

            Spacer(minLength: 0)
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

/// One friend's standing. Shows their percent AND their raw value against
/// their own target — a bare number would be unreadable when everyone is
/// chasing a different one.
struct WeeklyLeaderboardRow: View {
    let entry: WeeklyChallengeResponse.LeaderboardEntry
    let unit: String

    private var rankColor: Color {
        switch entry.rank {
        case 1: return Color(hex: "FFD133")
        case 2: return Color(hex: "C7C7C7")
        case 3: return Color(hex: "D18C4D")
        default: return .white.opacity(0.4)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(rankColor)
                .frame(width: 20)

            AvatarView(
                name: entry.displayName,
                imageURL: entry.profile_image_url,
                size: 34
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.displayName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if entry.completed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                    }
                }

                Text("\(WeeklyChallengeFormat.value(entry.value, unit: unit)) / \(WeeklyChallengeFormat.value(entry.target, unit: unit)) \(unit)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text("\(Int((entry.percent * 100).rounded()))%")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(entry.completed ? .green : .white.opacity(0.75))
                .fixedSize()
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(entry.is_me ? MADTheme.Colors.madRed.opacity(0.12) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .strokeBorder(
                            entry.is_me ? MADTheme.Colors.madRed.opacity(0.35) : Color.white.opacity(0.07),
                            lineWidth: 1
                        )
                )
        )
    }
}
