import SwiftUI

// Shared pieces of the Run Plans v2 screens (mockup /m/mad-run-plans):
// palette, formatting, Flamey's avatar and note, chips, the tier badge, the
// week strip, the today card, proposal rows and buttons. No emoji anywhere:
// Flamey is a gradient circle with `flame.fill`.

// MARK: - Palette

enum RPV2Colors {
    static let red = MADTheme.Colors.madRed
    static let green = Color(red: 0.2, green: 0.702, blue: 0.302)
    static let orange = Color(red: 1.0, green: 0.584, blue: 0.0)
    static let gold = Color(red: 1.0, green: 0.702, blue: 0.278)
    static let blue = Color(red: 0.251, green: 0.6, blue: 0.949)
    static let card = Color(red: 0.075, green: 0.075, blue: 0.086)
    static let cardStroke = Color.white.opacity(0.095)
    static let mint = Color(red: 0.588, green: 0.882, blue: 0.647)
    static let flamey = LinearGradient(colors: [orange, red], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let aiBadge = LinearGradient(colors: [orange, red], startPoint: .leading, endPoint: .trailing)
    static let difficulty = LinearGradient(colors: [green, orange, red], startPoint: .leading, endPoint: .trailing)

    static func tint(_ kind: RunPlanV2DayKind) -> Color {
        switch kind {
        case .intervals: return red
        case .tempo: return orange
        case .easy: return green
        case .long: return blue
        case .race, .calibration: return gold
        case .walk: return .white.opacity(0.55)
        }
    }
}

// MARK: - Formatting (input is ALWAYS miles / seconds per mile)

enum RPV2Format {
    static var unit: String { DistanceUnits.current.abbreviation }

    /// "4" / "3.5" in the display unit, no unit.
    static func number(_ miles: Double) -> String {
        let v = miles.inDisplayUnit
        if abs(v - v.rounded()) < 0.05 { return String(format: "%.0f", v.rounded()) }
        return String(format: "%.1f", v)
    }

    /// "4 mi" / "6.4 km".
    static func distance(_ miles: Double) -> String { "\(number(miles)) \(unit)" }

    /// "1:40", "26:00", "1:52:10".
    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// Seconds per mile → "8:05/mi" (or /km).
    static func pace(_ secondsPerMile: Int) -> String {
        clock(Int(TimeInterval(secondsPerMile).pacePerDisplayUnit.rounded())) + DistanceUnits.current.paceSuffix
    }

    /// "11:30–12:15/mi".
    static func paceRange(_ fast: Int, _ slow: Int) -> String {
        let f = clock(Int(TimeInterval(fast).pacePerDisplayUnit.rounded()))
        let s = clock(Int(TimeInterval(slow).pacePerDisplayUnit.rounded()))
        return "\(f)–\(s)\(DistanceUnits.current.paceSuffix)"
    }

    /// Treadmill belt speed: "9.0 mph" / "14.5 km/h".
    static func speed(_ mph: Double) -> String {
        DistanceUnits.current == .miles
            ? String(format: "%.1f mph", mph)
            : String(format: "%.1f km/h", mph * 1.609344)
    }

    static func kindLabel(_ kind: RunPlanV2DayKind) -> String {
        switch kind {
        case .easy: return String(localized: "Easy")
        case .long: return String(localized: "Long")
        case .tempo: return String(localized: "Tempo")
        case .intervals: return String(localized: "Intervals")
        case .race: return String(localized: "Race")
        case .calibration: return String(localized: "Test run")
        case .walk: return String(localized: "Walk day")
        }
    }

    static func title(_ day: RunPlanV2Day) -> String {
        if let t = day.title, !t.isEmpty { return t }
        if day.isWalk { return kindLabel(.walk) }
        return "\(kindLabel(day.dayKind)) \(distance(day.miles))"
    }

    /// One line for a proposal's before/after: "Tempo 4 mi · 2 mi at 8:15/mi".
    static func changeLine(_ day: RunPlanV2Day?) -> String {
        guard let day else { return String(localized: "Nothing planned") }
        if day.isWalk { return kindLabel(.walk) }
        var line = title(day)
        if let sub = day.subtitle, !sub.isEmpty { line += " · \(sub)" }
        return line
    }

    private static let weekdayShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()

    private static let weekdayLetterFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d")
        return f
    }()

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("h:mm a")
        return f
    }()

    private static func date(_ key: String) -> Date { RunPlanV2Date.date(from: key) ?? Date() }

    static func weekdayLetter(_ key: String) -> String { weekdayLetterFormatter.string(from: date(key)) }
    static func dayOfMonth(_ key: String) -> String { dayFormatter.string(from: date(key)) }
    /// "Mon Nov 23".
    static func dayHeader(_ key: String) -> String { headerFormatter.string(from: date(key)) }
    static func weekdayShort(_ key: String) -> String { weekdayShortFormatter.string(from: date(key)) }

    /// "today 7:42 AM" / "Mon Nov 23".
    static func when(_ timestamp: String?) -> String {
        guard let d = RunPlanV2Date.parseTimestamp(timestamp) else { return "" }
        if Calendar.current.isDateInToday(d) {
            return String(localized: "today \(timeFormatter.string(from: d))")
        }
        return headerFormatter.string(from: d)
    }

    static func goalName(_ goal: RunPlanV2Goal) -> String {
        switch goal.goalType {
        case .justImprove: return String(localized: "Keep improving")
        case .burnCalories: return String(localized: "Burn more calories")
        case .distanceTime:
            let name = distanceName(goal.goalDistance, miles: goal.distance_mi)
            if let t = goal.target_s {
                return goal.goalDistance == .mile
                    ? String(localized: "\(clock(t)) mile")
                    : String(localized: "sub-\(clock(t)) \(name)")
            }
            return goal.goalDistance == .mile ? String(localized: "Faster mile") : name
        }
    }

    static func distanceName(_ d: RunPlanV2GoalDistance?, miles: Double?) -> String {
        switch d {
        case .mile: return String(localized: "Mile")
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .half: return String(localized: "Half")
        case .marathon: return String(localized: "Marathon")
        case .custom, .none: return miles.map(distance) ?? String(localized: "Custom")
        }
    }

    /// "Faster mile + sub-20:00 5K".
    static func goalsLine(_ goals: [RunPlanV2Goal]) -> String {
        let names = goals.map(goalName)
        return names.isEmpty ? String(localized: "Your plan") : names.joined(separator: " + ")
    }

    static func difficultyLabel(_ d: RunPlanV2Difficulty) -> String {
        switch d {
        case .easy: return String(localized: "Easy does it")
        case .steady: return String(localized: "Steady")
        case .push: return String(localized: "Push")
        case .allIn: return String(localized: "All in")
        }
    }

    static func phaseLabel(_ plan: RunPlanV2Plan) -> String {
        switch plan.phaseKind {
        case .base: return String(localized: "Base")
        case .build: return String(localized: "Build")
        case .peak: return String(localized: "Peak")
        case .taper: return String(localized: "Taper")
        case .race: return String(localized: "Race week")
        case .cutback: return String(localized: "Easier week")
        case .returning: return String(localized: "Coming back")
        case .rolling, .none:
            if plan.walkMode == .flexible { return String(localized: "Flexible walk days") }
            return String(localized: "Keep improving")
        }
    }
}

// MARK: - Flamey

/// Flamey as an avatar: a gradient circle with a flame (no emoji, no art).
struct FlameyAvatar: View {
    var size: CGFloat = 26

    var body: some View {
        Circle()
            .fill(RPV2Colors.flamey)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "flame.fill")
                    .font(.system(size: size * 0.52, weight: .bold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// Flamey's note for a day: avatar + text + where it came from.
struct FlameyNote: View {
    let text: String
    var tag: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            FlameyAvatar(size: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .madFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                if let tag {
                    Text(tag)
                        .madFont(size: 11, weight: .bold, design: .rounded)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    static func tag(for source: String?) -> String? {
        switch source {
        case "apple": return String(localized: "Written with Apple Intelligence")
        case "anthropic": return String(localized: "Written by the AI Coach")
        case "overseer", "user_claude": return String(localized: "Written with Claude")
        case "template": return String(localized: "Standard note for this kind of run")
        default: return nil
        }
    }
}

// MARK: - Small pieces

struct RPV2Chip: View {
    let icon: String
    let label: String
    var color: Color = .white.opacity(0.75)

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .madFont(size: 11, weight: .bold, maxScale: 1.15)
                .accessibilityHidden(true)
            Text(label)
                .madFont(size: 12, weight: .heavy, design: .rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

/// "AI Coach" (gradient) or "Run Plan" (plain).
struct RPV2TierBadge: View {
    let ai: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: ai ? "sparkles" : "calendar")
                .madFont(size: 10, weight: .bold, maxScale: 1.15)
                .accessibilityHidden(true)
            Text(ai ? String(localized: "AI Coach") : String(localized: "Run Plan"))
                .madFont(size: 11, weight: .black, design: .rounded)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(ai ? .white : .white.opacity(0.8))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            if ai { Capsule().fill(RPV2Colors.aiBadge) } else { Capsule().fill(Color.white.opacity(0.1)) }
        }
    }
}

struct RPV2KindPill: View {
    let kind: RunPlanV2DayKind

    var body: some View {
        Text(RPV2Format.kindLabel(kind).uppercased())
            .madFont(size: 10, weight: .black, design: .rounded)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(RPV2Colors.tint(kind))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(RPV2Colors.tint(kind).opacity(0.13)))
    }
}

/// Caps label used above sections ("TODAY · MON NOV 23").
struct RPV2Eyebrow: View {
    let text: String
    var color: Color = .white.opacity(0.5)

    var body: some View {
        Text(text.uppercased())
            .madFont(size: 11, weight: .black, design: .rounded)
            .tracking(1)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

/// The card every screen here sits on (mockup CARD + hairline).
struct RPV2Card<Content: View>: View {
    var stroke: Color = RPV2Colors.cardStroke
    var radius: CGFloat = 20
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(RPV2Colors.card)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(stroke, lineWidth: 1))
            )
    }
}

/// Full-width capsule button. Its label shrinks, never truncates.
struct RPV2Button: View {
    let title: String
    var icon: String? = nil
    var fill: Color = RPV2Colors.red
    var text: Color = .white
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: { MADHaptics.tap(); action() }) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().tint(text)
                } else if let icon {
                    Image(systemName: icon)
                        .madFont(size: 14, weight: .black, maxScale: 1.15)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .madFont(size: 16, weight: .black, design: .rounded)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

struct RPV2SecondaryButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: { MADHaptics.tap(); action() }) {
            Group {
                if isBusy { ProgressView().tint(.white) } else {
                    Text(title)
                        .madFont(size: 14, weight: .black, design: .rounded)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

/// A checkmark dot (selection).
struct RPV2CheckDot: View {
    let on: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(on ? RPV2Colors.orange : .clear)
                .overlay(Circle().strokeBorder(on ? .clear : Color.white.opacity(0.25), lineWidth: 1.5))
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

// MARK: - Week strip

struct RPV2WeekStrip: View {
    let days: [RunPlanV2Day]
    var today: String = RunPlanV2Date.todayKey()
    /// Dates with a pending proposal (gold dot).
    var flagged: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(days) { day in
                    cell(day)
                }
            }
            legend
        }
    }

    private func cell(_ day: RunPlanV2Day) -> some View {
        let key = day.dateKey
        let isToday = key == today
        let done = day.dayStatus.isComplete
        let tint = RPV2Colors.tint(day.dayKind)
        return VStack(spacing: 3) {
            Text(RPV2Format.weekdayLetter(key))
                .madFont(size: 9, weight: .black, design: .rounded, maxScale: 1.3)
                .foregroundStyle(.white.opacity(0.5))
            Text(RPV2Format.dayOfMonth(key))
                .madFont(size: 12, weight: .black, design: .rounded, maxScale: 1.3)
                .foregroundStyle(.white)
            ZStack {
                if done {
                    Circle().fill(RPV2Colors.green)
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundStyle(.black)
                } else if day.isWalk {
                    Circle().strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    Image(systemName: "figure.walk").font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                } else {
                    Circle().strokeBorder(tint, lineWidth: 1.5)
                    Text(RPV2Format.number(day.miles))
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(tint)
                        .padding(2)
                }
            }
            .frame(width: 22, height: 22)
            Circle()
                .fill(flagged.contains(key) ? RPV2Colors.gold : .clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isToday ? RPV2Colors.orange.opacity(0.14) : Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isToday ? RPV2Colors.orange : .clear, lineWidth: 1.5))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility(day, isToday: isToday, done: done, flagged: flagged.contains(key)))
    }

    private func accessibility(_ day: RunPlanV2Day, isToday: Bool, done: Bool, flagged: Bool) -> String {
        var parts = [RPV2Format.dayHeader(day.dateKey), RPV2Format.title(day)]
        if isToday { parts.insert(String(localized: "Today"), at: 0) }
        if done { parts.append(String(localized: "done")) }
        if flagged { parts.append(String(localized: "suggested change")) }
        return parts.joined(separator: ", ")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            Label(String(localized: "walk day"), systemImage: "figure.walk")
            Text(DistanceUnits.current == .miles ? String(localized: "numbers = miles") : String(localized: "numbers = km"))
            if !flagged.isEmpty {
                HStack(spacing: 4) {
                    Circle().fill(RPV2Colors.gold).frame(width: 5, height: 5)
                    Text(String(localized: "suggested change"))
                }
            }
        }
        .madFont(size: 11, weight: .bold, design: .rounded)
        .foregroundStyle(.white.opacity(0.5))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityHidden(true)
    }
}

// MARK: - Today card

/// Today's run: title, pace/speed line, shoe + treadmill chips, Flamey's note.
struct RPV2TodayCard: View {
    let day: RunPlanV2Day
    /// Most runs were indoors: show the belt speed chip.
    var treadmill: Bool = false
    var compactTitle = false

    var body: some View {
        RPV2Card(radius: 24, padding: 16) {
            HStack(alignment: .center, spacing: 8) {
                RPV2Eyebrow(text: String(localized: "Today · \(RPV2Format.dayHeader(day.dateKey))"))
                Spacer(minLength: 4)
                RPV2KindPill(kind: day.dayKind)
            }
            Text(RPV2Format.title(day))
                .madFont(size: compactTitle ? 28 : 34, weight: .black, design: .rounded, maxScale: 1.4)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.top, 4)
            ForEach(Array(detailLines.enumerated()), id: \.offset) { i, line in
                Text(line)
                    .madFont(size: 13, weight: .heavy, design: .rounded)
                    .foregroundStyle(.white.opacity(i == 0 ? 0.6 : 0.45))
                    .madBodyLines(2)
                    .padding(.top, i == 0 ? 6 : 0)
            }
            chips
                .padding(.top, 12)
            if let note = day.note, !note.isEmpty {
                FlameyNote(text: note, tag: FlameyNote.tag(for: day.note_source))
                    .padding(.top, 12)
            }
        }
    }

    private var detailLines: [String] {
        var lines: [String] = []
        if let sub = day.subtitle, !sub.isEmpty {
            lines.append(sub)
        } else if let w = day.workSegments.first, let lo = w.pace_low_s, let hi = w.pace_high_s {
            lines.append(RPV2Format.paceRange(lo, hi))
        } else if let seg = day.segments.first(where: { $0.hasPaceBand }), let lo = seg.pace_low_s, let hi = seg.pace_high_s {
            lines.append(RPV2Format.paceRange(lo, hi))
        }
        if day.isWalk {
            lines.append(String(localized: "Walk days still keep your streak: 1 mile or 10k steps."))
        } else if day.dayKind == .intervals || day.dayKind == .tempo, day.miles > 0 {
            lines.append(String(localized: "\(RPV2Format.distance(day.miles)) total with warm-up and cool-down"))
        }
        return lines
    }

    @ViewBuilder
    private var chips: some View {
        let shoe = day.shoe?.name
        let mph = day.workSegments.first?.speed_mph ?? day.segments.first(where: { $0.speed_mph != nil })?.speed_mph
        if shoe != nil || (treadmill && !day.isWalk) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chipViews(shoe: shoe, mph: mph) }
                VStack(alignment: .leading, spacing: 6) { chipViews(shoe: shoe, mph: mph) }
            }
        }
    }

    @ViewBuilder
    private func chipViews(shoe: String?, mph: Double?) -> some View {
        if let shoe {
            RPV2Chip(icon: ShoeSymbol.filled, label: shoe, color: RPV2Colors.orange)
        }
        if treadmill, !day.isWalk {
            RPV2Chip(icon: "figure.run.treadmill",
                     label: mph.map { String(localized: "Treadmill · \(RPV2Format.speed($0))") } ?? String(localized: "Treadmill"),
                     color: RPV2Colors.green)
        }
    }
}

// MARK: - Proposal pieces

/// One changed day: date, the old version struck through, the new one.
struct RPV2ChangeRow: View {
    let change: RunPlanV2ProposalChange

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            RPV2Eyebrow(text: change.local_date.map(RPV2Format.dayHeader) ?? "")
            Text(RPV2Format.changeLine(change.before))
                .madFont(size: 13, design: .rounded)
                .strikethrough()
                .foregroundStyle(.white.opacity(0.5))
                .madBodyLines(2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.down")
                    .madFont(size: 12, weight: .bold, maxScale: 1.15)
                    .foregroundStyle(RPV2Colors.gold)
                    .accessibilityHidden(true)
                Text(RPV2Format.changeLine(change.after))
                    .madFont(size: 14, weight: .black, design: .rounded)
                    .foregroundStyle(.white)
                    .madBodyLines(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}

/// Gold banner: "1 suggested change · tap to decide".
struct RPV2ProposalBanner: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(RPV2Colors.gold).frame(width: 8, height: 8)
            Text(count == 1
                 ? String(localized: "1 suggested change · tap to decide")
                 : String(localized: "\(count) suggested changes · tap to decide"))
                .madFont(size: 13, weight: .heavy, design: .rounded)
                .foregroundStyle(.white)
                .madBodyLines(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .madFont(size: 13, weight: .bold, maxScale: 1.15)
                .foregroundStyle(.white.opacity(0.4))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(RPV2Colors.gold.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(RPV2Colors.gold.opacity(0.4), lineWidth: 1.5))
        )
    }
}

/// A notice line (green / neutral / orange), icon + text.
struct RPV2Notice: View {
    let icon: String
    let text: String
    var tint: Color = .white.opacity(0.5)
    var fill: Color = Color.white.opacity(0.04)

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .madFont(size: 13, weight: .semibold, maxScale: 1.15)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(text)
                .madFont(size: 12, weight: .medium, design: .rounded)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(tint)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
    }
}

/// The step header in setup ("STEP 1 OF 3" / title / subtitle).
struct RPV2StepHeader: View {
    let step: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            RPV2Eyebrow(text: step, color: .white.opacity(0.5))
            Text(title)
                .madFont(size: 24, weight: .black, design: .rounded, maxScale: 1.5)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .madFont(size: 13, design: .rounded)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
