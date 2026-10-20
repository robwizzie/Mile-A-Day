import SwiftUI

// Shared pieces of the Run Plans screens: palette, formatting, the week
// strip, the today card, feeling chips, Flamey's note and the doctor line.

// MARK: - Palette

enum RunPlanColors {
    static let red = MADTheme.Colors.madRed
    static let blue = Color(red: 0.25, green: 0.6, blue: 0.95)
    static let green = Color(red: 0.2, green: 0.7, blue: 0.3)
    static let orange = Color(red: 1.0, green: 0.584, blue: 0.0)
    static let gold = Color(red: 1.0, green: 0.7, blue: 0.28)
    static let card = Color(red: 0.075, green: 0.075, blue: 0.086)
    static let cardStroke = Color.white.opacity(0.095)
    static let plum = LinearGradient(colors: [Color(red: 0.16, green: 0.06, blue: 0.11), Color(red: 0.05, green: 0.03, blue: 0.06)],
                                     startPoint: .top, endPoint: .bottom)
    static let plusGradient = LinearGradient(colors: [Color(red: 1.0, green: 0.82, blue: 0.45), orange, red],
                                             startPoint: .leading, endPoint: .trailing)
    static let effortGradient = LinearGradient(colors: [green, orange, red], startPoint: .leading, endPoint: .trailing)

    static func tint(_ kind: RunPlanDayKind) -> Color {
        switch kind {
        case .streak: return .white.opacity(0.55)
        case .easy: return green
        case .tempo: return orange
        case .intervals: return red
        case .long: return blue
        case .raceTest: return gold
        }
    }
}

// MARK: - Formatting

/// Distances arrive in MILES and convert only here (`DistanceUnits.current`).
enum RunPlanFormat {
    static func kindLabel(_ kind: RunPlanDayKind) -> String {
        switch kind {
        case .streak: return "Streak mile"
        case .easy: return "Easy"
        case .tempo: return "Tempo"
        case .intervals: return "Intervals"
        case .long: return "Long"
        case .raceTest: return "Time trial"
        }
    }

    static func title(_ day: RunPlanDay) -> String {
        if let t = day.title, !t.isEmpty { return t }
        return kindLabel(day.dayKind)
    }

    /// "2" / "1.5" in the display unit, no unit.
    static func distanceNumber(_ miles: Double) -> String {
        let v = miles.inDisplayUnit
        if abs(v - v.rounded()) < 0.05 { return String(format: "%.0f", v.rounded()) }
        return String(format: "%.1f", v)
    }

    /// "2 mi" / "3.2 km".
    static func distance(_ miles: Double) -> String {
        "\(distanceNumber(miles)) \(DistanceUnits.current.abbreviation)"
    }

    static var unit: String { DistanceUnits.current.abbreviation }

    /// "1:40", "26:00", "1:52:10".
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// Seconds per mile → "8:05/mi" (or /km).
    static func pace(_ secondsPerMile: Double) -> String {
        "\(clock(secondsPerMile.pacePerDisplayUnit))\(DistanceUnits.current.paceSuffix)"
    }

    /// A rep's length: "400m" under a mile, else the display distance.
    static func repLength(_ miles: Double) -> String {
        if miles < 0.95 {
            let meters = (miles * 1609.344 / 50).rounded() * 50
            return "\(Int(meters))m"
        }
        return distance(miles)
    }

    /// The pace line beside today's distance: "1:40 / 400m", "8:05/mi", "any pace".
    static func target(_ day: RunPlanDay) -> String {
        if day.dayKind == .streak { return "any pace" }
        if let work = day.workSegments.first, let p = work.target_pace_s {
            if let mi = work.distance_mi, mi < 0.95 { return "\(clock(p * mi)) / \(repLength(mi))" }
            return pace(p)
        }
        if let p = day.target_pace_s { return pace(p) }
        return "easy effort"
    }

    /// "1:40 each · 2 mi total" (intervals) or "8:05/mi · 3 mi".
    static func subtitle(_ day: RunPlanDay) -> String {
        let total = "\(distance(day.miles)) total"
        if let work = day.workSegments.first, let p = work.target_pace_s, let mi = work.distance_mi, mi < 0.95 {
            return "\(clock(p * mi)) each · \(total)"
        }
        if day.dayKind == .streak { return "\(distance(day.miles)) · any pace" }
        if let p = day.target_pace_s { return "\(pace(p)) · \(distance(day.miles))" }
        return distance(day.miles)
    }

    private static func date(_ key: String) -> Date { RunPlanDate.date(from: key) ?? Date() }

    /// "Mon".
    static func weekdayShort(_ key: String) -> String {
        date(key).formatted(.dateTime.weekday(.abbreviated))
    }

    /// "M".
    static func weekdayLetter(_ key: String) -> String {
        date(key).formatted(.dateTime.weekday(.narrow))
    }

    /// "20".
    static func dayOfMonth(_ key: String) -> String {
        date(key).formatted(.dateTime.day())
    }

    /// "Tue Oct 20".
    static func dayHeader(_ key: String) -> String {
        date(key).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Today" or "Thu Oct 22".
    static func relativeDay(_ key: String) -> String {
        key == RunPlanDate.todayKey() ? "Today" : dayHeader(key)
    }

    static func goalName(_ type: RunPlanGoalType) -> String {
        switch type {
        case .fasterMile: return "Faster mile"
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .half: return "Half marathon"
        case .marathon: return "Marathon"
        case .firstFiveK: return "First 5K"
        case .moreMiles: return "Run more miles"
        }
    }

    static func goalEmoji(_ type: RunPlanGoalType) -> String {
        switch type {
        case .fasterMile: return "⚡"
        case .fiveK: return "🏁"
        case .tenK: return "🎽"
        case .half: return "🏅"
        case .marathon: return "🏆"
        case .firstFiveK: return "🌱"
        case .moreMiles: return "📈"
        }
    }

    /// "Faster mile + 5K under 20:00".
    static func goalsLine(_ goals: [RunPlanGoal]) -> String {
        let names = goals.compactMap { goal -> String? in
            guard let type = goal.goalType else { return nil }
            if type != .fasterMile, let t = goal.target_seconds {
                let short = type == .half ? "Half" : goalName(type)
                return "\(short) under \(clock(t))"
            }
            return goalName(type)
        }
        return names.isEmpty ? "Your plan" : names.joined(separator: " + ")
    }

    /// 1-based plan week: the server's, else from `created_at`.
    static func week(_ plan: RunPlan) -> Int {
        if let w = plan.week, w > 0 { return w }
        guard let created = BuddyDate.parse(plan.created_at) else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: created),
                                                   to: Calendar.current.startOfDay(for: Date())).day ?? 0
        return max(1, days / 7 + 1)
    }

    static func effortLabel(_ effort: Int) -> String {
        switch effort {
        case 1: return "Easy does it"
        case 2: return "Steady"
        case 3: return "Push"
        default: return "All in"
        }
    }

    /// Hard days a week the effort sets (the engine's table).
    static func hardDays(forEffort effort: Int) -> Int {
        switch effort {
        case 1: return 1
        case 2: return 2
        default: return 3
        }
    }

    static func growthCap(forEffort effort: Int) -> Int {
        switch effort {
        case 1: return 5
        case 2: return 7
        case 3: return 8
        default: return 10
        }
    }

    static func summary(_ s: RunPlanDaySummary?) -> String {
        guard let s else { return "—" }
        let kind = s.kind.flatMap(RunPlanDayKind.init(rawValue:))
        if let t = s.title, !t.isEmpty { return t }
        let label = kind.map(kindLabel) ?? "Run"
        if let mi = s.distance_mi { return "\(label) \(distance(mi))" }
        return label
    }
}

// MARK: - Small pieces

struct RunPlanPlusChip: View {
    var body: some View {
        Text("PLUS")
            .madFont(size: 9, weight: .black, design: .rounded, maxScale: 1.2)
            .tracking(0.8)
            .foregroundColor(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(RunPlanColors.gold))
            .fixedSize()
    }
}

/// Flamey's face where the mockup draws 🔥: the user's own dressed Flamey.
struct RunPlanCoachAvatar: View {
    var size: CGFloat = 24

    var body: some View {
        FlameBuddyView(health: .healthy, size: size, still: true, showsMoodBubble: false,
                       look: FlameyFacts.look(detail: .compact), wardrobeReach: 0.8)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The Fun dashboard's card: near-black, hairline border.
    func runPlanCard(radius: CGFloat = 22, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(RunPlanColors.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(RunPlanColors.cardStroke, lineWidth: 1))
    }
}

/// Flamey's note on a card (avatar + text on a faint panel).
struct RunPlanFlameyNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RunPlanCoachAvatar(size: 22)
            Text(text)
                .madFont(size: 13, weight: .medium, design: .rounded)
                .foregroundColor(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flamey: \(text)")
    }
}

/// Shown whenever pain is flagged or the runner tapped Sore (App Review 1.4.1).
struct RunPlanDoctorLine: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .madFont(size: 14, weight: .bold, maxScale: 1.3)
                .accessibilityHidden(true)
            Text("If the pain is sharp, makes you limp, or lasts more than a few days, stop running and see a doctor. Flamey isn't a medical professional.")
                .madFont(size: 12.5, weight: .semibold, design: .rounded)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.55))
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(RunPlanColors.orange.opacity(0.10)))
        .accessibilityElement(children: .combine)
    }
}

/// Tired / Sore / Normal / Great.
struct RunPlanFeelingChips: View {
    var selected: RunPlanFeeling? = nil
    var compact = false
    var disabled = false
    let onPick: (RunPlanFeeling) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RunPlanFeeling.allCases) { feeling in
                Button {
                    MADHaptics.tap()
                    onPick(feeling)
                } label: {
                    chip(feeling)
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityLabel("I feel \(feeling.label.lowercased())")
                .accessibilityAddTraits(selected == feeling ? .isSelected : [])
            }
        }
    }

    private func chip(_ feeling: RunPlanFeeling) -> some View {
        let on = selected == feeling
        return VStack(spacing: compact ? 2 : 4) {
            Text(feeling.emoji)
                .font(.system(size: compact ? 16 : 20))
                .accessibilityHidden(true)
            Text(feeling.label)
                .madFont(size: compact ? 10 : 11, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white.opacity(on ? 0.95 : 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 44 : 52)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(on ? RunPlanColors.orange.opacity(0.18) : Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(on ? RunPlanColors.orange : Color.clear, lineWidth: 1.5))
        .opacity(disabled ? 0.5 : 1)
        .contentShape(Rectangle())
    }
}

// MARK: - Week strip

struct RunPlanWeekStrip: View {
    let days: [RunPlanDay]
    var todayKey: String = RunPlanDate.todayKey()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(days) { day in
                cell(day)
            }
        }
        // Seven columns at 320pt: ~39pt each, so the type stops growing here.
        .madTypeCap(.madFixedChromeCap)
        .accessibilityElement(children: .contain)
    }

    private func cell(_ day: RunPlanDay) -> some View {
        let isToday = day.local_date == todayKey
        let tint = RunPlanColors.tint(day.dayKind)
        return VStack(spacing: 3) {
            Text(RunPlanFormat.weekdayLetter(day.local_date))
                .madFont(size: 9, weight: .black, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white.opacity(0.45))
            Text(RunPlanFormat.dayOfMonth(day.local_date))
                .madFont(size: 12, weight: .black, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
            ZStack {
                if day.isDone {
                    Circle().fill(RunPlanColors.green)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.black)
                } else {
                    Circle().strokeBorder(tint, lineWidth: 1.5)
                    Text(RunPlanFormat.distanceNumber(day.miles))
                        .madFont(size: 10, weight: .black, design: .rounded, maxScale: 1.2)
                        .foregroundColor(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 2)
                }
            }
            .frame(width: 22, height: 22)
            Circle()
                .fill(day.wasMoved ? RunPlanColors.gold : Color.clear)
                .frame(width: 4, height: 4)
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isToday ? RunPlanColors.orange.opacity(0.14) : Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isToday ? RunPlanColors.orange : Color.clear, lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(day, isToday: isToday))
    }

    private func accessibilityText(_ day: RunPlanDay, isToday: Bool) -> String {
        var parts = [isToday ? "Today" : RunPlanFormat.dayHeader(day.local_date),
                     RunPlanFormat.title(day), RunPlanFormat.distance(day.miles)]
        if day.isDone { parts.append("done") }
        if day.wasMoved { parts.append("changed") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Today card

struct RunPlanTodayCard: View {
    let day: RunPlanDay
    /// Shown when the day has no note of its own.
    var fallbackNote: String? = nil

    var body: some View {
        let kind = day.dayKind
        let tint = RunPlanColors.tint(kind)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("TODAY · \(RunPlanFormat.dayHeader(day.local_date).uppercased())")
                    .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(RunPlanFormat.kindLabel(kind).uppercased())
                    .madFont(size: 10, weight: .black, design: .rounded, maxScale: 1.3)
                    .foregroundColor(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tint.opacity(0.14)))
                    .lineLimit(1)
                    .fixedSize()
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    distance
                    Spacer(minLength: 8)
                    target(alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 4) {
                    distance
                    target(alignment: .leading)
                }
            }
            if let title = day.title, !title.isEmpty, kind != .streak {
                Text(title)
                    .madFont(size: 15, weight: .heavy, design: .rounded)
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if day.isDone {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .madFont(size: 13, weight: .heavy, design: .rounded)
                    .foregroundColor(RunPlanColors.green)
            }
            if let note = day.note ?? fallbackNote, !note.isEmpty {
                RunPlanFlameyNote(text: note)
                    .padding(.top, 4)
            }
        }
        .runPlanCard(radius: 24)
    }

    private var distance: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(RunPlanFormat.distanceNumber(day.miles))
                .madFont(size: 44, weight: .black, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
                .lineLimit(1)
            Text(RunPlanFormat.unit)
                .madFont(size: 16, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white.opacity(0.6))
        }
        .fixedSize()
    }

    private func target(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(RunPlanFormat.target(day))
                .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(1)
            Text("TARGET PACE")
                .madFont(size: 10, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white.opacity(0.4))
        }
        .fixedSize()
    }
}
