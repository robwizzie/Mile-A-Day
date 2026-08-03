import SwiftUI

/// Spending a Streak Assist on a friend, as a self-contained CTA.
///
/// Shared by the friends list row and the friend's profile so both surfaces
/// promise the same thing and take the same confirmation. States:
///
///  1. **Rescuable + token held** → the "Save Streak · Back to N days" pill.
///     N is where the friend LANDS (`restored_streak`), not the run that ended
///     at the miss — those differ by every day they've kept since. Tapping
///     opens a confirmation naming the day it covers and that same number.
///     Nothing is spent until it's confirmed.
///  2. **Rescuable, no token yet** → a locked pill showing the Assist meter, so
///     "why don't I have the option" has a visible answer instead of the CTA
///     silently not rendering.
///  3. **Rescuable, friend's build is too old** → a muted line saying so.
///  4. **Nothing to rescue** → renders nothing.
///
/// The friend may still be holding a token that fixes this for free (an open
/// Double Down window, or a Streak Save the morning sweep will consume). That
/// doesn't hide the CTA — it's said plainly in the confirmation, and the giver
/// decides.
struct SaveFriendStreakView: View {
    let friendId: String
    let friendName: String
    /// `.compact` is the friends-list row slot; `.prominent` is the profile
    /// action row, where the pill sits beside Nudge and Compete.
    var style: Style = .prominent
    /// Rescue state the host already has (the friends list gets every friend's
    /// in ONE status call). Supplying it skips the per-friend fetch — without
    /// this a 60-friend list would fire 60 requests to draw at most one pill.
    var preloaded: FriendRescueStatus? = nil
    /// Fired after a successful save, with the friend's restored streak.
    var onSaved: (Int) -> Void = { _ in }

    enum Style { case compact, prominent }

    @StateObject private var model: SaveFriendStreakModel
    @State private var showingConfirmation = false

    /// The first load is kicked off by the MODEL's init, not by the `.task`
    /// below. Every phase that shows no CTA renders `EmptyView`, and SwiftUI
    /// never fires lifecycle modifiers on an empty view — so a `.task`-driven
    /// first load could never leave `.idle`: empty view → no task → still
    /// `.idle` → still empty. The CTA was invisible on both surfaces.
    /// The `.task` stays for RE-loads (a fresh `preloaded` handed down), which
    /// only happen while the view is already rendering something.
    init(
        friendId: String,
        friendName: String,
        style: Style = .prominent,
        preloaded: FriendRescueStatus? = nil,
        onSaved: @escaping (Int) -> Void = { _ in }
    ) {
        self.friendId = friendId
        self.friendName = friendName
        self.style = style
        self.preloaded = preloaded
        self.onSaved = onSaved
        _model = StateObject(
            wrappedValue: SaveFriendStreakModel(friendId: friendId, preloaded: preloaded)
        )
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .unavailable:
                EmptyView()
            case .friendNeedsUpdate:
                infoPill(
                    icon: "arrow.down.circle",
                    text: "\(friendName) needs the latest update to be saved"
                )
            case .beyondRescue(let multiDay):
                infoPill(
                    icon: "clock.arrow.circlepath",
                    text: multiDay
                        ? "\(friendName) has missed more than one day — a Streak Assist only covers a single miss"
                        : "\(friendName)'s miss is too old to rescue — Assists reach back 2 days"
                )
            case .available(let status):
                if status.viewer_holds_assist {
                    saveButton(status)
                } else {
                    lockedPill(status)
                }
            case .saving:
                pill(background: MADTheme.Colors.redGradient) {
                    ProgressView().tint(.white).scaleEffect(0.6)
                }
            case .saved(let streak):
                savedPill(streak)
            }
        }
        .task(id: taskKey) { await model.load(friendId: friendId, preloaded: preloaded) }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save Streak") { save() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    // MARK: - States

    private func saveButton(_ status: FriendRescueStatus) -> some View {
        Button {
            MADHaptics.tap()
            showingConfirmation = true
        } label: {
            pill(background: MADTheme.Colors.redGradient) {
                HStack(spacing: 6) {
                    TokenMedallion(kind: .assist, held: true, size: style == .compact ? 18 : 20)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Save Streak")
                            .font(.system(size: style == .compact ? 11 : 12, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                        // Says where they LAND, not what's being spent. A bare
                        // "5 days" under "Save Streak" reads as "this saves 5
                        // days"; the number is actually the streak they end up
                        // on — their run before the miss, plus the covered day,
                        // plus every day they've kept since.
                        Text("Back to \(Self.dayCount(status.streakAfterSave))")
                            .font(.system(size: style == .compact ? 9 : 10, weight: .bold, design: .rounded))
                            .opacity(0.85)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .foregroundColor(.white)
            }
            .shadow(color: MADTheme.Colors.madRed.opacity(0.45), radius: 5)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    /// Rescuable, but the caller hasn't earned the Assist yet. Showing the meter
    /// beats showing nothing: the absence of a CTA is otherwise indistinguishable
    /// from the feature being broken.
    private func lockedPill(_ status: FriendRescueStatus) -> some View {
        let meter = status.viewer_meter
        let remaining = max(0, (meter?.target ?? 20) - (meter?.progress ?? 0))
        return pill(background: nil) {
            HStack(spacing: 6) {
                TokenMedallion(
                    kind: .assist,
                    held: false,
                    progress: meter?.fraction ?? 0,
                    size: style == .compact ? 18 : 20
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text("Streak Assist")
                        .font(.system(size: style == .compact ? 11 : 12, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                    Text(String(format: "%.1f mi to go", remaining))
                        .font(.system(size: style == .compact ? 9 : 10, weight: .bold, design: .rounded))
                        .opacity(0.7)
                }
            }
            .foregroundColor(.white.opacity(0.6))
        }
    }

    /// Non-actionable explanation. Only ever shown for a friend who genuinely
    /// has a break we can't cover — never as blanket chrome.
    private func infoPill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: style == .compact ? 10 : 11, weight: .semibold, design: .rounded))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(.white.opacity(0.45))
        .padding(.horizontal, style == .compact ? 11 : 14)
        .padding(.vertical, style == .compact ? 6 : 8)
        .frame(maxWidth: style == .compact ? nil : .infinity, alignment: .leading)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.04))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    private func savedPill(_ streak: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .bold))
            Text("Saved · \(streak)-day streak")
                .font(.system(size: style == .compact ? 11 : 12, weight: .heavy, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(.green)
        .padding(.horizontal, style == .compact ? 11 : 14)
        .padding(.vertical, style == .compact ? 6 : 9)
        .frame(maxWidth: style == .compact ? nil : .infinity)
        .background(Capsule().fill(Color.green.opacity(0.14)))
    }

    @ViewBuilder
    private func pill<Content: View>(
        background: LinearGradient?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, style == .compact ? 11 : 14)
            .padding(.vertical, style == .compact ? 6 : 7)
            .frame(maxWidth: style == .compact ? nil : .infinity)
            .background {
                if let background {
                    Capsule().fill(background)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                }
            }
    }

    // MARK: - Confirmation copy

    /// Re-runs the task when the friend changes OR the host hands down a fresh
    /// preloaded rescue (e.g. the status refresh drops one that's been saved).
    private var taskKey: String {
        "\(friendId)|\(preloaded?.missed_date ?? "")|\(preloaded == nil ? "fetch" : "given")"
    }

    private var confirmationTitle: String {
        "Save \(friendName)'s streak?"
    }

    private var confirmationMessage: String {
        guard case .available(let status) = model.phase else { return "" }
        var lines: [String] = []
        let missed = SaveFriendStreakView.dayLabel(status.missed_date)
        lines.append(
            "You'll spend your Streak Assist to cover \(missed) — the day \(friendName) missed — bringing them back to a \(status.streakAfterSave)-day streak."
        )
        if status.self_recovery == "double_down" {
            lines.append("\(friendName) can still win this back themselves today with a Double Down run, so your Assist may not be needed.")
        } else if status.self_recovery == "streak_save" {
            lines.append("\(friendName) is holding a Streak Save that will cover this automatically tomorrow morning, so your Assist may not be needed.")
        }
        lines.append("Streak Assists are earned by banking 20 miles beyond your own daily goal.")
        return lines.joined(separator: "\n\n")
    }

    /// "1 day" / "5 days" — a rescue is regularly worth exactly one day, and
    /// "1 days" on the button looked like a bug in its own right.
    static func dayCount(_ n: Int) -> String {
        "\(n) day\(n == 1 ? "" : "s")"
    }

    /// "Sunday, Jul 26" from a yyyy-MM-dd local date, or "the missed day".
    static func dayLabel(_ isoDay: String?) -> String {
        guard let isoDay else { return "the missed day" }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = parser.date(from: isoDay) else { return isoDay }
        let out = DateFormatter()
        out.dateFormat = "EEEE, MMM d"
        out.timeZone = TimeZone(secondsFromGMT: 0)
        return out.string(from: date)
    }

    private func save() {
        // Explicit @MainActor: `onSaved` hosts mutate @State (the profile's
        // toast, the row's saved-chip set) and this isn't called from an
        // isolated context.
        Task { @MainActor in
            let restored = await model.save(friendId: friendId)
            if let restored { onSaved(restored) }
        }
    }
}

/// Fetch + spend state for one friend's rescue. Kept off the hosting views so
/// the profile and the friends list can't drift apart on when they refresh.
@MainActor
final class SaveFriendStreakModel: ObservableObject {
    enum Phase {
        case idle
        /// Nothing to rescue (or we couldn't tell) — the CTA stays out of the way.
        case unavailable
        /// They DO have a coverable miss, but their build predates streak
        /// tokens, so nothing can be written on their behalf.
        case friendNeedsUpdate
        /// Their streak IS broken, but no single covered day brings it back —
        /// a multi-day hole, or a miss older than the rescue window. Shown as
        /// an explanation, because silence here reads as a broken feature.
        case beyondRescue(multiDay: Bool)
        case available(FriendRescueStatus)
        case saving
        case saved(Int)
    }

    @Published private(set) var phase: Phase = .idle

    /// Resolves the phase at construction so the view never has to render an
    /// empty frame it can't recover from (see the init comment on the view).
    /// A host that already holds the rescue lands on its final phase with no
    /// async hop at all; the profile, which has nothing preloaded, starts its
    /// fetch here instead of waiting for a `.task` that will never fire.
    init(friendId: String, preloaded: FriendRescueStatus? = nil) {
        if let preloaded {
            phase = Self.resolvePhase(for: preloaded)
            return
        }
        Task { [weak self] in await self?.load(friendId: friendId) }
    }

    func load(friendId: String, preloaded: FriendRescueStatus? = nil) async {
        // A completed save is terminal for this view's lifetime — refetching
        // would flip it back to "nothing to rescue" and blink the chip away.
        if case .saved = phase { return }
        if let preloaded {
            phase = Self.resolvePhase(for: preloaded)
            return
        }
        do {
            let status = try await StreakFeatureService.rescueStatus(friendId: friendId)
            phase = Self.resolvePhase(for: status)
        } catch {
            print("[SaveStreak] rescue status failed: \(error.localizedDescription)")
            phase = .unavailable
        }
    }

    private static func resolvePhase(for status: FriendRescueStatus) -> Phase {
        if status.available { return .available(status) }
        if status.friendNotEnrolled { return .friendNeedsUpdate }
        switch status.reason {
        case "gap_too_wide": return .beyondRescue(multiDay: true)
        case "window_passed": return .beyondRescue(multiDay: false)
        default: return .unavailable
        }
    }

    /// Returns the restored streak on success, nil on failure.
    func save(friendId: String) async -> Int? {
        guard case .available(let status) = phase else { return nil }
        phase = .saving
        do {
            let result = try await StreakFeatureService.assist(friendId: friendId)
            let restored = result.restored_streak ?? status.streakAfterSave
            phase = .saved(restored)
            MADHaptics.success()
            // Meters and the friends-list rescue list both move after a spend.
            await StreakTokensState.shared.refreshStatus()
            return restored
        } catch {
            // Someone else may have saved them first, or the window closed —
            // re-read rather than leaving a CTA that can't succeed.
            print("[SaveStreak] assist failed: \(error.localizedDescription)")
            MADHaptics.warning()
            phase = .idle
            await load(friendId: friendId)
            await StreakTokensState.shared.refreshStatus()
            return nil
        }
    }
}
