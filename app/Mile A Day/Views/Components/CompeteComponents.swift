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

    /// "2nd of 5", or "2nd of 3 teams" when the competition is scored on teams
    /// — ranking the person there names a standing the competition isn't
    /// played on. Nil when the standings don't include us yet (pre-start, or a
    /// payload that hasn't resolved scores).
    private var standingText: String? {
        guard let uid = currentUserId,
              let standing = competition.standing(for: uid) else { return nil }
        let place = Self.ordinal(standing.place)
        return standing.isTeam ? "\(place) of \(standing.of) teams" : "\(place) of \(standing.of)"
    }

    /// `nonisolated` because it is pure arithmetic called from plain models
    /// (`CompetitionStickerData.standingText`): every member of a View struct
    /// — statics included — inherits @MainActor, which makes a call from a
    /// nonisolated context a Swift 6 error the CLI type-check never shows.
    nonisolated static func ordinal(_ rank: Int) -> String {
        switch rank {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(rank)th"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                topRow
                focusLine
                if let hint = competition.rivalryHint {
                    rivalryRow(hint)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous)
                    .fill(CompeteDesign.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous)
                    .strokeBorder(CompeteDesign.hairline, lineWidth: 1)
            )
            // The competition's colour as a rail, not as a wash over the whole
            // card. A diagonal tinted gradient behind the text was the single
            // thing that dated this row most: it greyed the copy sitting on it
            // and made twelve cards in a list read as twelve different
            // materials.
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(accent)
                    .frame(width: 3)
                    .padding(.vertical, 14)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var accent: Color { CompeteDesign.accent(competition.type) }

    private var topRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(competition.competition_name)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(CompeteDesign.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    Text(competition.type.displayName.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(0.9)
                        .foregroundColor(accent)
                    if let standing = standingText {
                        Text("·").foregroundColor(CompeteDesign.inkGhost)
                        Text(standing)
                            .font(CompeteDesign.caption)
                            .foregroundColor(CompeteDesign.inkMuted)
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let timeLeft = CompeteFormat.timeLeft(for: competition) {
                Text(timeLeft)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(CompeteDesign.inkFaint)
                    .monospacedDigit()
                    // Data-driven text in a fixed row: let the NAME truncate
                    // first, never this.
                    .fixedSize()
            }
        }
        .padding(.leading, 10)
    }

    /// What to do about it today — the reason this row leads with focus rather
    /// than with the competition's name.
    private var focusLine: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(focus.pill)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.9)
                .foregroundColor(focus.level.color)
                .lineLimit(1)

            Text(focus.detail)
                .font(CompeteDesign.detail)
                .foregroundColor(CompeteDesign.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 10)
        .accessibilityElement(children: .combine)
    }

    private func rivalryRow(_ hint: RivalryHint) -> some View {
        HStack(spacing: 6) {
            Text("\(hint.gapText) \(hint.actionSuffix)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(MADTheme.Colors.madRed)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
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
                    .fill(CompeteDesign.surface)
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
                            .strokeBorder(CompeteDesign.hairline, lineWidth: 1)
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

    /// Where this finished — the TEAM's place on a team competition, since
    /// that is what the competition was scored on and what the end screen
    /// prints. `standing(for:)` is the one place that decision is made.
    private var standing: (place: Int, of: Int, isTeam: Bool)? {
        guard let uid = UserDefaults.standard.string(forKey: "backendUserId") else { return nil }
        return competition.standing(for: uid)
    }

    private var placement: Int? { standing?.place }

    /// "Team 2 won" / "Won" / "2nd of 3 teams" / "4th of 6".
    ///
    /// It used to key "Won" off the stored `winner` matching you, which on a
    /// team competition is only ever the winning team's biggest contributor —
    /// so three of the four people who won it were shown "Finished" — and then
    /// fall back to an INDIVIDUAL place counted against the number of people,
    /// which is not the board this competition was decided on.
    private var resultText: String {
        guard let standing else { return "Finished" }
        if standing.place == 1 {
            guard standing.isTeam,
                  let uid = UserDefaults.standard.string(forKey: "backendUserId"),
                  let myTeam = competition.team(for: uid) else { return "Won" }
            return "\(myTeam.name) won"
        }
        let field = standing.isTeam
            ? "\(standing.of) team\(standing.of == 1 ? "" : "s")"
            : "\(standing.of)"
        return "\(ActiveCompetitionRow.ordinal(standing.place)) of \(field)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                // The PLACE, not the mode's icon. A finished competition is
                // remembered by how it went; the icon told you which game it
                // was, which is the one thing the name beside it already says.
                if let placement {
                    CompeteRankBadge(place: placement, size: 30)
                } else {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(CompeteDesign.inkFaint)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(competition.competition_name)
                        .font(CompeteDesign.nameSmall)
                        .foregroundColor(CompeteDesign.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 5) {
                        Text(resultText)
                            .foregroundColor(competition.isWinner ? (CompeteDesign.medal(1) ?? .yellow) : CompeteDesign.inkMuted)
                        Text("·").foregroundColor(CompeteDesign.inkGhost)
                        Text(competition.type.displayName)
                            .foregroundColor(CompeteDesign.inkFaint)
                        if let end = competition.end_date {
                            Text("·").foregroundColor(CompeteDesign.inkGhost)
                            Text(CompeteFormat.shortDate(end))
                                .foregroundColor(CompeteDesign.inkFaint)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(width: compact ? 240 : nil, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous)
                    .fill(CompeteDesign.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous)
                    .strokeBorder(
                        competition.isWinner
                            ? (CompeteDesign.medal(1) ?? .yellow).opacity(0.4)
                            : CompeteDesign.hairline,
                        lineWidth: 1
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

            Text(total == 0 ? "No finished competitions yet" : "\(ProgressCalculator.formatWholePercent(Double(winRate))) win rate · \(total) finished")
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
                .fill(CompeteDesign.surface)
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
                .fill(CompeteDesign.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .strokeBorder(CompeteDesign.hairline, lineWidth: 1)
                )
        )
    }
}

// MARK: - Section header

/// Shared section label for the Compete/Record scroll views, with an optional
/// trailing action. Same eyebrow as `CompeteHeader` so a section on the Compete
/// home and a section inside a competition read as the same rank of heading.
struct CompeteSectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var accent: Color = .white
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(CompeteDesign.eyebrow)
                .tracking(CompeteDesign.eyebrowTracking)
                .foregroundColor(CompeteDesign.inkFaint)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(MADTheme.Colors.madRed)
                }
                .fixedSize()
            }
        }
    }
}
