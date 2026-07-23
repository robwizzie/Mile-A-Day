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

    private var goal: StreakMilestone? {
        StreakMilestone.nextMajor(after: streak)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            RoadTrail(stops: stops)
                .frame(height: RoadTrail.trailHeight)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.07, green: 0.055, blue: 0.085))
                .overlay(
                    RadialGradient(colors: [Color.orange.opacity(0.16), Color.clear], center: .bottomLeading, startRadius: 30, endRadius: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                )
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("The Road to \(goal?.days ?? streak)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(roadSubtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.58))
            }
            Spacer()
            Image(systemName: "flag.checkered")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.orange)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.orange.opacity(0.14)))
        }
    }

    private var roadSubtitle: String {
        guard let goal else { return "Legendary territory" }
        let daysToGo = max(goal.days - streak, 0)
        if daysToGo == 0 { return "Goal reached — keep the fire alive" }
        return "\(daysToGo) day\(daysToGo == 1 ? "" : "s") to go · \(streak) done"
    }

    /// The full ladder of major milestones with the runner's live position woven in.
    /// Everything up to `streak` reads as reached; everything past it is locked.
    private var stops: [RoadStop] {
        let majors = StreakMilestone.allCases
            .filter(\.isMajor)
            .sorted { $0.days < $1.days }
        let goalDays = goal?.days

        var result: [RoadStop] = []
        var id = 0
        var placedCurrent = false

        func appendCurrent() {
            result.append(RoadStop(id: id, value: streak, caption: "You", state: .current, isGoal: false))
            id += 1
            placedCurrent = true
        }

        for milestone in majors {
            if !placedCurrent, milestone.days > streak { appendCurrent() }

            if milestone.days == streak {
                result.append(RoadStop(id: id, value: milestone.days, caption: "You", state: .current, isGoal: false))
                placedCurrent = true
            } else {
                let state: RoadStop.State = milestone.days < streak ? .reached : .locked
                let caption = milestone.days == goalDays ? "Goal" : (state == .reached ? "Club" : "Locked")
                result.append(RoadStop(id: id, value: milestone.days, caption: caption, state: state, isGoal: milestone.days == goalDays))
            }
            id += 1
        }

        if !placedCurrent { appendCurrent() }
        return result
    }
}

// MARK: - Road trail

/// A single platform on the road: a reached milestone, the runner's current
/// position, or a locked milestone still ahead.
private struct RoadStop: Identifiable {
    enum State: Equatable { case reached, current, locked }
    let id: Int
    let value: Int
    let caption: String
    let state: State
    let isGoal: Bool
}

/// A horizontally-scrollable road. Milestones are evenly spaced along a gently
/// weaving path that is drawn through the exact same node centers, so platforms
/// always sit *on* the road. Reached segments are solid; the locked road ahead
/// is dashed. Auto-scrolls to the runner's current position on first appear.
private struct RoadTrail: View {
    let stops: [RoadStop]

    static let trailHeight: CGFloat = 198

    private let baseY: CGFloat = 74
    private let amplitude: CGFloat = 15
    private let phase: CGFloat = 0.85
    private let spacing: CGFloat = 108
    private let sidePad: CGFloat = 46
    private let circleCell: CGFloat = 92

    @State private var didScroll = false

    private var centers: [CGPoint] {
        stops.indices.map { i in
            CGPoint(x: sidePad + CGFloat(i) * spacing,
                    y: baseY + amplitude * sin(CGFloat(i) * phase))
        }
    }

    private var contentWidth: CGFloat {
        sidePad * 2 + CGFloat(max(stops.count - 1, 0)) * spacing
    }

    private var currentIndex: Int {
        stops.firstIndex { $0.state == .current } ?? max(stops.count - 1, 0)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    roadLayer
                    ForEach(Array(stops.enumerated()), id: \.element.id) { pair in
                        RoadStopCircle(stop: pair.element)
                            .frame(width: circleCell, height: circleCell)
                            .offset(x: centers[pair.offset].x - circleCell / 2,
                                    y: centers[pair.offset].y - circleCell / 2)
                            .id(pair.element.id)
                    }
                    ForEach(Array(stops.enumerated()), id: \.element.id) { pair in
                        caption(for: pair.element, at: centers[pair.offset])
                    }
                }
                .frame(width: contentWidth, height: Self.trailHeight, alignment: .topLeading)
            }
            .onAppear {
                guard !didScroll, !stops.isEmpty else { return }
                didScroll = true
                DispatchQueue.main.async {
                    proxy.scrollTo(stops[currentIndex].id, anchor: UnitPoint(x: 0.36, y: 0.5))
                }
            }
        }
    }

    private var roadLayer: some View {
        let pts = centers
        let reachedPts = Array(pts.prefix(currentIndex + 1))
        let lockedPts = Array(pts.suffix(pts.count - currentIndex))
        return ZStack {
            smoothPath(through: pts)
                .stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
            smoothPath(through: lockedPts)
                .stroke(Color.white.opacity(0.20), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 11]))
            smoothPath(through: reachedPts)
                .stroke(
                    LinearGradient(colors: [MADTheme.Colors.madRed, .orange], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: MADTheme.Colors.madRed.opacity(0.40), radius: 8, y: 2)
        }
        .frame(width: contentWidth, height: Self.trailHeight, alignment: .topLeading)
    }

    private func caption(for stop: RoadStop, at center: CGPoint) -> some View {
        let radius = RoadStopCircle.diameter(for: stop) / 2
        return Text(stop.caption)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundColor(captionColor(for: stop))
            .lineLimit(1)
            .frame(width: circleCell)
            .offset(x: center.x - circleCell / 2, y: center.y + radius + 9)
    }

    private func captionColor(for stop: RoadStop) -> Color {
        switch stop.state {
        case .current: return MADTheme.Colors.madRed
        case .reached: return stop.isGoal ? .orange : Color.white.opacity(0.62)
        case .locked: return stop.isGoal ? .orange : Color.white.opacity(0.34)
        }
    }

    /// Catmull-Rom spline through the points, expressed as cubic Béziers, so the
    /// road curves smoothly through every platform center.
    private func smoothPath(through pts: [CGPoint]) -> Path {
        var path = Path()
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        for i in 0 ..< pts.count - 1 {
            let p0 = i == 0 ? pts[i] : pts[i - 1]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = (i + 2 < pts.count) ? pts[i + 2] : pts[i + 1]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

/// The platform disc: number in the middle, plus a state badge (check / flag /
/// lock). Locked platforms beyond the runner's streak read as clearly disabled.
private struct RoadStopCircle: View {
    let stop: RoadStop

    static func diameter(for stop: RoadStop) -> CGFloat {
        if stop.state == .current { return 72 }
        if stop.isGoal { return 60 }
        if stop.state == .reached { return 56 }
        return 48
    }

    var body: some View {
        let d = Self.diameter(for: stop)
        ZStack {
            if stop.state == .current {
                Circle()
                    .fill(MADTheme.Colors.madRed.opacity(0.30))
                    .frame(width: d + 26, height: d + 26)
                    .blur(radius: 8)
            }
            ZStack {
                Circle().fill(fillStyle)
                    .overlay(ringOverlay)
                label
            }
            .frame(width: d, height: d)
            .shadow(color: shadowColor, radius: shadowRadius, y: 3)
            .overlay(alignment: .topTrailing) { badge.offset(x: 5, y: -3) }
        }
        .frame(width: 92, height: 92)
    }

    private var fillStyle: AnyShapeStyle {
        if stop.state == .current {
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.95, green: 0.33, blue: 0.44), MADTheme.Colors.madRed],
                startPoint: .top, endPoint: .bottom))
        }
        if stop.state == .reached {
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 1.0, green: 0.74, blue: 0.28), .orange],
                startPoint: .top, endPoint: .bottom))
        }
        // locked (incl. locked goal)
        return AnyShapeStyle(Color.white.opacity(0.05))
    }

    private var ringOverlay: some View {
        Group {
            if stop.isGoal {
                Circle().strokeBorder(Color.orange.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            } else if stop.state == .locked {
                Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1.5)
            } else if stop.state == .current {
                Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2.5)
            } else {
                Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
            }
        }
    }

    private var label: some View {
        Text("\(stop.value)")
            .font(.system(size: numberSize, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundColor(numberColor)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 4)
    }

    private var numberSize: CGFloat {
        if stop.state == .current { return 23 }
        return stop.state == .reached ? 16 : 15
    }

    private var numberColor: Color {
        switch stop.state {
        case .current: return .white
        case .reached: return .white
        case .locked: return stop.isGoal ? .orange : Color.white.opacity(0.5)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if stop.isGoal {
            badgeCircle(icon: "flag.checkered", background: .orange, foreground: .white)
        } else if stop.state == .reached {
            badgeCircle(icon: "checkmark", background: MADTheme.Colors.success, foreground: .white)
        } else if stop.state == .locked {
            badgeCircle(icon: "lock.fill", background: Color(white: 0.22), foreground: Color.white.opacity(0.75))
        }
    }

    private func badgeCircle(icon: String, background: Color, foreground: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 9, weight: .black))
            .foregroundColor(foreground)
            .frame(width: 20, height: 20)
            .background(Circle().fill(background))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
    }

    private var shadowColor: Color {
        switch stop.state {
        case .current: return MADTheme.Colors.madRed.opacity(0.5)
        case .reached: return Color.orange.opacity(0.35)
        case .locked: return .clear
        }
    }

    private var shadowRadius: CGFloat {
        switch stop.state {
        case .current: return 14
        case .reached: return 7
        case .locked: return 0
        }
    }
}
