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
            VStack(alignment: .leading, spacing: 8) {
                opensGoal { progress(goal) }

                if goal.paceLine != nil || goal.inviteLine != nil {
                    CommunityGoalInviteRow(goal: goal)
                }

                opensGoal { CommunityGoalRewardStrip(goal: goal, days: response.my_days) }
            }
            .padding(DashboardCardSurface.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardCardSurface(style: .fun))
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

    private func opensGoal<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        Button {
            MADHaptics.tap()
            showingGoal = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the community goal")
    }

    /// Where we are, where we're going, and whether we'll make it.
    private func progress(_ goal: CommunityGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(goal.title)
                    .madFont(size: 18, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(goal.statusLine)
                    .madFont(size: 12, weight: .semibold, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            totals(goal)

            CommunityGoalJourney(goal: goal, height: 10)

            if let today = goal.walkingTodayLine {
                CommunityGoalWalkingToday(text: today, size: 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The number that matters, readable from arm's length.
    private func totals(_ goal: CommunityGoal) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(CommunityGoalCopy.count(goal.total_miles))
                .madFont(size: 32, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
            Text("of \(CommunityGoalCopy.whole(goal.target_miles))")
                .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white.opacity(0.7))
            Spacer(minLength: 4)
            Text("\(goal.percent)%")
                .madFont(size: 18, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(MADTheme.Colors.madRed)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// A live dot and how many people have walked today, so the goal feels busy.
struct CommunityGoalWalkingToday: View {
    let text: String
    var size: CGFloat = 13
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.35))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulsing ? 1 : 0.5)
                    .opacity(pulsing ? 0 : 1)
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .madFont(size: size, weight: .semibold, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulsing = true }
        }
    }
}

enum CommunityGoalCopy {
    /// Carries the sharer's username, so the page can say who to pick at sign-up.
    static var shareURL: URL? {
        var parts = URLComponents(string: "https://mileaday.run/goal")
        if let username = UserManager.shared.currentUser.username, !username.isEmpty {
            parts?.queryItems = [URLQueryItem(name: "ref", value: username)]
        }
        return parts?.url
    }

    /// "1,420", in the user's unit.
    static func count(_ miles: Double) -> String { Int(miles.inDisplayUnit).formatted() }

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

/// The way to move the number: bring someone in. Sits outside the card's
/// button, because a share control can't live inside one.
struct CommunityGoalInviteRow: View {
    let goal: CommunityGoal

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                if let pace = goal.paceLine {
                    Text(pace)
                        .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundColor(goal.onPace ? .green : .orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if let line = goal.inviteLine {
                    Text(line)
                        .madFont(size: 13, weight: .semibold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 4)
            if goal.inviteLine != nil, let url = CommunityGoalCopy.shareURL {
                ShareLink(
                    item: url,
                    message: Text("We're walking \(goal.title) together on Mile A Day. Come help us finish!")
                ) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.badge.plus")
                        Text("Invite")
                            .lineLimit(1)
                    }
                    .madFont(size: 14, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(MADTheme.Colors.madRed))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// What's up for grabs, in one slim banner so the rest of the tab stays in
/// view: Flamey in the whole set, and the next piece to earn.
struct CommunityGoalRewardStrip: View {
    let goal: CommunityGoal
    let days: Int

    private var next: CommunityGoal.Reward? { goal.nextReward(days: days) }

    private var progress: String {
        guard let next else { return "Full set earned" }
        if goal.phase == .ended { return "\(days) days walked" }
        return "\(min(days, next.days)) of \(next.days) days"
    }

    var body: some View {
        CommunityRewardStage(look: CommunityRewardLook.wearing(goal.rewards), height: 112, compact: true) {
            VStack(alignment: .leading, spacing: 1) {
                CommunityRewardCaption(eyebrow: next == nil ? "Collection" : "Next to earn",
                                       title: next?.name ?? "\(goal.title) Collection", titleSize: 17)
                Text(progress)
                    .madFont(size: 13, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: 170, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goal.rewards.map { "\($0.name), \($0.days) days" }.joined(separator: ", "))
    }
}

/// The set, tier by tier: tap a piece and Flamey wears everything up to it,
/// so you can see the look build toward the top reward.
struct CommunityRewardShowcase: View {
    let goal: CommunityGoal
    let days: Int
    @State private var selectedID: String?

    private var selected: CommunityGoal.Reward? {
        goal.rewards.first { $0.id == selectedID } ?? goal.rewards.last
    }

    private var worn: [CommunityGoal.Reward] {
        guard let selected else { return [] }
        return goal.rewards.filter { $0.days <= selected.days }
    }

    var body: some View {
        VStack(spacing: 10) {
            if let selected {
                CommunityRewardStage(look: CommunityRewardLook.wearing(worn), height: 330, live: true) {
                    CommunityRewardCaption(eyebrow: CommunityRewardRarity(selected).label, title: selected.name,
                                           color: CommunityRewardRarity(selected).color)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(selected.name), \(CommunityRewardRarity(selected).label)")
            }
            HStack(spacing: 6) {
                ForEach(goal.rewards) { reward in
                    Button {
                        MADHaptics.tap()
                        withAnimation(.easeInOut(duration: 0.2)) { selectedID = reward.id }
                    } label: {
                        CommunityRewardTile(reward: reward, days: days, selected: reward.id == selected?.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(reward.name), \(line(reward))")
                    .accessibilityAddTraits(reward.id == selected?.id ? .isSelected : [])
                }
            }
            if let selected {
                Text(line(selected))
                    .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.4)
                    .foregroundColor(selected.earned ? .green : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func line(_ reward: CommunityGoal.Reward) -> String {
        if reward.earned { return "Earned. It's yours to keep." }
        if goal.phase == .ended { return "Walk \(reward.days) days to earn" }
        return "\(min(days, reward.days)) of \(reward.days) days walked"
    }
}

/// How rare a piece is, for its label and colour.
struct CommunityRewardRarity {
    let label: String
    let color: Color

    init(_ reward: CommunityGoal.Reward) {
        switch reward.rarity {
        case "mythic": label = "Mythic"; color = Color(red: 1, green: 0.36, blue: 0.62)
        case "legendary": label = "Legendary"; color = Color(red: 1, green: 0.72, blue: 0.2)
        case "epic": label = "Epic"; color = Color(red: 0.72, green: 0.52, blue: 1)
        default: label = "Rare"; color = Color(red: 0.36, green: 0.74, blue: 1)
        }
    }
}

enum CommunityRewardLook {
    /// Flamey in these rewards, and nothing else he owns.
    static func wearing(_ rewards: [CommunityGoal.Reward]) -> FlameyLook {
        let items = rewards.compactMap { $0.item_id.flatMap(FlameyItem.init(rawValue:)) }
        var choice = FlameyLookChoice.basic
        for item in items { choice[item.slot] = item }
        return FlameyLook.resolve(owned: Set(items), choice: choice, date: FlameyItemArt.neutralDate, detail: .full)
    }
}

/// The dusk Flamey stands in: sunset over the water, one coast to the other.
struct CommunityRewardStage<Caption: View>: View {
    let look: FlameyLook
    let height: CGFloat
    var live = false
    /// A slim banner: Flamey to the right, words to the left.
    var compact = false
    @ViewBuilder let caption: () -> Caption

    private static var stars: [CGPoint] {
        [(0.08, 0.14), (0.17, 0.32), (0.26, 0.09), (0.36, 0.22), (0.47, 0.07), (0.6, 0.17), (0.71, 0.08),
         (0.8, 0.26), (0.9, 0.12), (0.95, 0.36), (0.04, 0.42), (0.67, 0.34)].map { CGPoint(x: $0.0, y: $0.1) }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Canvas { ctx, size in
                let horizon = size.height - (compact ? 22 : 74)
                let sky = Path(CGRect(x: 0, y: 0, width: size.width, height: horizon))
                ctx.fill(sky, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.05, green: 0.05, blue: 0.24), location: 0),
                        .init(color: Color(red: 0.25, green: 0.08, blue: 0.42), location: 0.42),
                        .init(color: Color(red: 0.78, green: 0.13, blue: 0.4), location: 0.75),
                        .init(color: Color(red: 1, green: 0.5, blue: 0.2), location: 1),
                    ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
                for (i, star) in Self.stars.enumerated() {
                    let r: CGFloat = i.isMultiple(of: 3) ? 1.6 : 1
                    ctx.fill(Path(ellipseIn: CGRect(x: star.x * size.width - r, y: star.y * size.height - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(i.isMultiple(of: 2) ? 0.85 : 0.5)))
                }
                let centre = CGPoint(x: size.width * (compact ? 0.72 : 0.5), y: horizon)
                let glow = size.width * 0.62
                ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.84, blue: 0.45).opacity(0.95),
                                                                 Color(red: 1, green: 0.45, blue: 0.2).opacity(0.35), .clear]),
                                               center: centre, startRadius: 0, endRadius: glow))
                let sea = Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon))
                ctx.fill(sea, with: .linearGradient(
                    Gradient(colors: [Color(red: 0.55, green: 0.16, blue: 0.36), Color(red: 0.05, green: 0.1, blue: 0.3),
                                      Color(red: 0.03, green: 0.05, blue: 0.16)]),
                    startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: size.height)))
                for i in 0..<2 {
                    let y = horizon + CGFloat(i + 1) * 7
                    let half = size.width * (0.14 + CGFloat(i) * 0.05)
                    ctx.fill(Path(roundedRect: CGRect(x: centre.x - half, y: y, width: half * 2, height: 2), cornerRadius: 1),
                             with: .color(Color(red: 1, green: 0.78, blue: 0.45).opacity(0.5 - Double(i) * 0.09)))
                }
            }

            FlameBuddyView(health: .blazing, size: height * (compact ? 0.66 : 0.58), still: !live,
                           showsMoodBubble: false, look: look)
                .frame(maxWidth: .infinity, alignment: compact ? .trailing : .center)
                .padding(.trailing, compact ? 56 : 0)
                .padding(.bottom, compact ? 10 : 58)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .accessibilityHidden(true)

            caption()
                .padding(12)
                .frame(maxHeight: .infinity, alignment: compact ? .center : .bottom)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CommunityRewardCaption: View {
    let eyebrow: String
    let title: String
    var color: Color = Color(red: 1, green: 0.84, blue: 0.5)
    var titleSize: CGFloat = 19

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(eyebrow.uppercased())
                .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.3)
                .tracking(1)
                .foregroundColor(color)
                .lineLimit(1)
            Text(title)
                .madFont(size: titleSize, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

/// One piece of the set: the item on a rarity-lit tile, with your progress.
struct CommunityRewardTile: View {
    let reward: CommunityGoal.Reward
    let days: Int
    let selected: Bool

    private var rarity: CommunityRewardRarity { CommunityRewardRarity(reward) }
    private var progress: Double { min(1, Double(days) / Double(max(reward.days, 1))) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                CommunityRewardArt(reward: reward, size: 58)
                    .frame(maxWidth: .infinity)
                if reward.earned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            Text("\(reward.days) days")
                .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(reward.earned ? Color.green : rarity.color)
                        .frame(width: max(4, geo.size.width * progress))
                }
            }
            .frame(height: 4)
        }
        .padding(7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(RadialGradient(colors: [rarity.color.opacity(0.32), rarity.color.opacity(0.08)],
                                     center: .center, startRadius: 2, endRadius: 56))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(rarity.color.opacity(selected ? 1 : 0.4), lineWidth: selected ? 2 : 1)
        )
    }
}

/// A reward's picture: the Flamey item, or a medal when it has none.
struct CommunityRewardArt: View {
    let reward: CommunityGoal.Reward
    let size: CGFloat

    var body: some View {
        Group {
            if let id = reward.item_id, let item = FlameyItem(rawValue: id) {
                FlameyItemArt(item: item, mannequin: false)
            } else {
                Image(systemName: "medal.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .accessibilityHidden(true)
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
