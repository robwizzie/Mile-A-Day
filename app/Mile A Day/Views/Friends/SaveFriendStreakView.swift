import SwiftUI

/// Donating a mile to a friend's Streak Assist, as a self-contained CTA.
///
/// An Assist costs two things from two people: the FRIEND's held token, and one
/// mile this user ran past their own goal today. So this button never spends
/// anything on its own — it offers, and the friend accepts. States:
///
///  1. **Both halves in hand** → the "Donate a Mile · Saves N days" pill. N is
///     where the friend LANDS (`restored_streak`), not the run that ended at
///     the miss — those differ by every day they've kept since. Tapping opens a
///     confirmation naming the day it covers and that same number.
///  2. **Friend has a day, you're out of spare miles** → a locked pill saying
///     how much further to run, so "why don't I have the option" has a visible
///     answer instead of the CTA silently not rendering.
///  3. **Friend has a day but no token** → a muted line saying they need to
///     bank 20 miles past their own goal first.
///  4. **Offer already in flight** → "Mile offered", waiting on them.
///  5. **Friend's build is too old / nothing to cover** → an explanation, or
///     nothing at all.
///
/// The friend may still be holding a token that fixes this for free (an open
/// Double Down window, or a Streak Save the morning sweep will consume). That
/// doesn't hide the CTA — it's said plainly in the confirmation, and the donor
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
    /// Fired once the offer is made, with the streak it would restore.
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
            case .friendNeedsToken:
                infoPill(
                    icon: "lock.circle",
                    text: "\(friendName) hasn't banked a Streak Assist yet — they need 20 miles past their own goal to hold one"
                )
            case .beyondRescue(let multiDay):
                infoPill(
                    icon: "clock.arrow.circlepath",
                    text: multiDay
                        ? "\(friendName) has missed more than one day — a Streak Assist only covers a single miss"
                        : "\(friendName)'s miss is too old to rescue — Assists reach back 2 days"
                )
            case .available(let status):
                saveButton(status)
            case .needsMiles(let status):
                lockedPill(status)
            case .saving:
                pill(background: MADTheme.Colors.redGradient) {
                    ProgressView().tint(.white).scaleEffect(0.6)
                }
            case .offered:
                offeredPill()
            }
        }
        .task(id: taskKey) { await model.load(friendId: friendId, preloaded: preloaded) }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Donate My Mile") { save() }
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
                        Text("Donate a Mile")
                            .font(.system(size: style == .compact ? 11 : 12, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                        // Says where they LAND, not what's being spent. A bare
                        // "5 days" under the title reads as "this saves 5
                        // days"; the number is actually the streak they end up
                        // on — their run before the miss, plus the covered day,
                        // plus every day they've kept since.
                        Text("Saves \(Self.dayCount(status.streakAfterSave))")
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

    /// The friend is ready to be saved, but this user hasn't run their spare
    /// mile yet. Showing exactly how much further beats showing nothing: the
    /// absence of a CTA is otherwise indistinguishable from a broken feature —
    /// and unlike a 20-mile meter, this one is closable today.
    private func lockedPill(_ status: FriendRescueStatus) -> some View {
        let toGo = status.viewer_budget?.milesToNext ?? 1
        return pill(background: nil) {
            HStack(spacing: 6) {
                TokenMedallion(
                    kind: .assist,
                    held: false,
                    progress: max(0, min(1, 1 - toGo)),
                    size: style == .compact ? 18 : 20
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text("Donate a Mile")
                        .font(.system(size: style == .compact ? 11 : 12, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                    Text(String(format: "%.2f mi further today", toGo))
                        .font(.system(size: style == .compact ? 9 : 10, weight: .bold, design: .rounded))
                        .opacity(0.7)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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

    /// The mile is committed and it's their move now — deliberately NOT a
    /// "Saved!" checkmark, which is the lie the one-sided version used to tell.
    private func offeredPill() -> some View {
        HStack(spacing: 5) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 12, weight: .bold))
            Text("Mile offered")
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
        "\(friendId)|\(preloaded?.target_date ?? "")|\(preloaded == nil ? "fetch" : "given")"
    }

    private var confirmationTitle: String {
        "Donate a mile to \(friendName)?"
    }

    private var confirmationMessage: String {
        guard case .available(let status) = model.phase else { return "" }
        var lines: [String] = []
        let day = SaveFriendStreakView.dayLabel(status.target_date)
        lines.append(
            status.isToday
                ? "One of the miles you ran past your goal today goes to \(friendName). If they accept, it banks today for them and their streak stays at \(status.streakAfterSave) days."
                : "One of the miles you ran past your goal today goes to \(friendName). If they accept, it covers \(day) — the day they missed — bringing them back to a \(status.streakAfterSave)-day streak."
        )
        lines.append("They spend their own Streak Assist to take it, so nothing happens until they say yes.")
        if status.self_recovery == "double_down" {
            lines.append("\(friendName) can still win this back themselves today with a Double Down run, so your mile may not be needed.")
        } else if status.self_recovery == "streak_save" {
            lines.append("\(friendName) is holding a Streak Save that will cover this automatically tomorrow morning, so your mile may not be needed.")
        }
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
        // toast, the row's offered-chip set) and this isn't called from an
        // isolated context.
        Task { @MainActor in
            let restored = await model.offerMile(friendId: friendId)
            if let restored { onSaved(restored) }
        }
    }
}

/// Fetch + offer state for one friend's rescue. Kept off the hosting views so
/// the profile and the friends list can't drift apart on when they refresh.
@MainActor
final class SaveFriendStreakModel: ObservableObject {
    enum Phase {
        case idle
        /// Nothing to cover (or we couldn't tell) — the CTA stays out of the way.
        case unavailable
        /// They DO have a coverable day, but their build predates streak
        /// tokens, so nothing can be written on their behalf.
        case friendNeedsUpdate
        /// They have a day in play but haven't banked an Assist to spend on
        /// it, so a donated mile would have nothing to pair with.
        case friendNeedsToken
        /// Their streak IS broken, but no single covered day brings it back —
        /// a multi-day hole, or a miss older than the rescue window. Shown as
        /// an explanation, because silence here reads as a broken feature.
        case beyondRescue(multiDay: Bool)
        /// Both halves in hand — the live CTA.
        case available(FriendRescueStatus)
        /// Their half is ready; this user just hasn't run the spare mile yet.
        case needsMiles(FriendRescueStatus)
        case saving
        /// Mile committed, waiting on them.
        case offered
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
        // A sent offer is terminal for this view's lifetime — refetching would
        // flip it back to "nothing to cover" and blink the chip away.
        if case .offered = phase { return }
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
        if status.alreadyOffered { return .offered }
        if status.available { return .available(status) }
        if status.friendNotEnrolled { return .friendNeedsUpdate }
        // Order matters: both halves can be missing at once, and the one the
        // USER can do something about today is the one worth showing.
        if status.needsMoreMiles { return .needsMiles(status) }
        if status.friendHasNoToken { return .friendNeedsToken }
        switch status.reason {
        case "gap_too_wide": return .beyondRescue(multiDay: true)
        case "window_passed": return .beyondRescue(multiDay: false)
        default: return .unavailable
        }
    }

    /// Commits one of today's spare miles. Returns the streak the friend would
    /// land on, or nil on failure — nothing is covered until THEY accept.
    func offerMile(friendId: String) async -> Int? {
        guard case .available(let status) = phase else { return nil }
        phase = .saving
        do {
            _ = try await StreakFeatureService.offerAssist(friendId: friendId)
            phase = .offered
            MADHaptics.success()
            // The budget and the donatable list both move after an offer.
            await StreakTokensState.shared.refreshStatus()
            return status.streakAfterSave
        } catch {
            // They may have run the day, or someone else's mile got there
            // first — re-read rather than leaving a CTA that can't succeed.
            print("[SaveStreak] offer failed: \(error.localizedDescription)")
            MADHaptics.warning()
            phase = .idle
            await load(friendId: friendId)
            await StreakTokensState.shared.refreshStatus()
            return nil
        }
    }
}
