import SwiftUI

/// Recovery Mode — start a pause, watch one run, or find out why you can't.
///
/// Every number on this screen comes off `InjuryPauseStatus`, never a local
/// constant. The rules ARE the anti-abuse design (90-day streak to unlock, 30
/// days minimum, 180-day cap, 90 consecutive days before the next one), so the
/// screen states them plainly rather than hiding them behind a confirmation —
/// a user who only discovers the 30-day minimum after tapping has been tricked.
struct RecoveryModeView: View {
    @ObservedObject private var state = InjuryPauseState.shared
    @Environment(\.dismiss) private var dismiss

    @State private var backdateDays = 0
    @State private var confirmingStart = false
    @State private var confirmingEnd = false
    @State private var working = false
    @State private var errorMessage: String?

    private var status: InjuryPauseStatus? { state.status }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let status {
                    if let active = status.active {
                        pausedSection(status: status, active: active)
                    } else {
                        // `eligible` is the gate, not the reason string. A
                        // server that says no for a reason this build doesn't
                        // know (the kill switch, or a rule added later) must
                        // not fall through to an enabled CTA that POST will
                        // then reject.
                        switch status.reason {
                        case "rebuilding": rebuildingSection(status)
                        case "streak_too_short", "not_enrolled": lockedSection(status)
                        default:
                            if status.eligible {
                                startSection(status)
                            } else {
                                unavailableSection
                            }
                        }
                    }
                } else if state.isLoading {
                    ProgressView().padding(.top, 60)
                } else {
                    Text("Couldn't load Recovery Mode.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                }
            }
            .padding(20)
        }
        .navigationTitle("Recovery Mode")
        .navigationBarTitleDisplayMode(.inline)
        .task { await state.refresh() }
        .alert("Pause your streak?", isPresented: $confirmingStart) {
            Button("Cancel", role: .cancel) {}
            Button("Pause", role: .destructive) { Task { await start() } }
        } message: {
            Text(startConfirmationCopy)
        }
        .alert("End your pause?", isPresented: $confirmingEnd) {
            Button("Cancel", role: .cancel) {}
            Button("End pause") { Task { await end() } }
        } message: {
            Text("Your streak starts counting again from today. You'll need \(status?.reearn_target ?? 90) days back before you can pause again.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Paused

    private func pausedSection(status: InjuryPauseStatus, active: InjuryPauseStatus.Active) -> some View {
        VStack(spacing: 18) {
            InjuredFlameBuddyView(size: 150, look: FlameyFacts.look())
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("\(active.frozen_streak)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("DAY STREAK · FROZEN")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }

            Text("Paused \(active.paused_days) \(active.paused_days == 1 ? "day" : "days") for injury")
                .font(.system(size: 15, weight: .medium, design: .rounded))

            card {
                infoRow("Started", active.started_on)
                Divider().opacity(0.4)
                infoRow("Ends by itself", active.expires_on)
                Divider().opacity(0.4)
                infoRow(
                    "Can end",
                    active.can_end ? "Now" : "in \(status.daysUntilCanEnd) \(status.daysUntilCanEnd == 1 ? "day" : "days")"
                )
            }

            Text("Your streak won't grow while it's paused, even on days you walk.")
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                confirmingEnd = true
            } label: {
                Text(active.can_end
                     ? "I'm back — end pause"
                     : "End pause · available in \(status.daysUntilCanEnd) \(status.daysUntilCanEnd == 1 ? "day" : "days")")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(active.can_end
                                       ? MADTheme.Colors.madRed
                                       : Color.secondary.opacity(0.18))
                    )
                    .foregroundStyle(active.can_end ? .white : Color.secondary)
            }
            .disabled(!active.can_end || working)
        }
    }

    // MARK: - Start

    private func startSection(_ status: InjuryPauseStatus) -> some View {
        VStack(spacing: 18) {
            InjuredFlameBuddyView(size: 130, look: FlameyFacts.look()).padding(.top, 4)

            Text("Hurt yourself?")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("Pause your streak while you recover. It freezes where it is and won't grow until you're back.")
                .font(.system(size: 13.5, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            card {
                infoRow("Lasts at least", "\(status.min_days) days")
                Divider().opacity(0.4)
                infoRow("Ends by itself after", "\(status.max_days) days")
                Divider().opacity(0.4)
                infoRow("Pause again after", "\(status.reearn_target) days back")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("When did it happen?")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                dayStrip(maxDaysAgo: status.max_backdate_days)
                Text(backdateCaption)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Button {
                confirmingStart = true
            } label: {
                Text("Pause my streak")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(MADTheme.Colors.madRed))
                    .foregroundStyle(.white)
            }
            .disabled(working)

            Text("You can end it once the \(status.min_days) days are up.")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    /// The days you can start the pause on, as tiles: weekday over date.
    ///
    /// Not a segmented control: today plus the server's backdate limit is
    /// eight choices, and eight segments across a phone leave ~40pt each, so
    /// every label ("Today", "3d ago") truncated. A tile only has to hold
    /// "TODAY"/"THU" over a number. Should the limit grow past what fits,
    /// the same tiles scroll instead of shrinking.
    private func dayStrip(maxDaysAgo: Int) -> some View {
        let days = Array(0...max(0, maxDaysAgo))
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { dayTile(daysAgo: $0) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(days, id: \.self) { dayTile(daysAgo: $0).frame(width: 44) }
                }
            }
        }
    }

    private func dayTile(daysAgo: Int) -> some View {
        let date = InjuryPauseDate.date(daysAgo: daysAgo)
        let selected = backdateDays == daysAgo
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            MADHaptics.tap()
            backdateDays = daysAgo
        } label: {
            VStack(spacing: 1) {
                Group {
                    if daysAgo == 0 {
                        Text("Today")
                    } else {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.white : Color.primary)
            }
            .frame(minWidth: 38, maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(shape.fill(selected ? MADTheme.Colors.madRed : Color(.secondarySystemBackground)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(date.formatted(.dateTime.weekday(.wide).month(.wide).day())), \(Self.agoText(daysAgo))"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// "Thu, Oct 8 · 3 days ago" under the tiles, so the choice is spelled out.
    private var backdateCaption: String {
        let date = InjuryPauseDate.date(daysAgo: backdateDays)
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(Self.agoText(backdateDays))"
    }

    private static func agoText(_ days: Int) -> String {
        switch days {
        case 0: return String(localized: "today")
        case 1: return String(localized: "yesterday")
        default: return String(localized: "\(days) days ago")
        }
    }

    private var startConfirmationCopy: String {
        guard let status else { return "" }
        let when = backdateDays == 0 ? "today" : "\(backdateDays) days ago"
        return "Your streak freezes as it stood before \(when). It can't be ended for \(status.min_days) days, and you'll need \(status.reearn_target) days back before you can pause again."
    }

    private var unavailableSection: some View {
        blockedCard(
            badge: "UNAVAILABLE",
            title: "Not right now",
            message: "Recovery Mode can't be started at the moment. Try again later.",
            progress: nil,
            total: nil,
            tint: .secondary
        )
    }

    // MARK: - Blocked

    private func rebuildingSection(_ status: InjuryPauseStatus) -> some View {
        blockedCard(
            badge: "REBUILDING",
            title: "Not yet",
            message: "You've run \(status.reearn_progress) of \(status.reearn_target) days since your last pause. \(max(0, status.reearn_target - status.reearn_progress)) to go before you can use it again.",
            progress: Double(status.reearn_progress),
            total: Double(status.reearn_target),
            tint: MADTheme.Colors.madRed
        )
    }

    private func lockedSection(_ status: InjuryPauseStatus) -> some View {
        VStack(spacing: 14) {
            blockedCard(
                badge: "LOCKED",
                title: "Build a streak first",
                message: "Recovery Mode unlocks at a \(status.min_streak)-day streak.",
                progress: nil,
                total: nil,
                tint: .secondary
            )
            Text("Missed one day to something short? Streak Save and Double Down still cover that.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func blockedCard(
        badge: String,
        title: String,
        message: String,
        progress: Double?,
        total: Double?,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                Text(badge)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.14)))

            Text(title).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(message)
                .font(.system(size: 13.5, design: .rounded))
                .foregroundStyle(.secondary)

            if let progress, let total, total > 0 {
                ProgressView(value: min(progress / total, 1))
                    .tint(tint)
                HStack {
                    Text("\(Int(progress))")
                    Spacer()
                    Text("\(Int(total)) days")
                }
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    // MARK: - Bits

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 10) { content() }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13.5, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
        }
    }

    // MARK: - Actions

    private func start() async {
        working = true
        defer { working = false }
        let day = backdateDays == 0
            ? nil
            : InjuryPauseDate.localDateString(daysAgo: backdateDays)
        errorMessage = await state.start(startedOn: day)
    }

    private func end() async {
        working = true
        defer { working = false }
        errorMessage = await state.end()
    }
}

/// YYYY-MM-DD in the DEVICE's local calendar — the same basis the server files
/// `local_date` under. Never UTC: an evening injury would land on the wrong day
/// and either miss the backdate window or skip a day the user actually ran.
enum InjuryPauseDate {
    /// The day `daysAgo` local days back — the same day the tile shows and
    /// `localDateString` sends.
    static func date(daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    }

    static func localDateString(daysAgo: Int) -> String? {
        guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
