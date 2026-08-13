import SwiftUI

// MARK: - Active competition row

/// A live competition, led by what you should do about it today.
///
/// The old `CompetitionCard` opened with the competition's *name* and type,
/// which tells you which game you're in but not whether you need to move. This
/// row opens with `TodayFocus` — the same per-mode "what should I do right
/// now?" model the dashboard banner and the home-screen widget already use —
/// so the answer is the first thing you read.
struct ActiveCompetitionRow: View {
    let competition: Competition
    let action: () -> Void

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    private var focus: TodayFocus {
        TodayFocus.compute(for: competition, currentUserId: currentUserId)
    }

    private var gradientColors: [Color] {
        competition.type.gradient.map { Color(hex: $0) }
    }

    /// "2nd of 5". Nil when the standings don't include us yet (pre-start, or
    /// a payload that hasn't resolved scores).
    private var standingText: String? {
        let ranked = competition.users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        guard let uid = currentUserId,
              let index = ranked.firstIndex(where: { $0.user_id == uid }) else { return nil }
        return "\(Self.ordinal(index + 1)) of \(ranked.count)"
    }

    static func ordinal(_ rank: Int) -> String {
        switch rank {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(rank)th"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                topRow
                focusLine
                if let hint = competition.rivalryHint {
                    rivalryRow(hint)
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [gradientColors[0].opacity(0.10), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [gradientColors[0].opacity(0.35), Color.white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var topRow: some View {
        HStack(spacing: 12) {
            Image(systemName: competition.type.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(gradientColors[0].opacity(0.14))
                        .overlay(Circle().strokeBorder(gradientColors[0].opacity(0.45), lineWidth: 1))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(competition.competition_name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(competition.type.displayName)
                    if let standing = standingText {
                        Text("·")
                        Text(standing)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let timeLeft = CompeteFormat.timeLeft(for: competition) {
                Text(timeLeft)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    // Data-driven text in a fixed row: let the NAME truncate
                    // first, never this.
                    .fixedSize()
            }
        }
    }

    /// The pill sits above its detail rather than beside it: both are
    /// data-driven strings, and side by side they compete for one row and
    /// truncate each other.
    private var focusLine: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: focus.pillIcon)
                    .font(.system(size: 11, weight: .bold))

                Text(focus.pill)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(0.8)

                Spacer(minLength: 0)
            }
            .foregroundColor(focus.level.color)

            Text(focus.detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func rivalryRow(_ hint: RivalryHint) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "figure.run")
                .font(.system(size: 10, weight: .bold))
            Text("\(hint.gapText) \(hint.actionSuffix)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundColor(MADTheme.Colors.madRed)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(MADTheme.Colors.madRed.opacity(0.12))
        )
    }
}

// MARK: - Formatting helpers

enum CompeteFormat {
    /// "3d left" / "6h left" / "Last day". Nil when the competition has no end
    /// date (race and streaks end on a condition, not a clock).
    static func timeLeft(for competition: Competition) -> String? {
        guard let end = competition.endDateFormatted else { return nil }
        var et = Calendar(identifier: .gregorian)
        et.timeZone = TimeZone(identifier: "America/New_York")!
        guard let expiry = et.date(byAdding: .day, value: 1, to: et.startOfDay(for: end)) else { return nil }

        let remaining = expiry.timeIntervalSince(Date())
        guard remaining > 0 else { return nil }

        let days = Int(remaining / 86_400)
        if days >= 1 { return "\(days)d left" }
        let hours = Int(remaining / 3_600)
        if hours >= 1 { return "\(hours)h left" }
        return "Last day"
    }

    /// "Aug 4" from a backend "YYYY-MM-DD" date column.
    static func shortDate(_ ymd: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = TimeZone(identifier: "America/New_York")
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: ymd) else { return ymd }

        let out = DateFormatter()
        out.dateFormat = "MMM d"
        out.locale = Locale.current
        return out.string(from: date)
    }
}

// MARK: - Mode gallery

/// One of the five modes, as something you can start rather than something you
/// have to already understand.
struct ModeGalleryCard: View {
    let type: CompetitionType
    let action: () -> Void

    private var gradientColors: [Color] {
        type.gradient.map { Color(hex: $0) }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: type.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(gradientColors[0].opacity(0.15))
                            .overlay(Circle().strokeBorder(gradientColors[0].opacity(0.45), lineWidth: 1))
                    )

                Text(type.displayName)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Text(type.tagline)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text("How it works")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(gradientColors[0])
            }
            .frame(width: 168, alignment: .leading)
            .frame(minHeight: 172, alignment: .top)
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [gradientColors[0].opacity(0.12), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(gradientColors[0].opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

/// A quick-start preset — the two-tap path past the nine-question form.
struct PresetCard: View {
    let preset: CompetitionPreset
    let action: () -> Void

    private var gradientColors: [Color] {
        preset.gradient.map { Color(hex: $0) }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: preset.systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(gradientColors[0].opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(preset.blurb)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Recently finished

/// A finished competition, small. Used both by the Compete tab's "just
/// wrapped" strip and by the Record tab's history list.
struct FinishedCompetitionRow: View {
    let competition: Competition
    var compact: Bool = false
    let action: () -> Void

    private var gradientColors: [Color] {
        competition.type.gradient.map { Color(hex: $0) }
    }

    private var placement: Int? {
        guard let uid = UserDefaults.standard.string(forKey: "backendUserId") else { return nil }
        if let winner = competition.winner { return winner == uid ? 1 : nil }
        let ranked = competition.users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        return ranked.firstIndex(where: { $0.user_id == uid }).map { $0 + 1 }
    }

    private var resultText: String {
        guard let placement else { return "Finished" }
        let field = competition.users.filter { $0.invite_status == .accepted }.count
        return placement == 1 ? "Won" : "\(ActiveCompetitionRow.ordinal(placement)) of \(field)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(gradientColors[0].opacity(0.14))
                        .frame(width: compact ? 40 : 44, height: compact ? 40 : 44)
                    Image(systemName: competition.isWinner ? "crown.fill" : competition.type.icon)
                        .font(.system(size: compact ? 15 : 16, weight: .bold))
                        .foregroundStyle(
                            competition.isWinner
                                ? LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(competition.competition_name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(resultText)
                            .foregroundColor(competition.isWinner ? .yellow : .white.opacity(0.55))
                        Text("·")
                            .foregroundColor(.white.opacity(0.3))
                        Text(competition.type.displayName)
                            .foregroundColor(.white.opacity(0.45))
                        if let end = competition.end_date {
                            Text("·")
                                .foregroundColor(.white.opacity(0.3))
                            Text(CompeteFormat.shortDate(end))
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(width: compact ? 240 : nil, alignment: .leading)
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(
                                competition.isWinner
                                    ? Color.yellow.opacity(0.28)
                                    : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Record

/// The W–L hero. The number people come to the Record tab for.
struct RecordHeroCard: View {
    let wins: Int
    let losses: Int
    let podiums: Int
    let currentStreak: Int
    /// True when the numbers are derived client-side from a single page of
    /// competitions rather than from the server's full history.
    let isPartial: Bool

    private var total: Int { wins + losses }
    private var winRate: Int {
        guard total > 0 else { return 0 }
        return Int((Double(wins) / Double(total) * 100).rounded())
    }

    var body: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(wins)")
                    .foregroundColor(.white)
                Text("–")
                    .foregroundColor(.white.opacity(0.4))
                Text("\(losses)")
                    .foregroundColor(.white.opacity(0.55))
            }
            .font(.system(size: 46, weight: .heavy, design: .rounded))

            Text(total == 0 ? "No finished competitions yet" : "\(winRate)% win rate · \(total) finished")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))

            if total > 0 {
                HStack(spacing: 0) {
                    statCell(value: "\(wins)", label: "Wins", tint: .yellow)
                    divider
                    statCell(value: "\(podiums)", label: "Podiums", tint: MADTheme.Colors.madRed)
                    divider
                    statCell(value: "\(currentStreak)", label: "Win streak", tint: .green)
                }
                .padding(.top, 2)
            }

            if isPartial && total > 0 {
                Text("From your recent competitions")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.lg)
        .padding(.horizontal, MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.extraLarge, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.extraLarge, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MADTheme.Colors.madRed.opacity(0.14), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.extraLarge, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func statCell(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 28)
    }
}

/// One mode's W–L, with a bar so the grid is scannable without reading numbers.
struct ModeRecordRow: View {
    let record: CompetitionModeRecord

    private var gradientColors: [Color] {
        record.type.gradient.map { Color(hex: $0) }
    }

    private var fraction: Double {
        guard record.total > 0 else { return 0 }
        return Double(record.wins) / Double(record.total)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.type.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(record.total > 0 ? gradientColors[0] : .white.opacity(0.25))
                .frame(width: 26)

            Text(record.type.displayName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(record.total > 0 ? .white.opacity(0.9) : .white.opacity(0.35))
                .frame(width: 62, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(
                            LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 6)

            Text(record.total > 0 ? "\(record.wins)–\(record.losses)" : "—")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(record.total > 0 ? .white.opacity(0.75) : .white.opacity(0.3))
                .frame(width: 38, alignment: .trailing)
        }
    }
}

/// Your head-to-head record against one person.
struct RivalRow: View {
    let rival: CompetitionRecord.Rival

    /// Green when you're up, red when you're down, neutral when level or when
    /// every meeting was decided by somebody else.
    private var tint: Color {
        if rival.wins > rival.losses { return .green }
        if rival.losses > rival.wins { return MADTheme.Colors.madRed }
        return .white.opacity(0.6)
    }

    /// A competition a third party won is a meeting but not a result, so the
    /// W–L can legitimately be 0–0 with several meetings behind it.
    private var subtitle: String {
        let decided = rival.wins + rival.losses
        if decided == 0 {
            return rival.meetings == 1
                ? "1 competition together"
                : "\(rival.meetings) competitions together"
        }
        if rival.meetings > decided {
            return "\(rival.meetings) together · \(decided) decided between you"
        }
        return rival.meetings == 1 ? "1 competition" : "\(rival.meetings) competitions"
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                name: rival.displayName,
                imageURL: rival.profile_image_url,
                size: 38
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(rival.displayName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(rival.recordText)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
                // Data-driven, but short and bounded — never let it truncate in
                // favour of the name.
                .fixedSize()
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

// MARK: - Section header

/// Shared section label for the Compete/Record scroll views, with an optional
/// trailing action.
struct CompeteSectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var accent: Color = .white
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(accent)
            }

            Text(title.uppercased())
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.85))

            Spacer(minLength: 4)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(MADTheme.Colors.madRed)
                }
                .fixedSize()
            }
        }
    }
}
