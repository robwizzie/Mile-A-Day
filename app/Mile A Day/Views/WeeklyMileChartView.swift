//
//  WeeklyMileChartView.swift
//  Mile A Day
//
//  Scroll-collapsible hero chart: expands as a full animated line chart,
//  collapses into a compact week-dot row with streak as the user scrolls.
//

import SwiftUI

// MARK: - Data Model

struct DayData: Identifiable {
    let id = UUID()
    let date: Date
    let label: String          // "Sun", "Mon", …
    let shortLabel: String     // "S", "M", …
    let distance: Double       // miles
    let metGoal: Bool
    let isToday: Bool
    let isFuture: Bool
}

// MARK: - Collapsible Hero Chart

struct WeeklyMileChartView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @Environment(\.colorScheme) var colorScheme

    // Animation state
    @State private var selectedIndex: Int? = nil
    @State private var lineDrawn: Bool = false
    @State private var pointsVisible: [Bool] = Array(repeating: false, count: 7)
    @State private var goalLineVisible: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var hasAppeared: Bool = false

    // Scroll-collapse: driven externally by scroll offset from parent
    var scrollOffset: CGFloat = 0

    // Heights
    private let expandedHeight: CGFloat = 280
    private let collapsedHeight: CGFloat = 72

    // MARK: Derived data

    private var goalDistance: Double {
        userManager.currentUser.goalMiles
    }

    private var weekDays: [DayData] {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromSunday = weekday - 1
        guard let startOfWeek = calendar.date(byAdding: .day, value: -daysFromSunday, to: calendar.startOfDay(for: today)) else {
            return []
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        return (0..<7).compactMap { offset -> DayData? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startOfWeek) else { return nil }
            let startOfDay = calendar.startOfDay(for: date)
            let isToday = calendar.isDateInToday(date)
            let isFuture = startOfDay > calendar.startOfDay(for: today)
            let miles: Double
            if isFuture {
                miles = goalDistance   // plot at goal line as a target
            } else if let index = healthManager.workoutIndex {
                miles = index.totalMiles(for: startOfDay)
            } else {
                let goalMet = healthManager.dailyMileGoals[startOfDay] ?? false
                miles = goalMet ? max(goalDistance, 1.0) : 0.0
            }
            let label = dayFormatter.string(from: date)
            let shortLabel = String(label.prefix(1))
            let met = !isFuture && miles >= goalDistance * 0.95
            return DayData(date: date, label: label, shortLabel: shortLabel, distance: miles, metGoal: met, isToday: isToday, isFuture: isFuture)
        }
    }

    private var currentStreak: Int {
        userManager.currentUser.streak
    }

    private var daysCompletedThisWeek: Int {
        weekDays.filter { $0.metGoal }.count
    }

    /// Number of days so far this week (including today)
    private var daysSoFarThisWeek: Int {
        weekDays.filter { !$0.isFuture }.count
    }

    // MARK: Colors

    private let accentRed = Color(red: 0.85, green: 0.25, blue: 0.35)
    private let missedOrange = Color(red: 1.0, green: 0.6, blue: 0.0)
    private let goalLineColor = Color.white.opacity(0.35)

    // MARK: Body

    var body: some View {
        // Compute collapse progress from scroll offset (0 = expanded, 1 = collapsed)
        let scrolled = max(-scrollOffset, 0)
        let collapseProgress = min(scrolled / 200, 1)
        let currentHeight = expandedHeight - (expandedHeight - collapsedHeight) * collapseProgress

        // Phase opacities — tuned so content crossfades without gaps or overlaps
        let expandedHeaderOpacity = min(max(1 - collapseProgress / 0.3, 0), 1)
        let collapsedHeaderOpacity = min(max((collapseProgress - 0.15) / 0.25, 0), 1)
        let chartOpacity = min(max(1 - max(collapseProgress - 0.3, 0) / 0.35, 0), 1)
        let dotsOpacity = min(max((collapseProgress - 0.55) / 0.35, 0), 1)

        ZStack(alignment: .top) {
            // Card background
            cardBackground

            VStack(alignment: .leading, spacing: 0) {
                // Morphing header: expanded ↔ collapsed
                ZStack(alignment: .leading) {
                    expandedHeader
                        .opacity(expandedHeaderOpacity)
                    collapsedHeaderRow
                        .opacity(collapsedHeaderOpacity)
                }

                // Content area: chart compresses via clipping, dots fade in
                ZStack(alignment: .top) {
                    // Chart (always rendered at full 180pt, bottom cropped as card shrinks)
                    chartArea
                        .padding(.top, 6)
                        .opacity(chartOpacity)

                    // Dots row (fades in during late collapse)
                    collapsedDotsRow
                        .padding(.top, 6)
                        .opacity(dotsOpacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .frame(height: currentHeight)
        .clipped()
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                runEntryAnimation()
            }
        }
        .onChange(of: healthManager.workoutIndex?.lastUpdated) {
            resetAndAnimate()
        }
        .sheet(isPresented: $showShareSheet) {
            EnhancedShareView(
                user: userManager.currentUser,
                currentDistance: healthManager.todaysDistance,
                progress: ProgressCalculator.calculateProgress(
                    current: healthManager.todaysDistance,
                    goal: userManager.currentUser.goalMiles
                ),
                isGoalCompleted: ProgressCalculator.isGoalCompleted(
                    current: healthManager.todaysDistance,
                    goal: userManager.currentUser.goalMiles
                ),
                fastestPace: userManager.currentUser.fastestMilePace,
                mostMiles: healthManager.cachedMostMilesInOneDay > 0
                    ? healthManager.cachedMostMilesInOneDay
                    : healthManager.mostMilesInOneDay,
                totalMiles: healthManager.totalLifetimeMiles
            )
        }
    }

    // MARK: - Expanded Header

    private var expandedHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This Week")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("\(daysCompletedThisWeek) of \(daysSoFarThisWeek) day\(daysSoFarThisWeek == 1 ? "" : "s") hit")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Share button
            Button {
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12))
                    )
            }

            streakBadge
        }
    }

    // MARK: - Collapsed Header Row (flame + "Streak" ... "X days")

    private var collapsedHeaderRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, accentRed], startPoint: .top, endPoint: .bottom)
                    )
                Text("Streak")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(currentStreak)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("days")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Collapsed Dots Row (7 circle indicators)

    private var collapsedDotsRow: some View {
        HStack(spacing: 0) {
            ForEach(weekDays) { day in
                Spacer()
                collapsedDot(day: day)
                Spacer()
            }
        }
    }

    private func collapsedDot(day: DayData) -> some View {
        ZStack {
            if day.isFuture {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 26, height: 26)
            } else if day.metGoal {
                Circle()
                    .stroke(Color.green, lineWidth: 2)
                    .frame(width: 26, height: 26)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
            } else if day.distance > 0 {
                Circle()
                    .fill(missedOrange.opacity(0.3))
                    .frame(width: 26, height: 26)
                Circle()
                    .fill(missedOrange)
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 26, height: 26)
            }

            if day.isToday {
                Circle()
                    .stroke(accentRed, lineWidth: 2)
                    .frame(width: 30, height: 30)
            }
        }
    }

    // MARK: - Streak Badge

    private var streakBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 13))
                .foregroundColor(.orange)
            Text("\(currentStreak)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.15))
        )
    }

    // MARK: - Chart Drawing Area

    private var chartArea: some View {
        GeometryReader { geo in
            let size = geo.size
            let data = weekDays
            let maxY = max(chartMaxY(data: data), goalDistance * 1.4, 1.5)
            let points = chartPoints(data: data, size: size, maxY: maxY)
            let goalY = yPosition(for: goalDistance, height: size.height, maxY: maxY)

            // Split into active (past+today) and future
            let activeCount = data.filter { !$0.isFuture }.count
            let activePoints = Array(points.prefix(activeCount))
            let activeData = Array(data.prefix(activeCount))

            ZStack(alignment: .topLeading) {
                // Gradient fill under the line (active days only)
                if activePoints.count >= 2 {
                    areaFill(points: activePoints, size: size)
                        .opacity(lineDrawn ? 0.25 : 0)
                        .animation(.easeInOut(duration: 0.5).delay(0.6), value: lineDrawn)
                }

                // Goal line
                goalLine(y: goalY, width: size.width)
                    .opacity(goalLineVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5), value: goalLineVisible)

                // "Today" vertical marker line
                if activeCount > 0, activeCount < data.count {
                    let todayX = points[activeCount - 1].x
                    Path { p in
                        p.move(to: CGPoint(x: todayX, y: 0))
                        p.addLine(to: CGPoint(x: todayX, y: size.height - 24))
                    }
                    .stroke(accentRed.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                // Solid line for active days
                if activePoints.count >= 2 {
                    animatedLine(points: activePoints, data: activeData)
                }

                // Dashed faint line from today into future days
                if activeCount > 0, activeCount < data.count {
                    let futureSegmentPoints = Array(points[(activeCount - 1)...])
                    let futurePath = smoothPath(points: futureSegmentPoints)
                    futurePath.stroke(
                        Color.white.opacity(0.10),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 6])
                    )
                }

                // Data points
                ForEach(0..<min(data.count, points.count), id: \.self) { i in
                    if data[i].isFuture {
                        futureDayPlaceholder(at: points[i])
                    } else {
                        dataPoint(at: points[i], data: data[i], index: i)
                    }
                }

                // Tooltip (only for non-future days)
                if let idx = selectedIndex, idx < points.count, idx < data.count, !data[idx].isFuture {
                    tooltip(for: data[idx], at: points[idx], chartWidth: size.width)
                }

                // X-axis labels
                xAxisLabels(data: data, points: points, height: size.height)
            }
        }
        .frame(height: 180)
    }

    // MARK: - Area Fill

    private func areaFill(points: [CGPoint], size: CGSize) -> some View {
        let path = smoothPath(points: points)
        var area = path
        area.addLine(to: CGPoint(x: points.last!.x, y: size.height - 20))
        area.addLine(to: CGPoint(x: points.first!.x, y: size.height - 20))
        area.closeSubpath()

        return area.fill(
            LinearGradient(
                colors: [accentRed.opacity(0.4), accentRed.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Goal Line

    private func goalLine(y: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: width, y: y))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            .foregroundColor(goalLineColor)

            Text(String(format: "%.1f mi", goalDistance))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .offset(x: 0, y: y - 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    // MARK: - Animated Line

    private func animatedLine(points: [CGPoint], data: [DayData]) -> some View {
        let path = smoothPath(points: points)

        return ZStack {
            // Shadow glow
            path.stroke(
                accentRed.opacity(0.4),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )
            .blur(radius: 4)

            // Main colored line
            path.trim(from: 0, to: lineDrawn ? 1 : 0)
                .stroke(
                    LinearGradient(
                        stops: gradientStops(data: data, points: points),
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .animation(.easeInOut(duration: 0.8), value: lineDrawn)
        }
    }

    // MARK: - Data Points

    private func dataPoint(at point: CGPoint, data: DayData, index: Int) -> some View {
        let isSelected = selectedIndex == index
        let color = data.metGoal ? accentRed : missedOrange
        let radius: CGFloat = data.isToday ? 7 : 5
        let visible = pointsVisible.indices.contains(index) ? pointsVisible[index] : false

        return ZStack {
            if data.isToday || isSelected {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: radius * 3, height: radius * 3)
            }
            Circle()
                .fill(color)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(Color.white)
                .frame(width: radius * 0.8, height: radius * 0.8)
        }
        .scaleEffect(isSelected ? 1.25 : (visible ? 1.0 : 0.01))
        .opacity(visible ? 1 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: visible)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .position(point)
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                selectedIndex = selectedIndex == index ? nil : index
            }
        }
    }

    // MARK: - Tooltip

    private func tooltip(for data: DayData, at point: CGPoint, chartWidth: CGFloat) -> some View {
        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f
        }()
        let distText = data.isFuture ? "—" : String(format: "%.2f mi", data.distance)
        let dateText = dateFormatter.string(from: data.date)

        let tooltipWidth: CGFloat = 90
        let clampedX = min(max(point.x, tooltipWidth / 2 + 4), chartWidth - tooltipWidth / 2 - 4)

        return VStack(spacing: 2) {
            Text(distText)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(dateText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.15, green: 0.15, blue: 0.18))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        )
        .position(x: clampedX, y: max(point.y - 30, 20))
        .transition(.scale.combined(with: .opacity))
        .zIndex(10)
    }

    // MARK: - Future Day Placeholder

    private func futureDayPlaceholder(at point: CGPoint) -> some View {
        Circle()
            .strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            .frame(width: 10, height: 10)
            .position(point)
            .allowsHitTesting(false)
    }

    // MARK: - X-Axis Labels

    private func xAxisLabels(data: [DayData], points: [CGPoint], height: CGFloat) -> some View {
        ForEach(0..<min(data.count, points.count), id: \.self) { i in
            VStack(spacing: 1) {
                if data[i].isToday {
                    Text("TODAY")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundColor(accentRed)
                } else {
                    Text(data[i].label)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundColor(data[i].isFuture ? .white.opacity(0.2) : .secondary)
                }
            }
            .position(x: points[i].x, y: height - 4)
        }
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    accentRed.opacity(0.06),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    // MARK: - Geometry Helpers

    private func chartMaxY(data: [DayData]) -> Double {
        let maxDistance = data.map(\.distance).max() ?? 0
        return max(maxDistance, goalDistance) * 1.3
    }

    private func chartPoints(data: [DayData], size: CGSize, maxY: Double) -> [CGPoint] {
        let chartHeight = size.height - 24
        let count = data.count
        guard count > 0 else { return [] }
        let spacing = size.width / CGFloat(count)

        return data.enumerated().map { i, d in
            let x = spacing * CGFloat(i) + spacing / 2
            let y = chartHeight - (CGFloat(d.distance / maxY) * (chartHeight - 16)) + 8
            return CGPoint(x: x, y: y)
        }
    }

    private func yPosition(for value: Double, height: CGFloat, maxY: Double) -> CGFloat {
        let chartHeight = height - 24
        return chartHeight - (CGFloat(value / maxY) * (chartHeight - 16)) + 8
    }

    // MARK: - Smooth Catmull-Rom → Cubic Bezier Path

    private func smoothPath(points: [CGPoint]) -> Path {
        guard points.count >= 2 else { return Path() }

        var path = Path()
        path.move(to: points[0])

        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = (i + 2 < points.count) ? points[i + 2] : points[i + 1]

            let d1 = distance(p0, p1)
            let d2 = distance(p1, p2)
            let d3 = distance(p2, p3)

            let b1: CGPoint
            let b2: CGPoint

            if d1 < 0.001 {
                b1 = p1
            } else {
                let factor = d2 / (3 * (d1 + d2))
                b1 = CGPoint(
                    x: p1.x + factor * (p2.x - p0.x),
                    y: p1.y + factor * (p2.y - p0.y)
                )
            }

            if d3 < 0.001 {
                b2 = p2
            } else {
                let factor = d2 / (3 * (d2 + d3))
                b2 = CGPoint(
                    x: p2.x - factor * (p3.x - p1.x),
                    y: p2.y - factor * (p3.y - p1.y)
                )
            }

            path.addCurve(to: p2, control1: b1, control2: b2)
        }
        return path
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    // MARK: - Gradient Stops (red vs orange per segment)

    private func gradientStops(data: [DayData], points: [CGPoint]) -> [Gradient.Stop] {
        guard data.count >= 2, points.count >= 2 else {
            return [Gradient.Stop(color: accentRed, location: 0)]
        }

        var stops: [Gradient.Stop] = []

        for i in 0..<data.count {
            let color = data[i].metGoal ? accentRed : missedOrange
            let location = points[i].x / (points.last?.x ?? 1)

            if i > 0 {
                let prevMet = data[i - 1].metGoal
                if data[i].metGoal != prevMet {
                    let prevColor = prevMet ? accentRed : missedOrange
                    let midLocation = ((stops.last?.location ?? 0) + location) / 2
                    stops.append(Gradient.Stop(color: prevColor, location: max(midLocation - 0.02, 0)))
                    stops.append(Gradient.Stop(color: color, location: min(midLocation + 0.02, 1)))
                }
            }
            stops.append(Gradient.Stop(color: color, location: location))
        }

        stops.sort { $0.location < $1.location }
        return stops
    }

    // MARK: - Entry Animation

    private func runEntryAnimation() {
        lineDrawn = false
        goalLineVisible = false
        pointsVisible = Array(repeating: false, count: 7)
        selectedIndex = nil

        withAnimation { goalLineVisible = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            lineDrawn = true
        }

        for i in 0..<7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7 + Double(i) * 0.07) {
                withAnimation {
                    if pointsVisible.indices.contains(i) {
                        pointsVisible[i] = true
                    }
                }
            }
        }
    }

    private func resetAndAnimate() {
        lineDrawn = false
        goalLineVisible = false
        pointsVisible = Array(repeating: false, count: 7)
        selectedIndex = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            runEntryAnimation()
        }
    }
}


// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.08, blue: 0.1),
                Color(red: 0.05, green: 0.02, blue: 0.04)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        ScrollView {
            VStack(spacing: 16) {
                WeeklyMileChartView(
                    healthManager: HealthKitManager(),
                    userManager: UserManager(),
                    scrollOffset: 0
                )

                ForEach(0..<5) { _ in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .frame(height: 120)
                }
            }
            .padding()
        }
        .coordinateSpace(name: "dashboardScroll")
    }
}
