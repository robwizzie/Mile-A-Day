import SwiftUI

// MARK: - Month share cards
//
// The monthly recap used to share a 4:5 card rendered off-screen straight into
// the system sheet — no preview, no Instagram, and "mi" printed at somebody
// who set the app to kilometres. A good month is the single most postable
// thing the app produces (it is the screenshot people already take of their
// Apple Fitness calendar), so it goes through the Share Studio like every
// other share, in three designs:
//
//   * MONTH IN MILES — the month's calendar, every goal day lit. The calendar
//     IS the brag: thirty green squares need no caption.
//   * THE RING — the month as a ring of days around the day count; the
//     "28 of 30" read at a glance, built for the person whose number is days.
//   * FLAMEY — Fun only, over the month's daily miles as a bar strip.
//
// A PERFECT month (every day banked) turns gold everywhere — the legendary
// medal's own metal (`MedalPalette`), so "perfect" looks like the app's
// rarest thing rather than a colour picked for the occasion. That is the
// moment people post, and it should look like a trophy.
//
// Same card rules as ShareTemplateCards (ios.md, the sharing bullet): explicit
// sizes, nothing asynchronous, no TimelineView/.blur(), ONE `ShareLockup`
// bottom-left, distances through `DistanceUnits`.

/// The month, as the cards need it. A thin view over `MonthlyRecapStats` so
/// the cards never re-derive a day's state differently from each other.
struct ShareMonth {
    let stats: MonthlyRecapStats

    enum DayState { case met, partial, none }

    var isPerfect: Bool { stats.isPerfect }

    /// Legendary gold, from the medal shelf's own palette.
    static let gold = MedalPalette.forRarity(.legendary, locked: false)

    var accent: Color { isPerfect ? ShareMonth.gold.faceHi : MADTheme.Colors.success }

    var monthTitle: String { stats.monthName.uppercased() }

    var yearText: String? {
        guard let start = stats.monthStart else { return nil }
        return String(Calendar.current.component(.year, from: start))
    }

    /// One decimal, floored, no unit — a month total at two decimals reads as
    /// false precision ("87.43").
    static func oneDecimal(_ miles: Double) -> String {
        let v = (miles.inDisplayUnit * 10.0 + 1e-6).rounded(.down) / 10.0
        return v >= 1000 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    var totalText: String { ShareMonth.oneDecimal(stats.totalMiles) }

    var daysText: String { "\(stats.activeDays)/\(stats.daysInMonth)" }

    /// Per-day state, index 0 = the 1st. Empty when the caller had no per-day
    /// figures (the grid is then simply not drawn).
    var days: [DayState] {
        guard let miles = stats.dayMiles else { return [] }
        let goal = max(stats.goalMiles ?? 1, 0.01)
        return miles.map { m in
            if ProgressCalculator.isGoalCompleted(current: m, goal: goal) { return .met }
            return m > 0 ? .partial : .none
        }
    }

    /// Blank cells before the 1st, in the locale's week.
    var leadingBlanks: Int {
        guard let start = stats.monthStart else { return 0 }
        let cal = Calendar.current
        return (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
    }

    /// "S M T W T F S", starting on the locale's first weekday.
    static var weekdayLetters: [String] {
        let cal = Calendar.current
        let symbols = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The line under the big number. Celebratory at every level a person
    /// would choose to post — nobody shares a card that grades them.
    var headline: String {
        let s = stats
        if s.isPerfect { return "Every single day." }
        if s.daysInMonth - s.activeDays <= 2 { return "\(s.activeDays) of \(s.daysInMonth) days. So close." }
        return "\(s.activeDays) of \(s.daysInMonth) days."
    }

    func rail(limit: Int, includeDays: Bool) -> [MADStoryStat] {
        var out: [MADStoryStat] = []
        if includeDays {
            out.append(MADStoryStat(value: daysText, label: "GOAL DAYS", tint: isPerfect ? ShareMonth.gold.faceHi : .white))
        }
        if stats.bestDayMiles > 0 {
            out.append(MADStoryStat(value: stats.bestDayMiles.distanceText, label: "BEST DAY"))
        }
        if stats.streakAtMonthEnd > 0 {
            out.append(MADStoryStat(value: "\(stats.streakAtMonthEnd)", label: "STREAK", tint: MADTheme.Colors.warning))
        } else if stats.workoutCount > 0 {
            out.append(MADStoryStat(value: "\(stats.workoutCount)", label: stats.workoutCount == 1 ? "WORKOUT" : "WORKOUTS"))
        }
        return Array(out.prefix(limit))
    }
}

// MARK: Shared parts

/// "👑 PERFECT MONTH" — the kicker a perfect month wears in place of the year.
struct SharePerfectMonthBadge: View {
    var size: CGFloat = 12

    var body: some View {
        let gold = ShareMonth.gold
        HStack(spacing: size * 0.5) {
            Image(systemName: "crown.fill")
                .font(.system(size: size, weight: .black))
            Text("PERFECT MONTH")
                .font(.system(size: size, weight: .black, design: .rounded))
                .tracking(size * 0.2)
        }
        .foregroundColor(Color(red: 0.24, green: 0.14, blue: 0.0))
        .padding(.horizontal, size * 1.0)
        .padding(.vertical, size * 0.55)
        .background(
            Capsule().fill(LinearGradient(colors: [gold.rimHi, gold.faceHi, gold.rimLo],
                                          startPoint: .top, endPoint: .bottom))
        )
        .lineLimit(1)
        .fixedSize()
    }
}

/// The month as a calendar: one rounded square per day, lit when the goal was
/// banked, warm when there were miles short of it, faint when there were none.
struct ShareMonthGrid: View {
    let month: ShareMonth
    var cell: CGFloat = 36
    var spacing: CGFloat = 5
    var showsNumbers: Bool = true
    var showsWeekdays: Bool = true

    var body: some View {
        let days = month.days
        let blanks = month.leadingBlanks
        let total = blanks + days.count
        let rows = Int((Double(total) / 7).rounded(.up))
        VStack(alignment: .leading, spacing: spacing) {
            if showsWeekdays {
                HStack(spacing: spacing) {
                    ForEach(Array(ShareMonth.weekdayLetters.enumerated()), id: \.offset) { _, letter in
                        Text(letter)
                            .font(.system(size: max(8, cell * 0.27), weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.38))
                            .frame(width: cell)
                    }
                }
                .padding(.bottom, 2)
            }
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { col in
                        let index = row * 7 + col - blanks
                        if index >= 0 && index < days.count {
                            dayCell(days[index], number: index + 1)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func dayCell(_ state: ShareMonth.DayState, number: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: cell * 0.26, style: .continuous)
        let gold = ShareMonth.gold
        ZStack {
            switch state {
            case .met:
                if month.isPerfect {
                    shape.fill(LinearGradient(colors: [gold.rimHi, gold.faceHi, gold.faceLo],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    shape.fill(MADTheme.Colors.success)
                }
            case .partial:
                shape.fill(MADTheme.Colors.warning.opacity(0.24))
                shape.strokeBorder(MADTheme.Colors.warning.opacity(0.6), lineWidth: 1.2)
            case .none:
                shape.fill(Color.white.opacity(0.06))
            }
            if showsNumbers {
                Text("\(number)")
                    .font(.system(size: cell * 0.32, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(numberColor(state))
            }
        }
        .frame(width: cell, height: cell)
    }

    private func numberColor(_ state: ShareMonth.DayState) -> Color {
        switch state {
        case .met: return month.isPerfect ? Color(red: 0.36, green: 0.21, blue: 0.0) : .white
        case .partial: return MADTheme.Colors.warning
        case .none: return .white.opacity(0.26)
        }
    }
}

/// The month's daily miles as one strip of bars — the shape of the month in a
/// line. Heights are relative to the best day; colour is the day's state.
struct ShareMonthBars: View {
    let month: ShareMonth
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        let miles = month.stats.dayMiles ?? []
        let states = month.days
        let peak = max(miles.max() ?? 1, 0.01)
        let n = max(miles.count, 1)
        let gap: CGFloat = n > 20 ? 2.5 : 4
        let bar = (width - gap * CGFloat(n - 1)) / CGFloat(n)
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(Array(miles.enumerated()), id: \.offset) { i, m in
                let h = m > 0 ? max(bar, height * CGFloat(m / peak)) : bar * 0.8
                RoundedRectangle(cornerRadius: bar / 2, style: .continuous)
                    .fill(color(states.indices.contains(i) ? states[i] : .none))
                    .frame(width: bar, height: h)
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
    }

    private func color(_ state: ShareMonth.DayState) -> Color {
        switch state {
        case .met: return month.accent
        case .partial: return MADTheme.Colors.warning.opacity(0.85)
        case .none: return .white.opacity(0.12)
        }
    }
}

/// Kicker row: the perfect badge, else "MY MONTH · 2026".
private struct ShareMonthKicker: View {
    let month: ShareMonth
    var size: CGFloat = 11.5

    var body: some View {
        if month.isPerfect {
            SharePerfectMonthBadge(size: size)
        } else {
            ShareCopy.kickerText(["MY MONTH", month.yearText].compactMap { $0 }.joined(separator: " · "),
                                 size: size)
        }
    }
}

/// The month name, as big as the canvas allows.
private struct ShareMonthTitle: View {
    let month: ShareMonth
    var size: CGFloat

    var body: some View {
        Text(month.monthTitle)
            .font(.system(size: size, weight: .black, design: .rounded))
            .tracking(-0.5)
            .foregroundStyle(
                month.isPerfect
                    ? AnyShapeStyle(LinearGradient(colors: [ShareMonth.gold.rimHi, ShareMonth.gold.faceHi, ShareMonth.gold.rimLo],
                                                   startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Color.white)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.4)
    }
}

// MARK: - Month in miles

/// The month's calendar as a story, or a compact badge as a sticker.
struct MonthShareCard: View {
    let content: MADStoryContent
    var format: MADStoryFormat = .story

    var body: some View {
        if let stats = content.month {
            let month = ShareMonth(stats: stats)
            if format == .story { story(month) } else { sticker(month) }
        }
    }

    private func story(_ month: ShareMonth) -> some View {
        ZStack {
            ShareGround(glow: month.isPerfect ? ShareMonth.gold.glow : MADTheme.Colors.madRed,
                        center: UnitPoint(x: 0.85, y: 0.04),
                        strength: month.isPerfect ? 0.42 : 0.38)
            VStack(alignment: .leading, spacing: 0) {
                ShareMonthKicker(month: month)
                ShareMonthTitle(month: month, size: 62)
                    .padding(.top, 12)
                ShareCopy.hero(month.totalText, size: 70)
                    .padding(.top, -4)
                Text(month.headline)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(month.isPerfect ? ShareMonth.gold.rimHi : .white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 2)
                Spacer(minLength: 0)
                if !month.days.isEmpty {
                    // A month that spans six weeks gets smaller cells, or the
                    // grid crowds the headline and the rail.
                    let sixRows = month.leadingBlanks + month.days.count > 35
                    ShareMonthGrid(month: month, cell: sixRows ? 31 : 36, spacing: sixRows ? 5 : 6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                Spacer(minLength: 0)
                ShareStatRail(stats: month.rail(limit: 3, includeDays: true))
                ShareLockup()
            }
            .padding(28)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    private func sticker(_ month: ShareMonth) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                ShareMonthKicker(month: month, size: 10)
                Spacer(minLength: 0)
            }
            ShareMonthTitle(month: month, size: 44)
                .padding(.top, 10)
            ShareCopy.hero(month.totalText, size: 54)
                .padding(.top, -4)
            Spacer(minLength: 0)
            ShareMonthBars(month: month, width: 276, height: 64)
            HStack(spacing: 0) {
                Text("\(month.stats.activeDays) of \(month.stats.daysInMonth) days")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(month.accent)
                Spacer(minLength: 8)
                if month.stats.streakAtMonthEnd > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").font(.system(size: 11, weight: .black))
                        Text("\(month.stats.streakAtMonthEnd) day streak")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                    }
                    .foregroundColor(MADTheme.Colors.warning)
                }
            }
            .lineLimit(1)
            .padding(.top, 10)
            ShareLockup(format: .sticker)
        }
        .padding(22)
        .frame(width: 320, height: 400)
        .background(
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                RadialGradient(colors: [(month.isPerfect ? ShareMonth.gold.glow : MADTheme.Colors.madRed).opacity(0.32), .clear],
                               center: UnitPoint(x: 0.9, y: 0.0), startRadius: 4, endRadius: 260)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(month.isPerfect ? ShareMonth.gold.faceHi.opacity(0.6) : Color.white.opacity(0.16),
                              lineWidth: 1.5)
        )
    }
}

// MARK: - The ring

/// The month as a ring of days — one dot per day, lit when banked — around
/// the day count. For the walker whose number is DAYS, not miles.
struct MonthRingShareCard: View {
    let content: MADStoryContent

    var body: some View {
        if let stats = content.month {
            let month = ShareMonth(stats: stats)
            ZStack {
                ShareGround(glow: month.isPerfect ? ShareMonth.gold.glow : MADTheme.Colors.success,
                            center: UnitPoint(x: 0.5, y: 0.42),
                            strength: month.isPerfect ? 0.40 : 0.26, radius: 300)
                VStack(spacing: 0) {
                    ShareMonthKicker(month: month)
                    ShareMonthTitle(month: month, size: 46)
                        .padding(.top, 12)
                    Spacer(minLength: 0)
                    ring(month)
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(month.totalText)
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                        Text(DistanceUnits.current.abbreviation.uppercased())
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .tracking(1.4)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    ShareStatRail(stats: month.rail(limit: 2, includeDays: false))
                        .padding(.top, 14)
                    ShareLockup()
                }
                .padding(28)
            }
            .frame(width: 360, height: 640)
            .clipped()
        }
    }

    private func ring(_ month: ShareMonth) -> some View {
        let states = month.days
        let n = max(states.count, month.stats.daysInMonth)
        let diameter: CGFloat = 262
        let radius = diameter / 2 - 10
        let dot: CGFloat = n > 30 ? 15 : 15.5
        return ZStack {
            ForEach(0..<n, id: \.self) { i in
                let angle = Angle.degrees(Double(i) / Double(n) * 360 - 90)
                let state: ShareMonth.DayState = states.indices.contains(i)
                    ? states[i]
                    : (i < month.stats.activeDays ? .met : .none)
                Circle()
                    .fill(fill(state, month: month))
                    .overlay(
                        Circle().strokeBorder(state == .partial ? MADTheme.Colors.warning.opacity(0.7) : .clear,
                                              lineWidth: 1.2)
                    )
                    .frame(width: dot, height: dot)
                    .offset(x: CGFloat(cos(angle.radians)) * radius,
                            y: CGFloat(sin(angle.radians)) * radius)
            }
            VStack(spacing: 2) {
                Text("\(month.stats.activeDays)")
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(month.isPerfect ? ShareMonth.gold.faceHi : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(month.isPerfect ? "FOR \(month.stats.daysInMonth)" : "OF \(month.stats.daysInMonth) DAYS")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(2.4)
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(width: diameter - 70)
        }
        .frame(width: diameter, height: diameter)
    }

    private func fill(_ state: ShareMonth.DayState, month: ShareMonth) -> AnyShapeStyle {
        let gold = ShareMonth.gold
        switch state {
        case .met:
            return month.isPerfect
                ? AnyShapeStyle(LinearGradient(colors: [gold.rimHi, gold.faceLo], startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(MADTheme.Colors.success)
        case .partial: return AnyShapeStyle(MADTheme.Colors.warning.opacity(0.25))
        case .none: return AnyShapeStyle(Color.white.opacity(0.1))
        }
    }
}

// MARK: - Flamey

/// Flamey presenting the month (Fun only — `ShareTemplate.available`).
struct FlameyMonthShareCard: View {
    let content: MADStoryContent

    var body: some View {
        if let stats = content.month {
            let month = ShareMonth(stats: stats)
            ZStack {
                ShareGround(glow: month.isPerfect ? ShareMonth.gold.glow : MADTheme.Colors.warning,
                            center: UnitPoint(x: 0.5, y: 0.3), strength: 0.42)
                VStack(spacing: 0) {
                    ShareMonthKicker(month: month)
                    ShareMonthTitle(month: month, size: 50)
                        .padding(.top, 10)
                    Spacer(minLength: 0)
                    // Party hat on a perfect month, shades on a good one —
                    // both moods that render as a still.
                    ShareFlamey(size: 170,
                                mood: month.isPerfect ? .party
                                    : (month.stats.activeDays * 2 >= month.stats.daysInMonth ? .done : nil),
                                streak: month.stats.streakAtMonthEnd, maxHeight: 214)
                    Text("\(month.totalText) \(DistanceUnits.current.abbreviation)")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 10)
                    Text(month.headline)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(month.isPerfect ? ShareMonth.gold.rimHi : .white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 6)
                    ShareMonthBars(month: month, width: 304, height: 56)
                        .padding(.top, 24)
                    Spacer(minLength: 0)
                    ShareLockup()
                }
                .padding(28)
            }
            .frame(width: 360, height: 640)
            .clipped()
        }
    }
}
