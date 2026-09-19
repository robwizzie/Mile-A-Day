import SwiftUI

// MARK: - Token identity (one source of truth for look & copy)

enum StreakTokenKind {
    case doubleDown, save, assist

    /// Backend raw kind — the key used by meter-gain chips and the unlock
    /// event list (inverse of `from(raw:)`).
    var raw: String {
        switch self {
        case .doubleDown: return "double_down"
        case .save: return "streak_save"
        case .assist: return "streak_assist"
        }
    }

    var title: String {
        switch self {
        case .doubleDown: return "Double Down"
        case .save: return "Streak Save"
        case .assist: return "Streak Assist"
        }
    }

    var icon: String {
        switch self {
        case .doubleDown: return "bolt.fill"
        case .save: return "snowflake"
        case .assist: return "lifepreserver"
        }
    }

    /// Coin-face gradient. Kept saturated and MAD-branded: ember for effort,
    /// ice for the freeze, brand red for the friend rescue.
    var gradient: [Color] {
        switch self {
        case .doubleDown:
            return [Color(red: 1.0, green: 0.62, blue: 0.20),
                    Color(red: 0.86, green: 0.28, blue: 0.08)]
        case .save:
            return [Color(red: 0.45, green: 0.78, blue: 1.0),
                    Color(red: 0.12, green: 0.42, blue: 0.85)]
        case .assist:
            return [Color(red: 0.95, green: 0.35, blue: 0.55),
                    MADTheme.Colors.madRed]
        }
    }

    var tint: Color {
        switch self {
        case .doubleDown: return .orange
        case .save: return MADTheme.Colors.walkBlue
        case .assist: return MADTheme.Colors.madRed
        }
    }

    var what: String {
        switch self {
        case .doubleDown:
            return "Miss a day? Run 2× your goal the next day and yesterday still counts."
        case .save:
            return "Life happens — if you miss a day and can't Double Down, this covers it automatically."
        case .assist:
            return "Covers a day you missed — but only when a friend donates a mile they ran past their own goal. Ask, and it's theirs to give."
        }
    }

    var howToEarn: String {
        switch self {
        case .doubleDown:
            return "Complete your mile on 14 days — runs or walks both count."
        case .save:
            return "Run your full mile on 7 days. Running only — walks don't tick this one."
        case .assist:
            return "One every 30 days — the countdown starts the day you spend one, so a brand-new account is already holding its first. Holding one is half of a save; a friend's spare mile is the other half."
        }
    }

    /// WHO has to do something for this token to fire.
    ///
    /// The single most confusing thing about the set, by a distance: two of
    /// them spend themselves and one cannot be spent alone, and until this
    /// was stated the app only ever showed a meter — so a user holding three
    /// tokens had no idea which of them they were supposed to *do* something
    /// with. It's a badge rather than a sentence because it belongs on every
    /// surface the token appears on, including the 100pt-wide dashboard tile.
    var usage: TokenUsage {
        switch self {
        case .doubleDown: return .youRunIt
        case .save: return .automatic
        case .assist: return .withAFriend
        }
    }

    /// The instruction, in the imperative where there is one to give.
    var howToUse: String {
        switch self {
        case .doubleDown:
            return "Nothing to tap. Miss a day, then run double your goal before the next midnight — we back-fill the missed day as soon as the miles sync."
        case .save:
            return "Nothing to tap and nothing to decide. Miss a day you don't run back, and this spends itself the next morning. We always tell you when it does."
        case .assist:
            return "The only one you choose. Tap “Ask a friend” when your streak is on the line, or hand someone a mile you ran past your own goal. It spends only once you've both said yes."
        }
    }

    /// When, exactly — the question a meter can never answer.
    var whenItFires: String {
        switch self {
        case .doubleDown: return "The day after a miss, the moment your second mile lands."
        case .save: return "The morning after a miss you didn't run back."
        case .assist: return "The moment the other person accepts."
        }
    }
}

/// Who acts for a token to be spent. Three tokens, three completely different
/// answers — and the app used to state none of them.
enum TokenUsage {
    /// Spent for you. You are told, never asked.
    case automatic
    /// Yours to earn back by running; no button exists.
    case youRunIt
    /// Needs a second person, so there is something to tap.
    case withAFriend

    var label: String {
        switch self {
        case .automatic: return "AUTOMATIC"
        case .youRunIt: return "YOU RUN IT"
        case .withAFriend: return "YOU + A FRIEND"
        }
    }

    var icon: String {
        switch self {
        case .automatic: return "sparkles"
        case .youRunIt: return "figure.run"
        case .withAFriend: return "person.2.fill"
        }
    }

    /// One line under the badge, for surfaces with room for it.
    var summary: String {
        switch self {
        case .automatic: return "Spends itself when you need it."
        case .youRunIt: return "Earn the day back by running."
        case .withAFriend: return "Ask, or be asked. Both must agree."
        }
    }
}

/// The "who acts" badge. Deliberately monochrome-on-glass rather than tinted
/// per token: it answers a question ABOUT the token, so tinting it the
/// token's own colour would fold it back into the decoration it needs to
/// stand apart from.
struct TokenUsageBadge: View {
    let usage: TokenUsage
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: usage.icon)
                .font(.system(size: compact ? 7 : 9, weight: .black))
                .accessibilityHidden(true)
            Text(usage.label)
                .font(.system(size: compact ? 8 : 10, weight: .black, design: .rounded))
                .tracking(0.5)
        }
        .foregroundColor(.white.opacity(0.85))
        .lineLimit(1)
        // The dashboard tile is ~94pt of usable width and "YOU + A FRIEND"
        // is the longest label, so the compact badge has to be allowed to
        // shrink rather than push the three tiles out of the row.
        .minimumScaleFactor(compact ? 0.6 : 0.8)
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, compact ? 2.5 : 4)
        .background(Capsule().fill(Color.white.opacity(0.10)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .accessibilityLabel("Used: \(usage.label.lowercased())")
    }
}

// MARK: - Token medallion (the token itself — a minted coin, not an emoji)

/// The canonical rendering of a token everywhere it appears: a coin with a
/// gradient face, top-light sheen, inner ring, and an engraved SF Symbol.
/// EARNED  → full color, gold rim, soft glow.
/// EARNING → dimmed face with a progress arc filling the rim.
struct TokenMedallion: View {
    let kind: StreakTokenKind
    var held: Bool = false
    /// 0…1 earn progress; ignored when held.
    var progress: Double = 0
    var size: CGFloat = 44

    private var gold: Color { Color(red: 1.0, green: 0.84, blue: 0.35) }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: kind.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.45), .clear],
                        center: .init(x: 0.32, y: 0.25),
                        startRadius: 0,
                        endRadius: size * 0.75
                    )
                )

            Circle()
                .fill(Color.black.opacity(0.10))
                .padding(size * 0.22)

            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: max(1, size * 0.035))
                .padding(size * 0.10)

            tokenGlyph
        }
        .frame(width: size, height: size)
        .saturation(held ? 1 : 0.45)
        .opacity(held ? 1 : 0.85)
        .overlay(
            // Rim: solid gold when earned; progress arc while earning.
            Group {
                if held {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [gold, kind.tint.opacity(0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(1.5, size * 0.06)
                        )
                    Circle()
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: max(0.8, size * 0.018))
                        .padding(size * 0.08)
                } else {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: max(1.5, size * 0.05))
                    Circle()
                        .trim(from: 0, to: max(0.02, min(progress, 1)))
                        .stroke(
                            kind.tint,
                            style: StrokeStyle(lineWidth: max(1.5, size * 0.05), lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(max(0.75, size * 0.025))
                }
            }
        )
        .shadow(color: held ? kind.tint.opacity(0.55) : .clear, radius: size * 0.18)
        .accessibilityLabel("\(kind.title)\(held ? ", available" : "")")
    }

    @ViewBuilder
    private var tokenGlyph: some View {
        switch kind {
        case .doubleDown:
            Text("2x")
                .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
        case .save, .assist:
            Image(systemName: kind.icon)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
        }
    }
}

// MARK: - Pure Flame badge (natural streak)

/// The "never needed a rescue" seal — shown beside the username when the
/// current streak is 100% natural (no Save, Double Down, or received Assist
/// inside it). Mile A Day's answer to a verified check: a gold diamond seal.
struct PureFlameBadge: View {
    var size: CGFloat = 22

    var body: some View {
        let diamondSize = size * 0.76
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.90, blue: 0.45),
                            Color(red: 0.92, green: 0.58, blue: 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: diamondSize, height: diamondSize)
                .rotationEffect(.degrees(45))
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: max(1, size * 0.05))
                .frame(width: diamondSize, height: diamondSize)
                .rotationEffect(.degrees(45))
            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.42, weight: .black))
                .foregroundColor(Color(red: 0.52, green: 0.22, blue: 0.02))
                .shadow(color: .white.opacity(0.35), radius: 1)
            if size >= 34 {
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.18, weight: .bold))
                    .foregroundColor(.white)
                    .offset(x: size * 0.26, y: -size * 0.26)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: gold.opacity(0.55), radius: size * 0.16)
        .accessibilityLabel("Natural streak — every day earned")
    }

    private var gold: Color { Color(red: 1.0, green: 0.84, blue: 0.35) }
}

// MARK: - Dashboard card

/// The tokens' home on the Dashboard: three minted medallions with earn
/// progress, always present while the feature is active (never dependent on
/// which week-view tab is selected). Renders nothing when the server gate is
/// off. Tapping opens the explainer.
struct StreakTokensCard: View {
    @ObservedObject var tokensState = StreakTokensState.shared
    /// Supplied by MainTabView's environment — the ask sheet lists friends.
    @EnvironmentObject private var friendService: FriendService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDetail = false
    @State private var showDonateSheet = false
    @State private var showAskSheet = false
    /// Drives the slow breathing pulse on earned medallions.
    @State private var pulse = false

    var body: some View {
        if let payload = tokensState.payload {
            Button {
                MADHaptics.tap()
                showDetail = true
            } label: {
                VStack(spacing: 15) {
                    // Quiet section header; the medallions carry the color.
                    HStack(spacing: 6) {
                        Text("Streak Tokens")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.72))
                        Spacer()
                        let ready = [
                            payload.double_down.held,
                            payload.streak_save.held,
                            payload.streak_assist.held,
                        ].filter { $0 }.count
                        Text(ready > 0 ? "\(ready) available" : "How they work")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(ready > 0 ? 0.72 : 0.55))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    HStack(alignment: .top, spacing: 12) {
                        medallionCell(
                            kind: .doubleDown,
                            held: payload.double_down.held,
                            progress: payload.double_down.fraction,
                            caption: payload.double_down.held
                                ? "Available"
                                : "\(Int(payload.double_down.progress))/\(Int(payload.double_down.target))"
                        )
                        medallionCell(
                            kind: .save,
                            held: payload.streak_save.held,
                            progress: payload.streak_save.fraction,
                            caption: payload.streak_save.held
                                ? "Available"
                                : "\(Int(payload.streak_save.progress))/\(Int(payload.streak_save.target))"
                        )
                        medallionCell(
                            kind: .assist,
                            held: payload.streak_assist.held,
                            progress: payload.streak_assist.fraction,
                            caption: payload.streak_assist.held
                                ? "Available"
                                : payload.streak_assist.assistCaption
                        )
                    }

                    // A token holding TODAY leads the card: it is the one
                    // thing on this screen that explains a streak number the
                    // rest of the dashboard's mileage doesn't account for.
                    if let today = payload.today_covered {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: SavedDayStyle.icon(for: today.kind))
                                .font(.system(size: 10, weight: .bold))
                                .padding(.top, 1)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(SavedDayStyle.todayHeadline(for: today)) — \(SavedDayStyle.credit(for: today))")
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text("Run your mile anyway and the token comes back.")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundColor(SavedDayStyle.tint.opacity(0.75))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .foregroundColor(SavedDayStyle.tint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if payload.streak_at_risk {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Missed yesterday — run 2× today to save your streak!")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // The two halves of an Assist, each shown only when this
                    // user is holding one of them: the token needs someone
                    // else's mile, and a spare mile needs someone else's token.
                    if let day = payload.my_savable_day {
                        assistActionRow(
                            icon: "hand.raised.fill",
                            tint: MADTheme.Colors.madRed,
                            text: day.isToday
                                ? "Ask a friend for a mile to bank today"
                                : "Ask a friend for a mile — back to \(day.restored_streak) days"
                        ) { showAskSheet = true }
                    }
                    let spare = tokensState.donationBudget?.remaining ?? 0
                    if spare > 0,
                       tokensState.assistableFriends.contains(where: { !$0.alreadyOffered }) {
                        assistActionRow(
                            icon: "figure.run",
                            tint: .green,
                            text: spare == 1
                                ? "You have a spare mile — save a friend's streak"
                                : "You have \(spare) spare miles — save a friend's streak"
                        ) { showDonateSheet = true }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            .background(tokenCardBackground(readyCount: readyCount(for: payload)))
            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDetail) {
                StreakTokensDetailView()
            }
            .sheet(isPresented: $showDonateSheet) {
                DonateMileSheet()
            }
            .sheet(isPresented: $showAskSheet) {
                if let day = tokensState.payload?.my_savable_day {
                    AskForMileSheet(savableDay: day, friendService: friendService)
                }
            }
        }
    }

    /// A tappable line inside the card. It's a Button nested in the card's own
    /// Button — SwiftUI routes the tap to the innermost one, so the rest of the
    /// card still opens the explainer.
    private func assistActionRow(
        icon: String,
        tint: Color,
        text: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(text)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.6)
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func readyCount(for payload: StreakFeaturesPayload) -> Int {
        [
            payload.double_down.held,
            payload.streak_save.held,
            payload.streak_assist.held,
        ].filter { $0 }.count
    }

    private func tokenCardBackground(readyCount: Int) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(red: 0.055, green: 0.050, blue: 0.058))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.05),
                                Color(red: 1.0, green: 0.56, blue: 0.20).opacity(0.06),
                                MADTheme.Colors.madRed.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                readyCount > 0 ? Color.white.opacity(0.14) : Color.white.opacity(0.08),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.16), radius: 14, x: 0, y: 7)
    }

    private func medallionCell(
        kind: StreakTokenKind, held: Bool, progress: Double, caption: String
    ) -> some View {
        VStack(spacing: 9) {
            TokenMedallion(kind: kind, held: held, progress: progress, size: 58)
                // Earned tokens breathe gently — alive, not static.
                .scaleEffect(held && pulse ? 1.014 : 1.0)
                .animation(
                    held
                        ? .easeInOut(duration: 2.2).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
                .onAppear { if !reduceMotion { pulse = true } }
                // Transient "+1 run day" chip when a fresh payload moved
                // this meter forward — the bar visibly ticks, not just sits.
                .overlay(alignment: .top) {
                    if let gain = tokensState.meterGains[kind.raw] {
                        Text(gain)
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(kind.tint))
                            .fixedSize()
                            .offset(y: -15)
                            .transition(
                                .scale(scale: 0.5).combined(with: .opacity)
                            )
                    }
                }
                .animation(
                    .spring(response: 0.4, dampingFraction: 0.7),
                    value: tokensState.meterGains
                )
            Text(kind.title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(held ? 0.95 : 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // "Who acts" instead of the old mood copy ("Get a boost when you
            // need it most"), which said nothing three times. This is the
            // question people actually had about a token they were holding.
            TokenUsageBadge(usage: kind.usage, compact: true)
                .opacity(held ? 1 : 0.65)
            Text(kind.usage.summary)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(held ? 0.70 : 0.46))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(minHeight: 28)
            Text(caption.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(held ? kind.tint : .white.opacity(0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(Color.black.opacity(0.22)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 190)
        .background(tokenTileBackground(kind: kind, held: held))
    }

    private func tokenTileBackground(kind: StreakTokenKind, held: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(red: 0.060, green: 0.055, blue: 0.066))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(kind.tint.opacity(held ? 0.12 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(kind.tint.opacity(held ? 0.46 : 0.18), lineWidth: 1)
            )
            .shadow(color: held ? kind.tint.opacity(0.24) : .clear, radius: 16, x: 0, y: 8)
    }
}

// MARK: - Full explainer sheet

/// What each token does, how it's earned, and where its meter stands — the
/// "easily known how to unlock and what they do" surface.
struct StreakTokensDetailView: View {
    @ObservedObject var tokensState = StreakTokensState.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showPureFlameInfo = false

    /// The receipts: every day a token actually carried.
    ///
    /// The tokens sheet explained how tokens are EARNED but never showed what
    /// they had DONE, so a user who knew a day was covered had nowhere to
    /// confirm it — and a short day on the week chart looked like a plain
    /// miss. Sourced from the era history the dashboard already warms, so this
    /// costs no extra request.
    @ViewBuilder
    private var savedDaysCard: some View {
        let saved = StreakErasStore.shared.response?.covered_days ?? []
        if !saved.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(SavedDayStyle.tint)
                    Text("Days your tokens saved")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(saved.count)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(SavedDayStyle.tint)
                }

                ForEach(saved.prefix(12), id: \.self) { day in
                    HStack(spacing: 10) {
                        Image(systemName: SavedDayStyle.icon(for: day.kind))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(SavedDayStyle.tint)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(SavedDayStyle.tint.opacity(0.15)))
                        Text(SavedDayStyle.formatDate(day.local_date))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer(minLength: 6)
                        SavedDayStyle.chip(for: day.kind)
                    }
                }

                if saved.count > 12 {
                    Text("+ \(saved.count - 12) more")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                }

                Text("These days count toward your streak. They show in blue on your week chart instead of as a missed day.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(MADTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(SavedDayStyle.tint.opacity(0.22), lineWidth: 1)
                    )
            )
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.md) {
                        if let payload = tokensState.payload {
                            if payload.streak_at_risk {
                                atRiskBanner(payload)
                            }
                            // Today first, when a token is holding it: this
                            // sheet is where someone lands after noticing a
                            // streak that went up beside a mile they know
                            // they haven't run.
                            if let today = payload.today_covered {
                                SavedTodayBanner(day: today, isSelf: true)
                            }

                            tokenCard(
                                kind: .doubleDown,
                                meter: StreakTokenMeter(
                                    progress: payload.double_down.progress,
                                    target: payload.double_down.target,
                                    held: payload.double_down.held,
                                    last_used: payload.double_down.last_used
                                ),
                                unit: "days"
                            )
                            tokenCard(kind: .save, meter: payload.streak_save, unit: "run days")
                            tokenCard(kind: .assist, meter: payload.streak_assist, unit: "days")

                            naturalCard(payload.natural_streak)
                            rulesCard
                            savedDaysCard
                        } else {
                            ProgressView().tint(.white)
                                .padding(.top, MADTheme.Spacing.xl)
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .navigationTitle("Streak Tokens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(MADTheme.Colors.madRed)
                        .fontWeight(.semibold)
                }
            }
            .task { await tokensState.refreshStatus() }
        }
    }

    /// The three rules that apply to every token, which no per-token card
    /// can own. The first one is the important one: a token is not a day off,
    /// and running the day anyway costs you nothing — the server hands the
    /// token straight back. Without that stated, a covered day reads as "well,
    /// that's spent, might as well rest", which is the exact opposite of what
    /// the feature is for.
    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Good to know")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(.white)

            rule(
                icon: "arrow.uturn.backward.circle.fill",
                tint: SavedDayStyle.tint,
                title: "Run it anyway and you get the token back",
                detail: "A token buys a day you missed. Go and run that day for real and we return the token — and, for an Assist, your friend's mile goes back to them too."
            )
            rule(
                icon: "shield.fill",
                tint: SavedDayStyle.tint,
                title: "A saved day shows blue, not green",
                detail: "Everywhere a day appears — your week chart, your profile, a friend's — a day a token carried is blue and says which token did it. It is never drawn as a missed day."
            )
            rule(
                icon: "flame.fill",
                tint: Color(red: 1.0, green: 0.84, blue: 0.35),
                title: "One at a time, and only for a real gap",
                detail: "Tokens never bridge two missed days in a row, and a streak that used one rests its Pure Flame until your next untouched run."
            )
        }
        .padding(MADTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func rule(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 22)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func atRiskBanner(_ payload: StreakFeaturesPayload) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your streak is on the line")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                Text("You missed yesterday. Run \(String(format: "%.1f", payload.double_down.recover_miles ?? 2.0)) mi today to Double Down and save it.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func tokenCard(
        kind: StreakTokenKind,
        meter: StreakTokenMeter,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: 14) {
                TokenMedallion(
                    kind: kind,
                    held: meter.held,
                    progress: meter.fraction,
                    size: 68
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                    Text(kind.what)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if meter.held {
                    Text("Available")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(kind.tint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.22)))
                }
            }

            // HOW IT'S USED comes before HOW TO EARN on purpose. Someone
            // reading this sheet is almost always holding at least one token
            // already (enrollment back-fills a year), so "what do I do with
            // it" is the live question and "how do I get another" is the
            // follow-up.
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("How it's used")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(kind.tint)
                    TokenUsageBadge(usage: kind.usage)
                }
                Text(kind.howToUse)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    Text(kind.whenItFires)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("How to earn")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(kind.tint)
                Text(kind.howToEarn)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TokenMeterBar(kind: kind, meter: meter, unit: unit)
        }
        .padding(MADTheme.Spacing.md)
        .background(detailTokenBackground(kind: kind, held: meter.held))
    }

    private func detailTokenBackground(kind: StreakTokenKind, held: Bool) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(red: 0.060, green: 0.055, blue: 0.066))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(kind.tint.opacity(held ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(kind.tint.opacity(held ? 0.42 : 0.18), lineWidth: 1)
            )
            .shadow(color: held ? kind.tint.opacity(0.20) : Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
    }

    /// Pure Flame explainer — deliberately an INFO PANEL, not another card in
    /// the earnable-token language above it (no medallion, no meter, flat
    /// fill, gold accent stripe): it's a status you keep, not a token you
    /// spend. Tapping opens the full badge explainer.
    private func naturalCard(_ natural: Bool) -> some View {
        Button {
            showPureFlameInfo = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(pureFlameGold)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("About Pure Flame")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(pureFlameGold)
                        if natural {
                            PureFlameBadge(size: 15)
                        }
                    }
                    Text(natural
                         ? "Your streak is \(ProgressCalculator.formatProgress(1)) natural — every day earned on the day. The gold seal shows beside your name."
                         : "A token kept this streak alive, so the badge is resting. It returns with your next untouched streak.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A status, not a token — nothing to spend. Tap to learn more.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.top, 2)
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(pureFlameGold.opacity(0.25), lineWidth: 1)
                    )
            )
            .overlay(alignment: .leading) {
                // Gold accent stripe — the info-box signature.
                RoundedRectangle(cornerRadius: 2)
                    .fill(pureFlameGold.opacity(0.8))
                    .frame(width: 3)
                    .padding(.vertical, 12)
                    .padding(.leading, 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPureFlameInfo) {
            PureFlameInfoSheet()
        }
    }

    private var pureFlameGold: Color { Color(red: 1.0, green: 0.84, blue: 0.35) }

    private func trimmed(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

// MARK: - Animated meter bar

/// The earn meter, made satisfying: the fill springs from zero on appear, a
/// light shimmer sweeps the filled portion, and the copy counts DOWN ("3 to
/// go") so progress reads as approach, not bookkeeping.
private struct TokenMeterBar: View {
    let kind: StreakTokenKind
    let meter: StreakTokenMeter
    let unit: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    @State private var shimmer = false

    private var fraction: Double { meter.held ? 1 : meter.fraction }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let rawFillWidth = geo.size.width * fraction * (grown ? 1 : 0)
                let fillWidth = min(geo.size.width, max(fraction > 0 ? 6 : 0, rawFillWidth))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: kind.gradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        if fraction > 0.1 {
                            // Shimmer sweep across the filled portion.
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.42), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 42)
                                .rotationEffect(.degrees(12))
                                .offset(x: shimmer ? fillWidth + 16 : -58)
                                .animation(
                                    .linear(duration: 2.2)
                                        .repeatForever(autoreverses: false)
                                        .delay(0.8),
                                    value: shimmer
                                )
                        }
                    }
                    .frame(width: fillWidth)
                    .clipShape(Capsule())
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            Text(statusLine)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(meter.held ? .green : .secondary)
        }
        .onAppear {
            // Reduce Motion: show the final fill immediately, no shimmer loop.
            if reduceMotion {
                grown = true
                return
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.15)) {
                grown = true
            }
            if fraction > 0.1 { shimmer = true }
        }
    }

    private var statusLine: String {
        if meter.held {
            return "Earned — you're holding 1 (max 1). Using it restarts the meter."
        }
        let remaining = max(meter.target - meter.progress, 0)
        let togo = remaining.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(remaining))
            : String(format: "%.1f", remaining)
        let progressText = meter.progress.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(meter.progress))
            : String(format: "%.1f", meter.progress)
        let targetText = meter.target.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(meter.target))
            : String(format: "%.1f", meter.target)
        return "\(progressText) / \(targetText) \(unit) · \(togo) to go"
    }
}

// MARK: - Pure Flame info sheet

/// "What's the gold seal?" — presented when anyone taps a Pure Flame badge
/// next to a name (own profile, friend profiles, the explainer's info panel).
/// One badge, one sentence, three quick rules. Medium detent.
struct PureFlameInfoSheet: View {
    private var gold: Color { Color(red: 1.0, green: 0.84, blue: 0.35) }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            VStack(spacing: MADTheme.Spacing.md) {
                PureFlameBadge(size: 68)
                    .padding(.top, MADTheme.Spacing.xl)

                VStack(spacing: 6) {
                    Text("Pure Flame")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Text("A \(ProgressCalculator.formatProgress(1)) natural streak — every single day earned the day it happened. No saves, no rescues.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MADTheme.Spacing.lg)
                }

                VStack(spacing: 10) {
                    ruleRow(
                        icon: "figure.run",
                        tint: .green,
                        text: "Keep completing your mile every day and the Pure Flame seal stays lit."
                    )
                    ruleRow(
                        icon: "snowflake",
                        tint: MADTheme.Colors.walkBlue,
                        text: "Using a token to cover a missed day rests the badge until your next untouched streak."
                    )
                    ruleRow(
                        icon: "lifepreserver",
                        tint: MADTheme.Colors.madRed,
                        text: "Donating a mile to a friend never dims your own flame — only the day THEY get covered rests theirs."
                    )
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.top, MADTheme.Spacing.xs)

                Text("It's a status, not a token — nothing to spend, everything to defend.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(gold.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MADTheme.Spacing.lg)

                Spacer(minLength: 0)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func ruleRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.15)))

            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
}
