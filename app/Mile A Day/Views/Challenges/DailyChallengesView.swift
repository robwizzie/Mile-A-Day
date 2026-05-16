import SwiftUI

struct DailyChallengesView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager

    @State private var completions: [ChallengeCompletion] = ChallengeService.shared.allCompletions()
    @State private var selectedHistoryCompletion: ChallengeCompletion?
    @State private var todaysChallenge: DailyChallenge?
    @State private var tomorrowsChallenge: DailyChallenge?
    @State private var todayProgress: Double = 0
    @State private var isTodayComplete: Bool = false

    private static let milestones: [(threshold: Int, id: String, name: String)] = [
        (1,   "challenge_1",   "Challenge Accepted"),
        (5,   "challenge_5",   "Challenge Seeker"),
        (10,  "challenge_10",  "Challenge Pro"),
        (25,  "challenge_25",  "Challenge Master"),
        (50,  "challenge_50",  "Challenge Legend"),
        (100, "challenge_100", "Challenge Immortal"),
    ]

    private var totalCompletions: Int { completions.count }

    private var earnedMedalsCount: Int {
        Self.milestones.filter { ms in
            userManager.currentUser.badges.contains(where: { $0.id == ms.id && !$0.isLocked })
        }.count
    }

    private var viewAllLabel: String {
        switch totalCompletions {
        case 0: return "View completions"
        case 1: return "View your 1 completion"
        default: return "View all \(totalCompletions) completions"
        }
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    heroCard
                    if let tomorrow = tomorrowsChallenge {
                        tomorrowPreviewCard(tomorrow)
                    }
                    statsRow
                    medalsGallery
                    historySection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Daily Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let userId = userManager.currentUser.backendUserId {
                await ChallengeService.refresh(userId: userId)
            }
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: ChallengeService.changedNotification)) { _ in
            refresh()
        }
        .sheet(item: $selectedHistoryCompletion) { completion in
            HistoryCompletionSheet(completion: completion)
                .presentationDetents([.medium])
        }
    }

    private func refresh() {
        completions = ChallengeService.shared.allCompletions()
        if let remote = ChallengeService.shared as? RemoteChallengeService {
            todaysChallenge = remote.todayChallenge
            tomorrowsChallenge = remote.tomorrowChallenge
            todayProgress = remote.todayProgress
            isTodayComplete = remote.todayCompleted
        }
    }

    // MARK: - Tomorrow Preview

    private func tomorrowPreviewCard(_ challenge: DailyChallenge) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: challenge.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .opacity(0.85)
                Image(systemName: challenge.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("COMING TOMORROW")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.55))
                Text(challenge.title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(challenge.description)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    (challenge.gradient.first ?? .white).opacity(0.25),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let challenge = todaysChallenge {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: isTodayComplete ? [.green, .green.opacity(0.8)] : challenge.gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                        Image(systemName: isTodayComplete ? "checkmark" : challenge.icon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("TODAY'S CHALLENGE")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundColor(isTodayComplete ? .green : (challenge.gradient.first ?? .orange))
                        Text(challenge.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text(challenge.description)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(3)
                    }

                    Spacer()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: isTodayComplete ? [.green, .green] : challenge.gradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: todayProgress * geo.size.width, height: 8)
                            .animation(.easeOut(duration: 0.5), value: todayProgress)
                    }
                }
                .frame(height: 8)

                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.yellow)
                    Text(isTodayComplete ? "Challenge complete — progress saved" : "Reward: +1 toward your next medal")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
            } else {
                Text("No challenge today")
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(18)
        .background(heroBackground)
    }

    private var heroBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [
                                (todaysChallenge?.gradient.first ?? MADTheme.Colors.madRed).opacity(0.12),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile(icon: "checkmark.seal.fill", color: .yellow, value: "\(totalCompletions)", label: "Completed")
            statTile(icon: "trophy.fill", color: MADTheme.Colors.madRed, value: "\(earnedMedalsCount)/\(Self.milestones.count)", label: "Medals")
        }
    }

    private func statTile(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Medal Gallery

    private var medalsGallery: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MEDAL COLLECTION")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("\(earnedMedalsCount)/\(Self.milestones.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ForEach(Self.milestones, id: \.id) { ms in
                    NavigationLink {
                        BadgeDetailView(badge: badgeFor(ms), userManager: userManager)
                    } label: {
                        PremiumBadgeCard(badge: badgeFor(ms))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private func badgeFor(_ ms: (threshold: Int, id: String, name: String)) -> Badge {
        if let earned = userManager.currentUser.badges.first(where: { $0.id == ms.id }) {
            return earned
        }
        return Badge(
            id: ms.id,
            name: ms.name,
            description: "Complete \(ms.threshold) daily \(ms.threshold == 1 ? "challenge" : "challenges")!",
            dateAwarded: Date.distantFuture,
            isNew: false,
            isLocked: true
        )
    }

    // MARK: - History

    private var historySection: some View {
        let days = last14Days()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LAST 14 DAYS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("\(days.filter { $0.completion != nil }.count) completed")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7),
                spacing: 8
            ) {
                ForEach(days, id: \.date) { day in
                    HistoryDayCell(day: day) {
                        if let c = day.completion { selectedHistoryCompletion = c }
                    }
                }
            }

            NavigationLink {
                CompletedChallengesListView()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                    Text(viewAllLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(MADTheme.Colors.madRed)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(MADTheme.Colors.madRed.opacity(0.12))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 4)
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

    private func last14Days() -> [HistoryDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lookup: [Date: ChallengeCompletion] = Dictionary(
            uniqueKeysWithValues: completions.map { (calendar.startOfDay(for: $0.date), $0) }
        )
        return (0..<14).reversed().compactMap { offset -> HistoryDay? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return HistoryDay(date: date, isToday: offset == 0, completion: lookup[date])
        }
    }
}

// MARK: - Supporting Types

private struct HistoryDay {
    let date: Date
    let isToday: Bool
    let completion: ChallengeCompletion?
}

private struct HistoryDayCell: View {
    let day: HistoryDay
    let onTap: () -> Void

    private var dayNumber: String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: day.date)
    }

    private var weekday: String {
        let f = DateFormatter(); f.dateFormat = "EEEEE"; return f.string(from: day.date)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(weekday)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(day.completion != nil ? Color.green.opacity(0.85) : Color.white.opacity(0.08))
                        .frame(height: 40)
                    if let c = day.completion {
                        Image(systemName: c.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text(dayNumber)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    if day.isToday {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(MADTheme.Colors.madRed, lineWidth: 2)
                            .frame(height: 40)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(day.completion == nil)
    }
}

private struct HistoryCompletionSheet: View {
    let completion: ChallengeCompletion

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: completion.icon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.top, 32)
                Text(completion.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(completion.description)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text(completion.date.formattedShortDate)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
        }
    }
}
