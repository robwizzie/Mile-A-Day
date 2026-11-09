import SwiftUI

// Support types for the day-detail sheet surfaced from CompetitionMyDailyRings.
// The scoreboard grid that used to live in this file was retired in favor of
// the ring strip — the rings cover the same info more visually and tapping
// a ring opens the detail sheet below.

// MARK: - Identifiable Date wrapper
/// `Sheet(item:)` requires Identifiable, but `Date` isn't on its own.
struct IdentifiableDate: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

// MARK: - Day Detail Sheet
/// Surfaced when a ring in `CompetitionMyDailyRings` is tapped. Shows every
/// accepted user's miles for that day, sorted by miles desc, with
/// mode-specific status icons. For weekly/monthly comps the "day" is
/// actually the interval anchor — the header reflects that.
struct CompetitionDayDetailSheet: View {
    let competition: Competition
    let date: Date
    let intervalKey: String
    let interval: CompetitionInterval

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var accepted: [CompetitionUser] {
        competition.users.filter { $0.invite_status == .accepted }
    }

    private var sortedUsers: [CompetitionUser] {
        accepted.sorted { ($0.intervals?[intervalKey] ?? 0) > ($1.intervals?[intervalKey] ?? 0) }
    }

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    private var gradientColors: [Color] {
        competition.type.gradient.map { Color(hex: $0) }
    }

    private var titleText: String {
        let f = DateFormatter()
        switch interval {
        case .day:
            if Calendar.current.isDateInToday(date) { return "Today" }
            if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
            f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
            return f.string(from: date)
        case .week:
            f.setLocalizedDateFormatFromTemplate("MMMd")
            let end = Calendar.current.date(byAdding: .day, value: 6, to: date) ?? date
            return "Week of \(f.string(from: date)) – \(f.string(from: end))"
        case .month:
            f.dateFormat = "MMMM yyyy"
            return f.string(from: date)
        }
    }

    private var totalMiles: Double {
        accepted.reduce(0) { $0 + ($1.intervals?[intervalKey] ?? 0) }
    }

    private var winnerId: String? {
        let active = accepted.filter { ($0.intervals?[intervalKey] ?? 0) > 0 }
        return active.max(by: { ($0.intervals?[intervalKey] ?? 0) < ($1.intervals?[intervalKey] ?? 0) })?.user_id
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHeader

                ScrollView {
                    VStack(spacing: 14) {
                        summaryRow

                        VStack(spacing: 6) {
                            ForEach(Array(sortedUsers.enumerated()), id: \.element.id) { index, user in
                                detailRow(rank: index + 1, user: user)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(competition.type.displayName.uppercased())
                    .madFont(size: 11, weight: .black, design: .rounded)
                    .tracking(1.2)
                    .foregroundColor(gradientColors.first ?? .white.opacity(0.5))
                Text(titleText)
                    .madFont(size: 20, weight: .bold, design: .rounded)
                    .foregroundColor(.white)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .madFont(size: 24, maxScale: 1.5)
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var winnerValue: String {
        guard let winnerId, let w = accepted.first(where: { $0.user_id == winnerId }) else { return "—" }
        return w.displayName
    }

    /// Three columns normally; stacked at accessibility sizes, where a third of
    /// the sheet can't hold "COMPETITORS".
    @ViewBuilder private var summaryStats: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                summaryStat(label: "Total miles", value: String(format: "%.1f mi", totalMiles))
                summaryStat(label: "Competitors", value: "\(accepted.count)")
                summaryStat(label: winnerLabel, value: winnerValue)
            }
        } else {
            HStack(spacing: 16) {
                summaryStat(label: "Total miles", value: String(format: "%.1f mi", totalMiles))
                Divider().background(Color.white.opacity(0.1)).frame(height: 28)
                summaryStat(label: "Competitors", value: "\(accepted.count)")
                Divider().background(Color.white.opacity(0.1)).frame(height: 28)
                summaryStat(label: winnerLabel, value: winnerValue)
            }
        }
    }

    private var summaryRow: some View {
        summaryStats
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(CompeteDesign.hairline, lineWidth: 1)
                )
        )
    }

    private var winnerLabel: String {
        switch competition.type {
        case .clash: return "Day winner"
        case .apex: return "Top miles"
        case .targets: return "Top miles"
        case .streaks: return "Top miles"
        case .race: return "Top miles"
        }
    }

    private func summaryStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .madFont(size: 11, weight: .heavy, design: .rounded)
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.45))
            Text(value)
                .madFont(size: 13, weight: .bold, design: .rounded)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(rank: Int, user: CompetitionUser) -> some View {
        let miles = user.intervals?[intervalKey] ?? 0
        let isMe = user.user_id == currentUserId
        let isWinner = user.user_id == winnerId && miles > 0
        let goal = competition.options.goal
        let hitGoal = goal > 0 && miles >= goal

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isWinner ? Color.yellow.opacity(0.25) : Color.white.opacity(0.08))
                    .frame(width: 28, height: 28)
                if isWinner {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                } else {
                    Text("\(rank)")
                        .madFont(size: 12, weight: .bold, design: .rounded)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                MADInlineStack {
                    Text(user.displayName)
                        .madFont(size: 14, weight: .semibold, design: .rounded)
                        .foregroundColor(.white)
                        .madNameLines()
                    if isMe {
                        Text("YOU")
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .madFont(size: 11, weight: .bold, maxScale: 1.3)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(MADTheme.Colors.madRed))
                    }
                }
                modeSpecificStatus(miles: miles, hitGoal: hitGoal, isWinner: isWinner)
            }

            Spacer()

            Text(miles > 0 ? String(format: "%.2f mi", miles) : "—")
                .madFont(size: 14, weight: .bold, design: .rounded)
                .foregroundColor(miles > 0 ? .white : .white.opacity(0.3))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isMe ? Color.white.opacity(0.08) : Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isMe ? MADTheme.Colors.primary.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func modeSpecificStatus(miles: Double, hitGoal: Bool, isWinner: Bool) -> some View {
        switch competition.type {
        case .clash:
            if isWinner {
                Text("Won the day · +1 pt")
                    .madFont(size: 11, weight: .semibold, design: .rounded)
                    .foregroundColor(.yellow)
            } else if miles > 0 {
                Text("No point")
                    .madFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
            } else {
                Text("No activity")
                    .madFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
            }
        case .targets:
            if hitGoal {
                Text("Hit target · +1 pt")
                    .madFont(size: 11, weight: .semibold, design: .rounded)
                    .foregroundColor(.green)
            } else if miles > 0 {
                let progress = min(1, miles / max(competition.options.goal, 0.1))
                Text("\(ProgressCalculator.formatProgress(progress)) of target")
                    .madFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundColor(.orange)
            } else {
                Text("Missed target")
                    .madFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
            }
        case .streaks:
            if hitGoal {
                Text("Streak safe")
                    .madFont(size: 11, weight: .semibold, design: .rounded)
                    .foregroundColor(.green)
            } else if Calendar.current.isDateInToday(date) && miles >= 0 {
                Text("Today — not yet done")
                    .madFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundColor(.orange)
            } else {
                Text("Life lost")
                    .madFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundColor(.red.opacity(0.7))
            }
        case .apex:
            if isWinner {
                Text("Most miles today")
                    .madFont(size: 11, weight: .semibold, design: .rounded)
                    .foregroundColor(.green)
            } else if miles > 0 {
                Text("Banked toward total")
                    .madFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text("No activity")
                    .madFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
            }
        case .race:
            if miles > 0 {
                Text("Toward finish line")
                    .madFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text("No activity")
                    .madFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}
