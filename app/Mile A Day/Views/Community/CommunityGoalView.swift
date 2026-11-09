import SwiftUI

/// The whole journey: how far everyone has come, what's ahead, and your part.
/// Only totals are ever shown here, never another person's name or location.
struct CommunityGoalView: View {
    private let service = CommunityGoalService.shared

    var body: some View {
        ScrollView {
            if let response = service.current, let goal = response.goal {
                VStack(alignment: .leading, spacing: 16) {
                    hero(goal)
                    if goal.needsMoreWalkers { inviteCard(goal) }
                    mineCard(goal, response: response)
                    rewardsCard(goal, response: response)
                    checkpointsCard(goal)
                }
                .padding(16)
                .lockedToScrollWidth()
            } else {
                Text("No community goal right now. The next one will show up here.")
                    .madFont(size: 15, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(32)
                    .lockedToScrollWidth()
            }
        }
        .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
        .navigationTitle(service.current?.goal?.title ?? "Community goal")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await service.refresh() }
        .task { await service.refresh() }
    }

    private func hero(_ goal: CommunityGoal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(goal.statusLine)
                .madFont(size: 13, weight: .bold, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white.opacity(0.65))
            Text(CommunityGoalCopy.whole(goal.total_miles))
                .madFont(size: 36, weight: .heavy, design: .rounded)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("of \(CommunityGoalCopy.whole(goal.target_miles)), walked by \(walkers(goal))")
                .madFont(size: 14, weight: .medium, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white.opacity(0.7))
            CommunityGoalJourney(goal: goal, height: 14)
                .padding(.top, 4)
            if let today = goal.walkingTodayLine {
                CommunityGoalWalkingToday(text: today)
            }
            if let line = goal.paceLine {
                Text(line)
                    .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.4)
                    .foregroundColor(goal.onPace ? .green : .orange)
            }
            Text(goal.description)
                .madFont(size: 14, weight: .regular, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            if let url = CommunityGoalCopy.shareURL {
                ShareLink(
                    item: url,
                    message: Text("We're walking \(goal.title) together on Mile A Day. Come help us finish!")
                ) {
                    Label("Share this goal", systemImage: "square.and.arrow.up")
                        .madFont(size: 14, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(MADTheme.Colors.madRed)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .communityCard()
    }

    private func walkers(_ goal: CommunityGoal) -> String {
        goal.walkers == 1 ? "1 walker" : "\(goal.walkers.formatted()) walkers"
    }

    private func mineCard(_ goal: CommunityGoal, response: CommunityGoalResponse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Your part")
            HStack(spacing: 24) {
                stat(response.my_miles.distanceFormatted1, caption: "added")
                stat("\(response.my_days)", caption: response.my_days == 1 ? "day walked" : "days walked")
            }
        }
        .communityCard()
    }

    private func stat(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .madFont(size: 22, weight: .heavy, design: .rounded)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .madFont(size: 12, weight: .medium, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    /// Close to the end and behind pace, the answer is more walkers.
    private func inviteCard(_ goal: CommunityGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label("We need more walkers")
            Text("We need about \(CommunityGoalCopy.whole(Double(goal.pace?.miles_per_day_needed ?? 0))) a day to finish. Every friend who joins gets us there faster.")
                .madFont(size: 14, weight: .medium, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                ReferralsView()
            } label: {
                Text("Invite a friend")
                    .madFont(size: 15, weight: .bold, design: .rounded)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(MADTheme.Colors.madRed))
            }
            .buttonStyle(.plain)
        }
        .communityCard()
    }

    private func rewardsCard(_ goal: CommunityGoal, response: CommunityGoalResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            label(goal.phase == .ended ? "Rewards" : "Limited rewards, this month only")
            CommunityRewardShowcase(goal: goal, days: response.my_days)
            Text("Reach \(CommunityGoalCopy.whole(goal.target_miles)) together and everyone who walked also gets a Streak Assist.")
                .madFont(size: 13, weight: .medium, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .communityCard()
    }

    private func checkpointsCard(_ goal: CommunityGoal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            label("The route")
            ForEach(goal.checkpoints) { checkpoint in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: checkpoint.reached ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(checkpoint.reached ? .green : .white.opacity(0.35))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(checkpoint.name)
                            .madFont(size: 15, weight: .bold, design: .rounded)
                            .foregroundColor(.white)
                        // A fact stays a surprise until the group gets there.
                        Text(checkpoint.reached ? checkpoint.fact : "\(checkpoint.percent)% of the way")
                            .madFont(size: 13, weight: .regular, design: .rounded, maxScale: 1.4)
                            .foregroundColor(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .communityCard()
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .madFont(size: 12, weight: .bold, design: .rounded, maxScale: 1.4)
            .foregroundColor(.white.opacity(0.65))
            .lineLimit(1)
    }
}

private extension View {
    func communityCard() -> some View {
        padding(DashboardCardSurface.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardCardSurface(style: .fun))
    }
}
