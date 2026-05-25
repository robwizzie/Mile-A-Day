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
            f.dateFormat = "EEEE, MMM d"
            return f.string(from: date)
        case .week:
            f.dateFormat = "MMM d"
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
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(gradientColors.first ?? .white.opacity(0.5))
                Text(titleText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var summaryRow: some View {
        HStack(spacing: 16) {
            summaryStat(label: "Total miles", value: String(format: "%.1f mi", totalMiles))
            Divider().background(Color.white.opacity(0.1)).frame(height: 28)
            summaryStat(label: "Competitors", value: "\(accepted.count)")
            Divider().background(Color.white.opacity(0.1)).frame(height: 28)
            if let winnerId, let w = accepted.first(where: { $0.user_id == winnerId }) {
                summaryStat(label: winnerLabel, value: w.displayName)
            } else {
                summaryStat(label: winnerLabel, value: "—")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
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
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
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
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(user.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if isMe {
                        Text("YOU")
                            .font(.system(size: 8, weight: .bold))
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
                .font(.system(size: 14, weight: .bold, design: .rounded))
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
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.yellow)
            } else if miles > 0 {
                Text("No point")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Text("No activity")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
            }
        case .targets:
            if hitGoal {
                Text("Hit target · +1 pt")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
            } else if miles > 0 {
                Text(String(format: "%.0f%% of target", min(100, miles / max(competition.options.goal, 0.1) * 100)))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.orange)
            } else {
                Text("Missed target")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
        case .streaks:
            if hitGoal {
                Text("Streak safe")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
            } else if Calendar.current.isDateInToday(date) && miles >= 0 {
                Text("Today — not yet done")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.orange)
            } else {
                Text("Life lost")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.red.opacity(0.7))
            }
        case .apex:
            if isWinner {
                Text("Most miles today")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
            } else if miles > 0 {
                Text("Banked toward total")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text("No activity")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
            }
        case .race:
            if miles > 0 {
                Text("Toward finish line")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text("No activity")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }
}
