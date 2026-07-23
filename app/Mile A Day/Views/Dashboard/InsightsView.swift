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

private struct RoadToMilestoneCard: View {
    let streak: Int

    private var nextMajor: StreakMilestone? {
        StreakMilestone.nextMajor(after: streak)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("The Road to \(nextMajor?.days ?? 500)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(roadSubtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.58))
                }
                Spacer()
                Image(systemName: "flag.checkered")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.orange)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.orange.opacity(0.14)))
            }

            GeometryReader { geo in
                ZStack {
                    roadPath(in: geo.size)
                        .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 12]))

                    roadPath(in: geo.size)
                        .trim(from: 0, to: currentRoadProgress)
                        .stroke(
                            LinearGradient(colors: [MADTheme.Colors.madRed, .orange], startPoint: .bottomLeading, endPoint: .topTrailing),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.45), radius: 10)

                    ForEach(nodes.indices, id: \.self) { index in
                        let node = nodes[index]
                        roadNode(node, index: index)
                            .position(point(for: node.position, in: geo.size))
                    }
                }
            }
            .frame(height: 310)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.07, green: 0.055, blue: 0.085))
                .overlay(
                    RadialGradient(colors: [Color.orange.opacity(0.18), Color.clear], center: .bottomLeading, startRadius: 30, endRadius: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                )
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        )
    }

    private var roadSubtitle: String {
        if let nextMajor {
            return "\(max(nextMajor.days - streak, 0)) days out"
        }
        return "Legendary territory"
    }

    private var currentRoadProgress: CGFloat {
        guard let nextMajor else { return 1 }
        let previous = StreakMilestone.allCases
            .filter { $0.isMajor && $0.days <= streak }
            .map(\.days)
            .max() ?? 0
        let span = max(nextMajor.days - previous, 1)
        return CGFloat(max(0, min(Double(streak - previous) / Double(span), 1)))
    }

    private struct Node {
        let label: String
        let caption: String
        let position: CGFloat
        let isCurrent: Bool
        let isReached: Bool
    }

    private var nodes: [Node] {
        let majorDays = [100, 250, 365, 500, 730, 1000]
        let target = nextMajor?.days ?? max(500, streak)
        var result = majorDays
            .filter { $0 <= max(target, streak) }
            .suffix(4)
            .map { day in
                Node(
                    label: "\(day)",
                    caption: day == target ? "Goal" : "Club",
                    position: position(forDay: day, target: target),
                    isCurrent: false,
                    isReached: streak >= day
                )
            }
        result.append(Node(label: "\(streak)", caption: "Today", position: min(max(currentRoadProgress, 0.08), 0.88), isCurrent: true, isReached: true))
        return result.sorted { $0.position < $1.position }
    }

    private func position(forDay day: Int, target: Int) -> CGFloat {
        CGFloat(max(0.05, min(Double(day) / Double(max(target, 1)), 0.95)))
    }

    private func roadNode(_ node: Node, index: Int) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(node.isCurrent ? MADTheme.Colors.madRed : node.isReached ? Color.orange.opacity(0.95) : Color.white.opacity(0.08))
                    .frame(width: node.isCurrent ? 70 : 42, height: node.isCurrent ? 70 : 42)
                    .shadow(color: node.isCurrent ? MADTheme.Colors.madRed.opacity(0.50) : .clear, radius: 14)
                Text(node.label)
                    .font(.system(size: node.isCurrent ? 22 : 13, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }
            Text(node.caption)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(node.isCurrent ? 0.82 : 0.50))
        }
    }

    private func roadPath(in size: CGSize) -> Path {
        var path = Path()
        path.move(to: point(for: 0, in: size))
        path.addCurve(to: point(for: 0.34, in: size), control1: CGPoint(x: size.width * 0.05, y: size.height * 0.86), control2: CGPoint(x: size.width * 0.76, y: size.height * 0.77))
        path.addCurve(to: point(for: 0.68, in: size), control1: CGPoint(x: size.width * 0.02, y: size.height * 0.42), control2: CGPoint(x: size.width * 0.80, y: size.height * 0.48))
        path.addCurve(to: point(for: 1, in: size), control1: CGPoint(x: size.width * 0.18, y: size.height * 0.14), control2: CGPoint(x: size.width * 0.66, y: size.height * 0.10))
        return path
    }

    private func point(for progress: CGFloat, in size: CGSize) -> CGPoint {
        let p = max(0, min(progress, 1))
        let y = size.height * (0.88 - 0.75 * p)
        let x = size.width * (0.18 + 0.64 * (0.5 + 0.5 * sin((p * 2.4 - 0.45) * .pi)))
        return CGPoint(x: x, y: y)
    }
}
