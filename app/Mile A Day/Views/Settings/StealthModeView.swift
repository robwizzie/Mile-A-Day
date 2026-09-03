import SwiftUI

/// The one owner of the Stealth Mode server call. Every entry point (Settings
/// row, Notifications & Sharing row, the dashboard banner) opens THIS sheet
/// rather than carrying its own toggle, because enabling asks a follow-up
/// question — "also hide routes from…" — that a bare switch can't.
///
/// Local-first: the store is written before the PUT, so an enable made on a
/// plane still keeps the next upload's route on the phone. The server's
/// response then re-hydrates the window log and wins.
struct StealthModeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var friendService = FriendService()

    @State private var isOn: Bool
    @State private var untilEnabled: Bool
    @State private var untilDate: Date
    @State private var backdate: Backdate = .now
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Whether the store said "on" when the sheet opened — the backdate
    /// question is only asked on an off→on transition.
    private let wasOn: Bool

    init() {
        let store = StealthModeStore.shared
        wasOn = store.isOn
        _isOn = State(initialValue: store.isOn)
        _untilEnabled = State(initialValue: store.until != nil)
        _untilDate = State(initialValue: store.until ?? Date().addingTimeInterval(7 * 86400))
    }

    /// "Also hide routes from…" — how far back the window reaches on enable.
    /// Capsule chips, not `.segmented`: UIKit's segmented control renders
    /// badly on the dark gradient (see GhostRaceOptionsContent).
    private enum Backdate: String, CaseIterable, Identifiable {
        case now, today, week, month
        var id: String { rawValue }
        var title: String {
            switch self {
            case .now: return "Now"
            case .today: return "Start of today"
            case .week: return "Last 7 days"
            case .month: return "Last 30 days"
            }
        }
        var date: Date? {
            let calendar = Calendar.current
            switch self {
            case .now: return nil
            case .today: return calendar.startOfDay(for: Date())
            case .week: return calendar.date(byAdding: .day, value: -7, to: Date())
            case .month: return calendar.date(byAdding: .day, value: -30, to: Date())
            }
        }
    }

    private var isEnabling: Bool { isOn && !wasOn }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                        header
                        masterCard
                        if isOn {
                            untilCard
                            if isEnabling { backdateCard }
                        }
                        whatHappensCard
                        if !StealthModeStore.shared.recentWindows.isEmpty {
                            historyCard
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        saveButton
                    }
                    .padding(MADTheme.Spacing.lg)
                    .padding(.bottom, MADTheme.Spacing.xl)
                }
            }
            .navigationTitle("Stealth Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.22))
                    .frame(width: 52, height: 52)
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Hide where you walk")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Friends still see your distance, pace and time — never the map. Walks recorded while this is on stay hidden for good, even after you turn it off.")
                    .modifier(StealthCaption())
            }
        }
    }

    private var masterCard: some View {
        card {
            Toggle(isOn: $isOn.animation(.easeInOut(duration: 0.2))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stealth Mode")
                        .font(MADTheme.Typography.bodyBold)
                        .foregroundColor(.white)
                    Text(isOn ? "Routes are hidden from friends" : "Routes are shared per your settings")
                        .modifier(StealthCaption())
                }
            }
            .tint(MADTheme.Colors.madRed)
            .onChange(of: isOn) { _, _ in MADHaptics.tap() }
        }
    }

    private var untilCard: some View {
        card {
            Toggle(isOn: $untilEnabled.animation(.easeInOut(duration: 0.2))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn off automatically")
                        .font(MADTheme.Typography.bodyBold)
                        .foregroundColor(.white)
                    Text("For a trip: pick the day you're back and forget about it.")
                        .modifier(StealthCaption())
                }
            }
            .tint(MADTheme.Colors.madRed)
            .onChange(of: untilEnabled) { _, _ in MADHaptics.tap() }
            if untilEnabled {
                DatePicker(
                    "Until",
                    selection: $untilDate,
                    in: Date().addingTimeInterval(3600)...Date().addingTimeInterval(
                        Double(StealthModeStore.untilLimitDays) * 86400),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(MADTheme.Colors.madRed)
                .foregroundColor(.white)
            }
        }
    }

    private var backdateCard: some View {
        card {
            Text("Also hide routes from…")
                .font(MADTheme.Typography.bodyBold)
                .foregroundColor(.white)
            Text("Already walked before you remembered? Earlier routes in this range are removed for friends too.")
                .modifier(StealthCaption())
            HStack(spacing: 8) {
                ForEach(Backdate.allCases) { option in
                    let selected = backdate == option
                    Button {
                        guard !selected else { return }
                        MADHaptics.tap()
                        withAnimation(.easeInOut(duration: 0.15)) { backdate = option }
                    } label: {
                        Text(option.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(selected ? .white : .white.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(selected
                                ? MADTheme.Colors.madRed.opacity(0.85)
                                : Color.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var whatHappensCard: some View {
        card {
            Text("What friends see")
                .font(MADTheme.Typography.bodyBold)
                .foregroundColor(.white)
            bullet("eye.slash", "Hidden: the map, route art and flyover of every walk recorded while it's on.")
            bullet("checkmark.circle", "Still shown: distance, pace, time, splits and any photo you choose to post.")
            bullet("lock.fill", "Permanent: those walks stay hidden even after you turn Stealth off.")
            bullet("iphone", "Your own map stays on this phone and in Apple Fitness.")
            bullet("map", "\"Share route maps\" is different: it only hides maps for display and can be turned back on.")
        }
    }

    private var historyCard: some View {
        card {
            Text("History")
                .font(MADTheme.Typography.bodyBold)
                .foregroundColor(.white)
            ForEach(Array(StealthModeStore.shared.recentWindows.prefix(5).enumerated()), id: \.offset) { _, window in
                Text(Self.describe(window))
                    .modifier(StealthCaption())
            }
        }
    }

    private var saveButton: some View {
        Button { save() } label: {
            HStack {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("Save")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Capsule().fill(MADTheme.Colors.redGradient))
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    // MARK: - Save

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let until: Date? = isOn && untilEnabled ? untilDate : nil
        let since: Date? = isEnabling ? backdate.date : nil

        // Local FIRST — an offline enable must still keep the next upload's
        // route on the phone.
        let store = StealthModeStore.shared
        store.setOn(isOn, until: until, since: since)

        var body: [String: Any] = ["stealth_mode": isOn]
        if isOn {
            let iso = ISO8601DateFormatter()
            body["stealth_until"] = until.map { iso.string(from: $0) } ?? NSNull()
            if let since { body["stealth_since"] = iso.string(from: since) }
        }
        Task {
            do {
                let response = try await friendService.updateNotificationSettings(body)
                await MainActor.run {
                    store.apply(response)
                    // A backdate scrubbed server routes the repeats cache may
                    // still index.
                    if since != nil { RouteMatcher.invalidateCache() }
                    MADHaptics.success()
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Saved on this phone, but the server didn't get it — check your connection and Save again."
                }
            }
        }
    }

    // MARK: - Helpers

    private static func describe(_ window: StealthWindow) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: window.start)
        guard let end = window.end else { return "Since \(start)" }
        if end > Date() { return "\(start) – until \(formatter.string(from: end))" }
        return "\(start) – \(formatter.string(from: end))"
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 18)
            Text(text)
                .modifier(StealthCaption())
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct StealthCaption: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, design: .rounded))
            .foregroundColor(.white.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Dashboard banner

/// "Stealth Mode is on" — a sibling of the Dashboard's attention slot, not an
/// `AttentionItem`: that slot keeps two items by strict priority, and a
/// privacy state must not be evicted by a friend request. Renders nothing
/// while off. Owns its own sheet (StreakTokensCard precedent), so
/// DashboardView gains no `.sheet`.
struct StealthAttentionRow: View {
    @State private var showSheet = false

    var body: some View {
        let store = StealthModeStore.shared
        if store.isOn {
            Button {
                MADHaptics.tap()
                showSheet = true
            } label: {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Stealth Mode is on — routes are hidden")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text(Self.subtitle(store))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(MADTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSheet) { StealthModeView() }
        }
    }

    private static func subtitle(_ store: StealthModeStore) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        if let until = store.until {
            return "Turns off \(formatter.string(from: until)) — tap to change"
        }
        if let since = store.onSince {
            let days = Calendar.current.dateComponents([.day], from: since, to: Date()).day ?? 0
            if days >= 14 {
                return "Still on since \(formatter.string(from: since)) — tap to review"
            }
            return "Since \(formatter.string(from: since)) — tap to change"
        }
        return "Tap to change"
    }
}

// MARK: - Per-workout hide

/// Retroactive stealth for ONE walk, from the owner's own detail screen. The
/// server stamps the workout and deletes its stored route; the id is
/// remembered locally because the HKWorkout carries no metadata for it.
struct StealthHideRouteButton: View {
    let workoutId: String

    @State private var confirming = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                MADHaptics.tap()
                confirming = true
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text("Hide this route from friends")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .alert("Hide this route?", isPresented: $confirming) {
                Button("Hide for good", role: .destructive) { hide() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Friends will no longer see where this walk was. The map stays on your phone. This can't be undone.")
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func hide() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                _ = try await WorkoutService().hideRouteFromFriends(workoutId: workoutId)
                await MainActor.run {
                    StealthModeStore.shared.markHidden(workoutId)
                    RouteMatcher.invalidateCache()
                    MADHaptics.success()
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    errorMessage = "Couldn't reach the server — try again."
                }
            }
        }
    }
}
