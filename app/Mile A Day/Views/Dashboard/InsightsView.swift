import SwiftUI
import HealthKit

struct InsightsView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @Binding var showWorkouts: Bool

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea()
            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    RoadToMilestoneCard(streak: userManager.currentUser.streak)

                    WeeklyMileChartView(healthManager: healthManager, userManager: userManager)
                    WeeklyTrendCard(healthManager: healthManager, userManager: userManager)

                    StatsGridView(user: userManager.currentUser, healthManager: healthManager)
                    RecentWorkoutsPreviewCard(healthManager: healthManager, showWorkouts: $showWorkouts)
                }
                .padding(MADTheme.Spacing.md)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Road to milestone

/// A vertical "journey" up the streak ladder. Conquered clubs sit at the top,
/// the glowing "You're here" hero card marks the runner's live position with a
/// progress bar to the next club, and every milestone still ahead descends
/// below — locked, with a countdown to unlock — ending at the ultimate goal.
/// The card grows with the ladder and scrolls as part of the Insights page.
private struct RoadToMilestoneCard: View {
    let streak: Int

    private var goal: StreakMilestone? {
        StreakMilestone.nextMajor(after: streak)
    }

    /// Highest major milestone the runner has already passed (0 if none yet).
    private var prevReachedDay: Int {
        StreakMilestone.allCases
            .filter { $0.isMajor && $0.days <= streak }
            .map(\.days)
            .max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { pair in
                    RoadRow(
                        row: pair.element,
                        streak: streak,
                        isFirst: pair.offset == 0,
                        isLast: pair.offset == rows.count - 1
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.07, green: 0.055, blue: 0.085))
                .overlay(
                    RadialGradient(colors: [Color.orange.opacity(0.16), Color.clear], center: .topTrailing, startRadius: 20, endRadius: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                )
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("The Road to \(goal?.days ?? streak)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(headerSubtitle)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            progressRing
        }
    }

    private var headerSubtitle: String {
        guard let goal else { return "Every club conquered — you're in legendary territory." }
        let daysToGo = max(goal.days - streak, 0)
        if daysToGo == 0 { return "You just hit the \(goal.days) Club — keep the fire alive." }
        return "\(daysToGo) day\(daysToGo == 1 ? "" : "s") to the \(goal.days) Club"
    }

    private var progressRing: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 5)
            Circle()
                .trim(from: 0, to: goalProgress)
                .stroke(
                    LinearGradient(colors: [MADTheme.Colors.madRed, .orange], startPoint: .top, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: MADTheme.Colors.madRed.opacity(0.4), radius: 5)
            Image(systemName: "flag.checkered")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.orange)
        }
        .frame(width: 48, height: 48)
    }

    private var goalProgress: CGFloat {
        guard let goal else { return 1 }
        let span = max(goal.days - prevReachedDay, 1)
        return CGFloat(max(0, min(Double(streak - prevReachedDay) / Double(span), 1)))
    }

    // MARK: Ladder model

    /// Ascending ladder (100 at top → 1000 at bottom) with the runner's live
    /// position woven in between the last reached and the first locked club.
    private var rows: [RoadRowModel] {
        let majors = StreakMilestone.allCases
            .filter(\.isMajor)
            .sorted { $0.days < $1.days }
        let goalDays = goal?.days

        var result: [RoadRowModel] = []
        var id = 0
        var placedYou = false

        func appendYou(emoji: String) {
            result.append(RoadRowModel(id: id, kind: .current, day: streak, emoji: emoji,
                                       isGoal: false, subtitle: "", prevDay: prevReachedDay, nextDay: goalDays))
            id += 1
            placedYou = true
        }

        for milestone in majors {
            if !placedYou, milestone.days > streak { appendYou(emoji: "🔥") }

            if milestone.days == streak {
                appendYou(emoji: milestone.emoji)
            } else {
                let kind: RoadRowModel.Kind = milestone.days < streak ? .reached : .locked
                result.append(RoadRowModel(id: id, kind: kind, day: milestone.days, emoji: milestone.emoji,
                                           isGoal: milestone.days == goalDays, subtitle: milestone.majorSubtitle,
                                           prevDay: 0, nextDay: nil))
                id += 1
            }
        }

        if !placedYou { appendYou(emoji: "🔥") }
        return result
    }
}

/// One rung of the ladder.
private struct RoadRowModel: Identifiable {
    enum Kind: Equatable { case reached, current, locked }
    let id: Int
    let kind: Kind
    let day: Int          // milestone day, or the current streak for `.current`
    let emoji: String
    let isGoal: Bool      // the next major milestone — the flagged target
    let subtitle: String
    let prevDay: Int      // (current only) previous reached club
    let nextDay: Int?     // (current only) next goal day
}

// MARK: - Road row

/// A timeline row: a rail on the left (the road + node) and a content card on
/// the right. The rail's road is solid/gold where the runner has travelled and
/// dashed where the road is still locked ahead.
private struct RoadRow: View {
    let row: RoadRowModel
    let streak: Int
    let isFirst: Bool
    let isLast: Bool

    private static let nodeCenterY: CGFloat = 26
    private static let railWidth: CGFloat = 46

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rail
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, isLast ? 0 : 16)
        }
    }

    // MARK: Rail (road + node)

    private var rail: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .top) {
                if !isFirst {
                    segment(from: 0, to: Self.nodeCenterY, width: w, travelled: upperTravelled)
                }
                if !isLast {
                    segment(from: Self.nodeCenterY, to: h, width: w, travelled: lowerTravelled)
                }
                node.offset(y: Self.nodeCenterY - nodeDiameter / 2)
            }
        }
        .frame(width: Self.railWidth)
    }

    /// A reached row has road on both sides; the current row has travelled road
    /// only above it; a locked row is dashed on both sides.
    private var upperTravelled: Bool { row.kind != .locked }
    private var lowerTravelled: Bool { row.kind == .reached }

    private func segment(from y0: CGFloat, to y1: CGFloat, width w: CGFloat, travelled: Bool) -> some View {
        Path { p in
            p.move(to: CGPoint(x: w / 2, y: y0))
            p.addLine(to: CGPoint(x: w / 2, y: y1))
        }
        .stroke(
            travelled
                ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.74, blue: 0.28), MADTheme.Colors.madRed], startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(Color.white.opacity(0.16)),
            style: travelled
                ? StrokeStyle(lineWidth: 4, lineCap: .round)
                : StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 7])
        )
    }

    private var nodeDiameter: CGFloat {
        switch row.kind {
        case .current: return 46
        case .reached: return 38
        case .locked: return row.isGoal ? 42 : 36
        }
    }

    private var node: some View {
        ZStack {
            if row.kind == .current {
                Circle()
                    .fill(MADTheme.Colors.madRed.opacity(0.32))
                    .frame(width: nodeDiameter + 18, height: nodeDiameter + 18)
                    .blur(radius: 7)
            }
            Circle()
                .fill(nodeFill)
                .overlay(nodeRing)
                .frame(width: nodeDiameter, height: nodeDiameter)
                .shadow(color: nodeShadow, radius: nodeShadowRadius, y: 2)
            nodeIcon
        }
    }

    private var nodeFill: AnyShapeStyle {
        switch row.kind {
        case .current:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.95, green: 0.33, blue: 0.44), MADTheme.Colors.madRed], startPoint: .top, endPoint: .bottom))
        case .reached:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.74, blue: 0.28), .orange], startPoint: .top, endPoint: .bottom))
        case .locked:
            return AnyShapeStyle(Color.white.opacity(0.05))
        }
    }

    private var nodeRing: some View {
        Group {
            if row.isGoal {
                Circle().strokeBorder(Color.orange.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            } else if row.kind == .locked {
                Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1.5)
            } else if row.kind == .current {
                Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2.5)
            } else {
                Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder
    private var nodeIcon: some View {
        switch row.kind {
        case .current:
            Image(systemName: "flame.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.white)
        case .reached:
            Text(row.emoji).font(.system(size: 17))
        case .locked:
            if row.isGoal {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.orange)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
    }

    private var nodeShadow: Color {
        switch row.kind {
        case .current: return MADTheme.Colors.madRed.opacity(0.5)
        case .reached: return Color.orange.opacity(0.35)
        case .locked: return .clear
        }
    }

    private var nodeShadowRadius: CGFloat {
        switch row.kind {
        case .current: return 12
        case .reached: return 6
        case .locked: return 0
        }
    }

    // MARK: Content card

    @ViewBuilder
    private var content: some View {
        switch row.kind {
        case .reached: reachedContent
        case .current: currentContent
        case .locked: lockedContent
        }
    }

    private var reachedContent: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(row.day) Club")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Unlocked")
                    .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                    .foregroundColor(.orange.opacity(0.9))
            }
            Spacer(minLength: 4)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18))
                .foregroundColor(MADTheme.Colors.success)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.14), lineWidth: 1))
        )
    }

    private var currentContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOU'RE HERE")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundColor(MADTheme.Colors.madRed)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(row.day)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text("day streak")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Text("🔥").font(.system(size: 17))
            }
            if let next = row.nextDay {
                ProgressToNext(streak: row.day, prevDay: row.prevDay, nextDay: next)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MADTheme.Colors.madRed.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(MADTheme.Colors.madRed.opacity(0.5), lineWidth: 1.5))
        )
        .shadow(color: MADTheme.Colors.madRed.opacity(0.25), radius: 12, y: 4)
    }

    private var lockedContent: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(row.day) Club")
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundColor(row.isGoal ? .white : .white.opacity(0.5))
                    if row.isGoal {
                        Text("NEXT GOAL")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.16)))
                    }
                }
                Text(lockedSubtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(row.isGoal ? .orange.opacity(0.9) : .white.opacity(0.32))
            }
            Spacer(minLength: 4)
            if !row.isGoal {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.28))
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(row.isGoal ? 0.04 : 0.025))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(row.isGoal ? Color.orange.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private var lockedSubtitle: String {
        let daysAway = max(row.day - streak, 0)
        if row.isGoal { return "\(daysAway) day\(daysAway == 1 ? "" : "s") to go" }
        return "\(daysAway) day\(daysAway == 1 ? "" : "s") to unlock"
    }
}

/// Progress bar from the last reached club to the next goal, shown on the hero.
private struct ProgressToNext: View {
    let streak: Int
    let prevDay: Int
    let nextDay: Int

    private var fraction: CGFloat {
        CGFloat(max(0, min(Double(streak - prevDay) / Double(max(nextDay - prevDay, 1)), 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [MADTheme.Colors.madRed, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * fraction, 8))
                }
            }
            .frame(height: 8)
            Text("\(max(nextDay - streak, 0)) days to the \(nextDay) Club")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.65))
        }
    }
}
