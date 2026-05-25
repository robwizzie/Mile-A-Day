import SwiftUI

/// Apple-Fitness-inspired strip of 7 rings showing the current user's past
/// week in this competition. Each ring is one day, oldest left → today right.
///
/// Ring layout (mode-aware):
///   • Outer ring (gradient/orange) — your miles vs the day's leader (clash/apex)
///     OR vs the daily goal (streaks/targets) OR vs a 1-mile baseline (race)
///   • Center icon — mode-specific status:
///       clash:   👑 if you won the day, • if active, blank if no activity
///       streaks: ❤ if hit, ✗ if life lost, ◯ if pending
///       targets: ✓ if hit, partial bar if active, blank if missed
///       apex:    ⬆ if you led the day, • if active, blank if no activity
///       race:    miles number itself
///   • Day label below (M / T / W / …) — today's label is the comp's accent
///
/// Each ring is tappable; tapping opens the day-detail sheet (same one used
/// by the scoreboard grid below). Visually anchors the active view so the
/// user's own week-long arc is the first thing they see.
struct CompetitionMyDailyRings: View {
    let competition: Competition

    @State private var selectedDate: Date?

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    private var me: CompetitionUser? {
        guard let id = currentUserId else { return nil }
        return competition.users.first(where: { $0.user_id == id })
    }

    private var accepted: [CompetitionUser] {
        competition.users.filter { $0.invite_status == .accepted }
    }

    private var interval: CompetitionInterval {
        competition.options.interval ?? .day
    }

    private var gradientColors: [Color] {
        competition.type.gradient.map { Color(hex: $0) }
    }

    /// 7 anchor dates oldest → today. Clamped to the competition's start.
    private var dates: [Date] {
        let cal = Calendar.current
        let now = Date()
        let compStart = competition.startDateFormatted ?? cal.date(byAdding: .day, value: -6, to: now)!
        var result: [Date] = []
        for offset in (0..<7).reversed() {
            let d: Date?
            switch interval {
            case .day: d = cal.date(byAdding: .day, value: -offset, to: now)
            case .week: d = cal.date(byAdding: .weekOfYear, value: -offset, to: now)
            case .month: d = cal.date(byAdding: .month, value: -offset, to: now)
            }
            if let date = d, date >= cal.startOfDay(for: compStart) {
                result.append(date)
            }
        }
        return result
    }

    private func intervalKey(for date: Date) -> String {
        let cal = Calendar.current
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        switch interval {
        case .day: return f.string(from: cal.startOfDay(for: date))
        case .week: return competition.weeklyIntervalKey(for: date)
        case .month:
            var comps = cal.dateComponents([.year, .month], from: date)
            comps.day = 1
            return f.string(from: cal.date(from: comps) ?? date)
        }
    }

    private func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        switch interval {
        case .day:
            let f = DateFormatter()
            f.dateFormat = "E"
            let s = f.string(from: date)
            return cal.isDateInToday(date) ? "Today" : String(s.prefix(3))
        case .week:
            let f = DateFormatter()
            f.dateFormat = "M/d"
            return f.string(from: date)
        case .month:
            let f = DateFormatter()
            f.dateFormat = "MMM"
            return f.string(from: date)
        }
    }

    private func dailyMax(_ key: String) -> Double {
        accepted.map { $0.intervals?[key] ?? 0 }.max() ?? 0
    }

    private func winnerId(for key: String) -> String? {
        let active = accepted.filter { ($0.intervals?[key] ?? 0) > 0 }
        return active.max(by: { ($0.intervals?[key] ?? 0) < ($1.intervals?[key] ?? 0) })?.user_id
    }

    var body: some View {
        let ds = dates
        guard !ds.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                header

                HStack(alignment: .top, spacing: 4) {
                    ForEach(ds, id: \.self) { date in
                        Button {
                            selectedDate = date
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            dayCell(for: date)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .stroke(
                                    LinearGradient(
                                        colors: gradientColors.map { $0.opacity(0.25) } + [Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .sheet(item: Binding(
                get: { selectedDate.map(IdentifiableDate.init) },
                set: { selectedDate = $0?.date }
            )) { wrapper in
                CompetitionDayDetailSheet(
                    competition: competition,
                    date: wrapper.date,
                    intervalKey: intervalKey(for: wrapper.date),
                    interval: interval
                )
                .presentationDetents([.medium, .large])
            }
        )
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom))
            Text("YOUR LAST 7 \(interval == .day ? "DAYS" : interval == .week ? "WEEKS" : "MONTHS")")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Text("Tap a ring for the matchup")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    // MARK: - Day Cell
    private func dayCell(for date: Date) -> some View {
        let key = intervalKey(for: date)
        let myMiles = me?.intervals?[key] ?? 0
        let leaderMiles = dailyMax(key)
        let goal = competition.options.goal
        let isToday = Calendar.current.isDateInToday(date)
        let isWinner = winnerId(for: key) == currentUserId && myMiles > 0

        return VStack(spacing: 6) {
            ZStack {
                // Background track
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 5)
                    .frame(width: 44, height: 44)

                // Progress arc
                Circle()
                    .trim(from: 0, to: progressFor(myMiles: myMiles, leaderMiles: leaderMiles, goal: goal))
                    .stroke(
                        LinearGradient(
                            colors: ringColors(myMiles: myMiles, leaderMiles: leaderMiles, goal: goal, isWinner: isWinner),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                    .shadow(color: (gradientColors.first ?? .white).opacity(myMiles > 0 ? 0.3 : 0), radius: 4)

                // Center indicator
                centerIcon(myMiles: myMiles, isWinner: isWinner, isToday: isToday)
            }

            // Day label
            Text(dayLabel(for: date))
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundColor(isToday ? MADTheme.Colors.madRed : .white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Miles number — the actual quantitative value
            Text(myMiles > 0 ? String(format: "%.1f", myMiles) : "—")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(myMiles > 0 ? .white : .white.opacity(0.25))
                .lineLimit(1)
        }
    }

    /// Fill ratio of the outer ring — mode-specific so each ring tells the
    /// right story.
    private func progressFor(myMiles: Double, leaderMiles: Double, goal: Double) -> CGFloat {
        switch competition.type {
        case .clash, .apex:
            // Your miles relative to the day's leader. Capped at 1.0.
            guard leaderMiles > 0 else { return 0 }
            return CGFloat(min(1.0, myMiles / leaderMiles))
        case .targets, .streaks:
            // Your miles vs the day's goal.
            guard goal > 0 else { return myMiles > 0 ? 1.0 : 0 }
            return CGFloat(min(1.0, myMiles / goal))
        case .race:
            // Use a 1-mile baseline so any contribution shows up. Capped at 1.0.
            return CGFloat(min(1.0, myMiles))
        }
    }

    /// Colors used for the gradient stroke on the progress arc.
    private func ringColors(myMiles: Double, leaderMiles: Double, goal: Double, isWinner: Bool) -> [Color] {
        if myMiles == 0 { return [Color.white.opacity(0.08)] }
        if isWinner { return [.yellow, .orange] }
        switch competition.type {
        case .streaks:
            return myMiles >= goal ? [.red, .pink] : [.orange, .yellow]
        case .targets:
            return myMiles >= goal ? [.green, gradientColors.last ?? .green] : gradientColors
        default:
            return gradientColors
        }
    }

    @ViewBuilder
    private func centerIcon(myMiles: Double, isWinner: Bool, isToday: Bool) -> some View {
        let goal = competition.options.goal
        switch competition.type {
        case .clash:
            if isWinner {
                Image(systemName: "crown.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
            } else if myMiles > 0 {
                Circle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 6, height: 6)
            } else if isToday {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.25))
            } else {
                Text("")
            }
        case .streaks:
            if myMiles >= goal {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
            } else if isToday {
                Image(systemName: "heart")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.35))
            } else {
                Image(systemName: "heart.slash.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.4))
            }
        case .targets:
            if myMiles >= goal {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
            } else if isToday {
                Image(systemName: "target")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
            } else if myMiles > 0 {
                Circle()
                    .fill(MADTheme.Colors.madRed.opacity(0.7))
                    .frame(width: 6, height: 6)
            } else {
                Text("")
            }
        case .apex:
            if isWinner {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
            } else if myMiles > 0 {
                Circle()
                    .fill((gradientColors.first ?? .white).opacity(0.7))
                    .frame(width: 6, height: 6)
            } else {
                Text("")
            }
        case .race:
            if myMiles > 0 {
                Image(systemName: "figure.run")
                    .font(.system(size: 14))
                    .foregroundColor(gradientColors.first ?? .white)
            } else {
                Text("")
            }
        }
    }
}
