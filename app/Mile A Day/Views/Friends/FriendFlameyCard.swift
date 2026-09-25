import SwiftUI

// A FRIEND's Flamey, on their profile. Fun-only on BOTH sides: the server
// enables the `flamey` block only for a Fun target seen by an accepted friend,
// and this card draws nothing unless the VIEWER is Fun too. Tapping him is a
// poke that sends a real nudge (`POST /friends/:id/nudge {"source":"flamey"}`),
// and its answer is spoken in HIS bubble rather than a toast.

// MARK: - Facts

/// Everything a friend's Flamey is dressed from, decoded once from the
/// profile's `flamey` block. nil = no Flamey (block absent on an older server,
/// `enabled: false`, or the target isn't Fun).
struct FriendFlameyFacts: Equatable {
    let ownerName: String
    let longestStreak: Int
    let earnedBadgeIds: Set<String>
    let signupDate: Date?
    /// Everything they own, as far as this block tells us: the server's
    /// `owned_item_ids` when it sends them, else what the medals it does send
    /// (holidays) and the longest streak imply — plus anything their Closet
    /// choice names, which the server only serves when it is owned.
    let owned: Set<FlameyItem>
    /// Their Closet choice (`look`, the wire `{slot: id}`); absent = basic —
    /// a friend's Flamey wears exactly what THEY picked.
    let choice: FlameyLookChoice
    /// What they named him (`flamey.name`); nil = "Flamey" (or an older
    /// server that doesn't send it).
    let flameyName: String?

    init?(block: FlameyProfileBlock?, ownerName: String) {
        guard let block, block.enabled == true else { return nil }
        self.ownerName = ownerName
        longestStreak = max(0, block.longest_streak ?? 0)
        // Holiday medals travel as keys; the wardrobe unlocks by badge id.
        earnedBadgeIds = Set((block.holiday_keys ?? []).compactMap { HolidayKey(rawValue: $0)?.badgeId })
        signupDate = block.signup_date.flatMap(Self.parseDay)
        let choice = FlameyLookChoice(wire: block.look ?? [:])
        self.choice = choice
        let trimmed = block.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        flameyName = (trimmed?.isEmpty == false) ? trimmed : nil
        var owned = FlameyWardrobe.owned(
            earnedBadgeIds: earnedBadgeIds.union(FlameyWardrobe.impliedBadgeIds(longestStreak: longestStreak)))
        owned.formUnion((block.owned_item_ids ?? []).compactMap(FlameyItem.init(rawValue:)))
        owned.formUnion(choice.items)
        self.owned = owned
    }

    /// "2025-06-13" (their own calendar day) → local noon that day, so the
    /// anniversary's month/day comparison can't slip across a timezone.
    static func parseDay(_ raw: String) -> Date? {
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return Calendar.current.date(from: components)
    }

    /// The card is a SMALL surface (`.compact`): colour, head, eyes, chest,
    /// feet, costume, standing on the ground. The wardrobe sheet passes
    /// `.full`.
    func look(mood: FlameMood.Kind?, date: Date = Date(), detail: FlameyRenderDetail = .compact) -> FlameyLook {
        let props = mood.map { FlameMood(kind: $0, streak: 0).props } ?? []
        return FlameyLook.resolve(owned: owned, choice: choice, date: date, mood: props,
                                  signupDate: signupDate, detail: detail)
    }

    /// Owned for good, in Closet order — the always-his starters aren't
    /// "unlocked" by anything, so they aren't listed.
    var unlocked: [FlameyItem] {
        FlameyItem.closet.filter { owned.contains($0) && $0.unlock != .always }
    }

    /// "Aaron's" / "James'".
    var possessive: String {
        ownerName.hasSuffix("s") ? "\(ownerName)’" : "\(ownerName)’s"
    }

    /// His name — "Sparky", else "Flamey".
    var mascotName: String { flameyName ?? "Flamey" }

    /// "Aaron's Sparky" (or "Aaron's Flamey") — the card's title.
    var title: String { "\(possessive) \(mascotName)" }

    /// The one thing worth naming under him today: the day's outfit if he's
    /// in one, else a costume, else his hat, then colour, shoes, eyes, chest.
    func headlineItem(in look: FlameyLook) -> FlameyItem? {
        if let dayItem = look.items.first(where: { $0.isHolidayOutfit }) { return dayItem }
        for slot in [FlameySlot.costume, .head, .color, .feet, .eyes, .chest] {
            if let item = look[slot], !item.isMoodProp, item != .classic { return item }
        }
        return nil
    }
}

extension FlameyItem {
    /// A glyph for captions and the wardrobe list — one per FAMILY (holiday
    /// outfits keep their own), so the list reads by what earned it.
    var flairEmoji: String {
        switch self {
        case .moodShades, .classicShades: return "😎"
        case .partyHat: return "🥳"
        case .nightcap: return "😴"
        case .crown: return "👑"
        case .pumpkinSuit: return "🎃"
        case .santaHat: return "🎅"
        case .holidayScarf: return "🧣"
        case .starGlasses: return "🤩"
        case .heartBopper: return "💘"
        case .leprechaunHat: return "☘️"
        case .bunnyEars: return "🐰"
        case .starHat: return "⭐️"
        case .turkeyFeathers: return "🦃"
        case .countdownHat: return "🎉"
        case .ghostSheet, .friendlyGhost: return "👻"
        case .astronautHelmet: return "🧑‍🚀"
        case .polaroid: return "📸"
        default: break
        }
        switch family {
        case .streakDays, .starter: return "🔥"
        case .lifetimeMiles, .firsts: return "🧢"
        case .pace: return "👟"
        case .dailyChallenges: return "👓"
        case .weeklyChallenges: return "🏅"
        case .competitionsEntered, .competitionsWon: return "🦸"
        case .organizer: return "🏁"
        case .hypes: return "📣"
        case .distanceInADay: return "✨"
        case .buddyWalks: return "🐾"
        case .ghosts: return "👻"
        case .stories: return "🎬"
        case .nudges: return "💬"
        case .holidays: return "🎁"
        case .mood: return "🙂"
        }
    }

    /// The caption under him ("Crown", "Pumpkin Suit").
    var captionName: String { displayName }

    /// How it was earned, in the wardrobe list.
    var earnedLine: String {
        if case .badge(let id) = unlock, let key = HolidayKey(badgeId: id) {
            return "\(key.medalName) medal · \(key.holidayName)"
        }
        return unlockCopy
    }
}

// MARK: - Their day → his mood

enum FriendFlameyDay {
    /// What their Flamey is feeling, from what the profile knows about their
    /// day. Their LOCAL hour isn't known, so there is no sleepy/bedtime here
    /// — only progress, done, and at-risk.
    static func mood(streak: Int, todayMiles: Double?, goalMiles: Double,
                     isDone: Bool, savedToday: Bool, now: Date = Date()) -> FlameMood.Kind {
        let goal = max(goalMiles, 0.01)
        let progress = min(max((todayMiles ?? 0) / goal, 0), 1)
        if isDone { return FlameMood.isMilestone(streak) ? .party : .done }
        if streak == 0, progress <= 0.05 { return .unlit }
        if progress >= 0.8 { return .almost }
        if progress >= 0.5 { return .halfway }
        if progress > 0.05 { return .going }
        // At risk: a live streak, nothing banked, no token holding the day,
        // and late on the viewer's clock (the best local clock we have).
        let hour = Calendar.current.component(.hour, from: now)
        if streak > 0, !savedToday, hour >= 20 { return .nervous }
        return .ready
    }

    static func health(for kind: FlameMood.Kind) -> FlameHealth {
        switch kind {
        case .unlit: return .dead
        case .done, .party: return .blazing
        case .nervous: return .dimming
        default: return .healthy
        }
    }

    /// The card's headline, said ABOUT them.
    static func headline(_ kind: FlameMood.Kind, streak: Int) -> String {
        switch kind {
        case .unlit: return "Waiting to be lit"
        case .done: return "Mile done today"
        case .party: return "\(streak) days — party!"
        case .almost: return "So close to the mile"
        case .halfway: return "Halfway there"
        case .going: return "On the move"
        case .nervous: return "Streak on the line"
        default: return "Ready for today's mile"
        }
    }
}

// MARK: - Poke → nudge

/// The ONE request a poke can make. Mirrors the plain nudge endpoint with
/// `source: "flamey"`, so it spends the same once-a-day cooldown.
enum FlameyPoke {
    enum Outcome: Equatable {
        case sent
        /// 429 — the shared daily nudge is already spent.
        case cooldown
        /// 400 "already completed" — their mile is in.
        case alreadyWalked
        /// 403 flamey_unavailable — one side isn't Fun any more.
        case unavailable
        case failed

        /// What he says about it.
        var line: String {
            switch self {
            case .sent: return "Nudge sent! 🔥"
            case .cooldown: return "Already poked today"
            case .alreadyWalked: return "They already walked!"
            case .unavailable: return "Hmm, not now"
            case .failed: return "Couldn't reach them"
            }
        }
    }

    static func send(to friendId: String) async -> Outcome {
        guard TokenStore.hasTokens,
              let body = try? JSONSerialization.data(withJSONObject: ["source": "flamey"]) else { return .failed }
        do {
            _ = try await APIClient.fancyFetch(endpoint: "/friends/\(friendId)/nudge", method: .POST,
                                               body: body, responseType: FriendNudgeResponse.self)
            return .sent
        } catch let error as APIError {
            switch error {
            case .rateLimited: return .cooldown
            case .badRequest(let message):
                return message.localizedCaseInsensitiveContains("completed") ? .alreadyWalked : .failed
            case .apiError(let message):
                return message == "flamey_unavailable" ? .unavailable : .failed
            default: return .failed
            }
        } catch {
            return .failed
        }
    }
}

// MARK: - The card

/// "Aaron's Flamey": their Flamey in their look and today's mood, a line on
/// how their day is going, what he's wearing (tap → the wardrobe) and the
/// poke. Sits at the top of a friend's Activity tab.
struct FriendFlameyCard: View {
    let friendId: String
    let facts: FriendFlameyFacts
    let streak: Int
    let todayMiles: Double?
    let goalMiles: Double
    let isDone: Bool
    let savedToday: Bool
    /// The viewer already spent today's nudge on them (plain or Flamey).
    let alreadyNudged: Bool
    /// A nudge went out — the host mirrors it onto its own nudge state.
    var onNudged: () -> Void = {}
    /// 403 flamey_unavailable — the host hides the card.
    var onUnavailable: () -> Void = {}
    /// A line held in his bubble from the start — SwiftUI previews and
    /// snapshot renders only; the live card always passes nil.
    var previewQuip: String? = nil

    @AppStorage(DashboardStylePreference.key) private var viewerStyle = DashboardStyle.modern.rawValue
    @State private var showWardrobe = false

    // Poke state machine (see `poke()`).
    @State private var pokedAt: Date?
    @State private var pokeQuip: String?
    @State private var clearTask: Task<Void, Never>?
    @State private var sending = false
    @State private var settled: FlameyPoke.Outcome?
    @State private var tapCount = 0

    private static let buddySize: CGFloat = 118

    var body: some View {
        if viewerStyle == DashboardStyle.fun.rawValue {
            let kind = FriendFlameyDay.mood(streak: streak, todayMiles: todayMiles, goalMiles: goalMiles,
                                            isDone: isDone, savedToday: savedToday)
            let look = facts.look(mood: kind)
            HStack(alignment: .bottom, spacing: 14) {
                stage(kind: kind, look: look)
                info(kind: kind, look: look)
                    .padding(.bottom, 16)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardGlow)
            .profileCard()
            .sheet(isPresented: $showWardrobe) {
                FriendFlameyWardrobeSheet(facts: facts)
            }
        }
    }

    // MARK: Stage

    private func stage(kind: FlameMood.Kind, look: FlameyLook) -> some View {
        var mood = FlameMood(kind: kind, streak: streak)
        mood.pokedAt = pokedAt
        mood.pokeQuip = pokeQuip ?? previewQuip
        mood.holiday = look.holiday
        mood.isAnniversary = look.isAnniversary
        let size = Self.buddySize
        return ZStack(alignment: .bottom) {
            FlameyStageGround()
                .frame(width: size * 1.1, height: 14)
                .offset(y: 3)
            FlameBuddyView(health: FriendFlameyDay.health(for: kind), size: size, mood: mood, look: look)
                .frame(width: size, height: size)
        }
        // Headroom for the bubble, which draws above his tip — and for his
        // legs, which stand him taller when he wears shoes.
        .frame(width: size * 1.3, height: size + 62 + look.standLift * size, alignment: .bottom)
        .padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture { poke(kind: kind) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(facts.title)
        .accessibilityHint("Tap to poke. Sends \(facts.ownerName) a nudge.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Info column

    private func info(kind: FlameMood.Kind, look: FlameyLook) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(facts.title.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(Color(red: 1.0, green: 0.72, blue: 0.35))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(FriendFlameyDay.headline(kind, streak: streak))
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            wearingChip(look: look)
            HStack(spacing: 5) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 10, weight: .bold))
                    .accessibilityHidden(true)
                Text(hint)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(.white.opacity(0.45))
        }
    }

    private var hint: String {
        if isDone || settled == .alreadyWalked { return "Tap him to say hi" }
        if alreadyNudged || settled == .sent || settled == .cooldown { return "Poked today" }
        return "Tap him to poke \(facts.ownerName)"
    }

    @ViewBuilder
    private func wearingChip(look: FlameyLook) -> some View {
        let unlockedCount = facts.unlocked.count
        Button {
            MADHaptics.tap()
            showWardrobe = true
        } label: {
            HStack(spacing: 5) {
                if let item = facts.headlineItem(in: look) {
                    Text(item.flairEmoji)
                        .font(.system(size: 12))
                    Text(item.captionName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    Text("✨")
                        .font(.system(size: 12))
                    Text(unlockedCount == 0 ? "No gear yet" : "Wardrobe")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.white.opacity(0.4))
                    .accessibilityHidden(true)
            }
            .foregroundColor(.white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What \(facts.title) is wearing")
    }

    /// A warm ember glow behind him, inside the flat card chrome.
    private var cardGlow: some View {
        RadialGradient(
            colors: [Color.orange.opacity(0.20), Color(red: 0.8, green: 0.2, blue: 0.1).opacity(0.06), .clear],
            center: UnitPoint(x: 0.17, y: 0.72),
            startRadius: 4,
            endRadius: 150
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Poke

    /// A tap ALWAYS gets the squash, a haptic and a line. It sends a nudge
    /// at most once per visit — and never when we already know the answer:
    ///
    ///   done today      → "They already walked!" (no request)
    ///   nudged today    → "Already poked today" (no request)
    ///   otherwise       → "Go walk!", ONE request, then the answer replaces
    ///                     the line in his bubble; 403 hides the card
    ///   later taps      → animate + a quip; a failed send may retry
    private func poke(kind: FlameMood.Kind) {
        pokedAt = Date()
        tapCount += 1
        if sending {
            MADHaptics.tap()
            return
        }
        if let settled {
            MADHaptics.tap()
            // Every third tap restates the answer, so it isn't lost for good
            // once the bubble clears.
            say(tapCount % 3 == 0 ? settled.line : (Self.idleQuips.randomElement() ?? "Hey!"))
            return
        }
        if isDone {
            MADHaptics.success()
            settle(.alreadyWalked)
            say(FlameyPoke.Outcome.alreadyWalked.line, for: 2.8)
            return
        }
        if alreadyNudged {
            MADHaptics.warning()
            settle(.cooldown)
            say(FlameyPoke.Outcome.cooldown.line, for: 2.8)
            return
        }
        MADHaptics.emphasis()
        sending = true
        say(["Hey!", "Go walk!", "Mile time!"].randomElement() ?? "Go walk!", for: 6)
        Task { @MainActor in
            let outcome = await FlameyPoke.send(to: friendId)
            sending = false
            switch outcome {
            case .sent:
                MADHaptics.success()
                settle(.sent)
                onNudged()
            case .cooldown, .alreadyWalked:
                MADHaptics.warning()
                settle(outcome)
            case .unavailable:
                // One side isn't Fun any more: no Flamey, no poke.
                onUnavailable()
                return
            case .failed:
                MADHaptics.error()
                // Not settled — the next tap may try again.
            }
            say(outcome.line, for: 2.8)
        }
    }

    private static let idleQuips = ["Hehe", "Boop!", "Hey!", "Again?", "Careful, hot"]

    private func settle(_ outcome: FlameyPoke.Outcome) {
        settled = outcome
    }

    private func say(_ line: String, for seconds: Double = 2.4) {
        pokeQuip = line
        clearTask?.cancel()
        clearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            guard !Task.isCancelled else { return }
            pokeQuip = nil
        }
    }
}

/// The little patch of warm ground he stands on.
struct FlameyStageGround: View {
    var body: some View {
        Ellipse()
            .fill(RadialGradient(
                colors: [Color.orange.opacity(0.30), Color.black.opacity(0.30), .clear],
                center: .center, startRadius: 1, endRadius: 60))
            .blur(radius: 3)
            .accessibilityHidden(true)
    }
}

// MARK: - Wardrobe (read-only)

/// Everything their Flamey owns, read-only. The wardrobe proper (picking
/// what he wears) will grow out of this list.
struct FriendFlameyWardrobeSheet: View {
    let facts: FriendFlameyFacts
    @Environment(\.dismiss) private var dismiss
    /// Your own Closet, opened ON this sheet: the friend's profile may itself
    /// be a sheet, and a cover raised from MainTabView's root can't present
    /// over one. Done lands back here.
    @State private var ownCloset: FlameyClosetLink.Request?

    var body: some View {
        ScrollView {
            content
            dressYourOwn
                .padding(.horizontal, MADTheme.Spacing.screenGutter)
                .padding(.bottom, 28)
        }
        .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(item: $ownCloset) { request in
            // Presented over a friend's sheet: "where to earn it" can't leave
            // for another tab from here, so locked cards say where instead.
            FlameyClosetScreen(request: request, canRoute: false)
        }
    }

    /// "Dress your own Flamey" — the viewer is on Fun (the card only shows
    /// when both sides are), so their Closet is always there to open.
    private var dressYourOwn: some View {
        Button {
            MADHaptics.action()
            ownCloset = FlameyClosetLink.Request()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "hanger")
                    .madFont(size: 14, weight: .bold, maxScale: 1.3)
                    .accessibilityHidden(true)
                // Yours has a name of his own, maybe: "Dress up Sparky".
                Text(FlameyFacts.name.map { "Dress up \($0)" } ?? "Dress your own Flamey")
                    .madFont(size: 15, weight: .heavy, design: .rounded)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(FlameyNameRules.possessive(FlameyFacts.displayName)) Closet")
    }

    /// The sheet's contents, outside the ScrollView (also what a snapshot
    /// render draws — ImageRenderer can't see into a ScrollView).
    var content: some View {
        let look = facts.look(mood: nil, detail: .full)
        let owned = facts.unlocked
        let total = FlameyItem.closet.filter { $0.unlock != .always }.count
        return VStack(spacing: 18) {
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        FlameyStageGround()
                            .frame(width: 140, height: 16)
                            .offset(y: 4)
                        FlameBuddyView(health: .healthy, size: 120, still: true, look: look)
                            .frame(width: 120, height: 120)
                    }
                    .frame(height: 150, alignment: .bottom)
                    Text(facts.title)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(owned.count) of \(total) unlocked")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .monospacedDigit()
                }
                .padding(.top, 8)

                if owned.isEmpty {
                    Text("Nothing yet — a 3-day streak turns him Ember.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(owned.enumerated()), id: \.element) { index, cosmetic in
                            if index > 0 {
                                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                                    .padding(.leading, 60)
                            }
                            row(cosmetic, wearing: look.wears(cosmetic))
                        }
                    }
                    .profileCard()
                }
            }
            .padding(.horizontal, MADTheme.Spacing.screenGutter)
            .padding(.bottom, 24)
    }

    private func row(_ cosmetic: FlameyItem, wearing: Bool) -> some View {
        HStack(spacing: 12) {
            Text(cosmetic.flairEmoji)
                .font(.system(size: 20))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(cosmetic.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(cosmetic.earnedLine)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            if wearing {
                Text("WEARING")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(0.6)
                    .foregroundColor(.black.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(red: 1.0, green: 0.72, blue: 0.35)))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
