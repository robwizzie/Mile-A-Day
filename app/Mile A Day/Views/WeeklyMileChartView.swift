//
//  WeeklyMileChartView.swift
//  Mile A Day
//
//  Animated weekly distance chart with goal line, color-coded segments,
//  tap-to-inspect tooltips, and a share button.
//

import SwiftUI

// MARK: - Data Model

struct DayData: Identifiable {
    let id = UUID()
    let date: Date
    let label: String          // "Mon", "Tue", …
    let distance: Double       // miles
    let metGoal: Bool
    let isToday: Bool
}

// MARK: - Main View

struct WeeklyMileChartView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedIndex: Int? = nil
    @State private var lineDrawn: Bool = false
    @State private var pointsVisible: [Bool] = Array(repeating: false, count: 7)
    @State private var goalLineVisible: Bool = false
    @State private var showShareSheet: Bool = false

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
            let miles: Double
            if let index = healthManager.workoutIndex {
                miles = index.totalMiles(for: startOfDay)
            } else {
                // Fallback: use dailyMileGoals presence to infer at least 0.95
                let goalMet = healthManager.dailyMileGoals[startOfDay] ?? false
                miles = goalMet ? max(goalDistance, 1.0) : 0.0
            }
            let label = dayFormatter.string(from: date)
            let isToday = calendar.isDateInToday(date)
            let met = miles >= goalDistance * 0.95  // same qualifying threshold
            return DayData(date: date, label: label, distance: miles, metGoal: met, isToday: isToday)
        }
    }

    private var currentStreak: Int {
        userManager.currentUser.streak
    }

    // MARK: Colors

    private let accentRed = Color(red: 0.85, green: 0.25, blue: 0.35)
    private let missedOrange = Color(red: 1.0, green: 0.6, blue: 0.0)
    private let goalLineColor = Color.white.opacity(0.35)

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            chartArea
                .padding(.top, 8)
        }
        .padding(16)
        .background(cardBackground)
        .onAppear { runEntryAnimation() }
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

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentRed, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("This Week")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
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

            // Streak badge
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
    }

    // MARK: - Chart Drawing Area

    private var chartArea: some View {
        GeometryReader { geo in
            let size = geo.size
            let data = weekDays
            let maxY = max(chartMaxY(data: data), goalDistance * 1.4, 1.5)
            let points = chartPoints(data: data, size: size, maxY: maxY)
            let goalY = yPosition(for: goalDistance, height: size.height, maxY: maxY)

            ZStack(alignment: .topLeading) {
                // Gradient fill under the line
                if points.count >= 2 {
                    areaFill(points: points, size: size)
                        .opacity(lineDrawn ? 0.25 : 0)
                        .animation(.easeInOut(duration: 0.5).delay(0.6), value: lineDrawn)
                }

                // Goal line
                goalLine(y: goalY, width: size.width, maxY: maxY)
                    .opacity(goalLineVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5), value: goalLineVisible)

                // Animated line path
                if points.count >= 2 {
                    animatedLine(points: points, data: data, size: size)
                }

                // Data points
                ForEach(0..<min(data.count, points.count), id: \.self) { i in
                    dataPoint(at: points[i], data: data[i], index: i)
                }

                // Tooltip
                if let idx = selectedIndex, idx < points.count, idx < data.count {
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

    private func goalLine(y: CGFloat, width: CGFloat, maxY: Double) -> some View {
        ZStack(alignment: .trailing) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: width, y: y))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            .foregroundColor(goalLineColor)

            // Goal label
            Text(String(format: "%.1f mi", goalDistance))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .offset(x: 0, y: y - 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    // MARK: - Animated Line

    private func animatedLine(points: [CGPoint], data: [DayData], size: CGSize) -> some View {
        let path = smoothPath(points: points)

        return ZStack {
            // Shadow glow
            path.stroke(
                accentRed.opacity(0.4),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )
            .blur(radius: 4)

            // Main colored line – red for met, orange for missed
            // We draw two masked copies of the path
            path.trim(from: 0, to: lineDrawn ? 1 : 0)
                .stroke(
                    LinearGradient(
                        stops: gradientStops(data: data, points: points, pathLength: pathLength(points: points)),
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
            // Outer glow
            if data.isToday || isSelected {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: radius * 3, height: radius * 3)
            }
            // Filled circle
            Circle()
                .fill(color)
                .frame(width: radius * 2, height: radius * 2)
            // Inner white dot
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
        let distText = String(format: "%.2f mi", data.distance)
        let dateText = dateFormatter.string(from: data.date)

        // Clamp tooltip so it doesn't go off-screen
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

    // MARK: - X-Axis Labels

    private func xAxisLabels(data: [DayData], points: [CGPoint], height: CGFloat) -> some View {
        ForEach(0..<min(data.count, points.count), id: \.self) { i in
            Text(data[i].label)
                .font(.system(size: 10, weight: data[i].isToday ? .bold : .regular, design: .rounded))
                .foregroundColor(data[i].isToday ? .primary : .secondary)
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
        let chartHeight = size.height - 24   // room for x labels
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

        // Catmull-Rom spline converted to cubic bezier segments
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

    private func gradientStops(data: [DayData], points: [CGPoint], pathLength: CGFloat) -> [Gradient.Stop] {
        guard data.count >= 2, pathLength > 0 else {
            return [Gradient.Stop(color: accentRed, location: 0)]
        }

        var stops: [Gradient.Stop] = []

        for i in 0..<data.count {
            let color = data[i].metGoal ? accentRed : missedOrange
            let location = points[i].x / (points.last?.x ?? 1)

            // Add a small transition zone
            if i > 0 {
                let prevColor = data[i - 1].metGoal ? accentRed : missedOrange
                if prevColor != color {
                    let midLocation = ((stops.last?.location ?? 0) + location) / 2
                    stops.append(Gradient.Stop(color: prevColor, location: max(midLocation - 0.02, 0)))
                    stops.append(Gradient.Stop(color: color, location: min(midLocation + 0.02, 1)))
                }
            }
            stops.append(Gradient.Stop(color: color, location: location))
        }

        // Deduplicate / ensure sorted
        stops.sort { $0.location < $1.location }
        return stops
    }

    private func pathLength(points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var length: CGFloat = 0
        for i in 1..<points.count {
            length += distance(points[i - 1], points[i])
        }
        return length
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

        // Stagger data point reveals
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

        WeeklyMileChartView(
            healthManager: HealthKitManager(),
            userManager: UserManager()
        )
        .padding()
    }
}
