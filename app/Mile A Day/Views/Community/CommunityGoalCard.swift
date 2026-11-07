import SwiftUI

/// The community goal, for the Dashboard and the top of Compete. Draws nothing
/// between goals. The load starts in `init` because an empty body gets no
/// lifecycle, and `refreshIfStale` keeps that cheap.
struct CommunityGoalCard: View {
    private let service = CommunityGoalService.shared
    @State private var showingGoal = false

    init() {
        Task { await CommunityGoalService.shared.refreshIfStale() }
    }

    var body: some View {
        if let response = service.current, let goal = response.goal {
            Button {
                MADHaptics.tap()
                showingGoal = true
            } label: {
                content(goal, response: response)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the community goal")
            .sheet(isPresented: $showingGoal) {
                NavigationStack {
                    CommunityGoalView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingGoal = false }
                                    .fontWeight(.semibold)
                            }
                        }
                }
                .madTypeCap(.accessibility1)
                .preferredColorScheme(.dark)
            }
        }
    }

    private func content(_ goal: CommunityGoal, response: CommunityGoalResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Community goal")
                    .madFont(size: 12, weight: .bold, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(goal.statusLine)
                    .madFont(size: 12, weight: .semibold, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(goal.title)
                .madFont(size: 20, weight: .heavy, design: .rounded)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            CommunityGoalJourney(goal: goal, height: 10)

            Text(progressLine(goal))
                .madFont(size: 13, weight: .semibold, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if goal.needsMoreWalkers {
                Text("We're behind. Invite a friend to help us finish.")
                    .madFont(size: 13, weight: .bold, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.orange)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            if goal.phase != .upcoming {
                Text(CommunityGoalCopy.mine(goal, response: response))
                    .madFont(size: 13, weight: .medium, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(DashboardCardSurface.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardCardSurface(style: .fun))
        .contentShape(Rectangle())
    }

    private func progressLine(_ goal: CommunityGoal) -> String {
        if goal.phase == .upcoming { return "\(CommunityGoalCopy.whole(goal.target_miles)) to go, together" }
        if let next = goal.nextCheckpoint { return "\(goal.percent)% · Next: \(next.name)" }
        return "\(goal.percent)% of the way"
    }
}

enum CommunityGoalCopy {
    /// "2,800 mi". Community totals are big enough that decimals are noise.
    static func whole(_ miles: Double) -> String {
        "\(Int(miles.inDisplayUnit).formatted()) \(DistanceUnits.current.abbreviation)"
    }

    /// Your own part, in days toward the reward.
    static func mine(_ goal: CommunityGoal, response: CommunityGoalResponse) -> String {
        let miles = response.my_miles.distanceFormatted1
        guard goal.phase != .ended, let next = goal.nextReward(days: response.my_days) else {
            return "You added \(miles) · \(response.my_days) days"
        }
        return "You added \(miles) · \(response.my_days) of \(next.days) days"
    }
}

/// The journey line: progress along the route, with a dot per checkpoint.
struct CommunityGoalJourney: View {
    let goal: CommunityGoal
    var height: CGFloat = 12

    private var accent: Color { goal.reachedTarget ? .green : MADTheme.Colors.madRed }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(accent)
                    .frame(width: max(height, width * CGFloat(goal.percent) / 100))
                    .opacity(goal.percent > 0 ? 1 : 0)
                ForEach(goal.checkpoints.filter { $0.percent < 100 }) { checkpoint in
                    Circle()
                        .fill(checkpoint.reached ? Color.white : Color.white.opacity(0.35))
                        .frame(width: height * 0.45, height: height * 0.45)
                        .position(x: width * CGFloat(checkpoint.percent) / 100, y: height / 2)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
