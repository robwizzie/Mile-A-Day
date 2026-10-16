import CryptoKit
import SwiftUI

// Mile A Day+ conversion pieces: which onboarding paywall this account gets,
// the usage pings that let the two be compared, the moment right after a
// purchase, and the dashboard card that offers Plus when a streak is at risk.

// MARK: - Onboarding A/B arm

/// The onboarding paywall's A/B arm: "streak" or "flamey". The server sends it
/// on `/plus/status` (`paywallVariantFor`); before that has loaded, the same
/// hash is computed here so the first paint never flips layouts.
enum PlusPaywallVariant {
    static func current(_ status: PlusStatus?) -> String {
        if let served = status?.paywall_variant { return served }
        guard let id = SessionIdentity.cachedUserId, !id.isEmpty else { return "streak" }
        let digest = SHA256.hash(data: Data("paywall:\(id)".utf8))
        let first = Array(digest).first ?? 0
        return first % 2 == 0 ? "streak" : "flamey"
    }
}

// MARK: - Usage pings

/// Fire-and-forget; the server keeps one row per person per feature per day
/// (`PLUS_FEATURES` in telemetryService.ts). Nothing user-facing waits on it.
enum PlusTelemetry {
    static func paywallStreak() { TelemetryService.record("plus_paywall_streak") }
    static func paywallFlamey() { TelemetryService.record("plus_paywall_flamey") }
    static func paywallCloset() { TelemetryService.record("plus_paywall_closet") }
    static func streakCardShown() { TelemetryService.record("plus_streak_card_shown") }
    static func streakCardTapped() { TelemetryService.record("plus_streak_card_tapped") }
}

// MARK: - Right after buying

/// Shown inside the paywall the moment a purchase lands: what just unlocked,
/// when a trial ends, and a way straight into the Closet.
struct PlusWelcomeView: View {
    var showsDressUp: Bool
    var onDressUp: () -> Void
    var onDone: () -> Void

    @ObservedObject private var store = PlusStore.shared
    @ObservedObject private var tokens = StreakTokensState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    private static let confetti: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, angle: Double, color: Color)] = [
        (0.15, 0.10, 8, 14, -24, .orange),
        (0.82, 0.08, 8, 14, 30, Color(red: 0.31, green: 0.55, blue: 1.0)),
        (0.75, 0.62, 7, 12, -40, Color(red: 0.18, green: 0.85, blue: 0.75)),
        (0.22, 0.68, 7, 12, 18, Color(red: 0.95, green: 0.6, blue: 0.53)),
        (0.31, 0.05, 8, 8, 0, Color(red: 1.0, green: 0.8, blue: 0.36)),
        (0.69, 0.40, 7, 7, 0, Color(red: 1.0, green: 0.48, blue: 0.69)),
        (0.10, 0.48, 6, 6, 0, Color(red: 0.56, green: 0.85, blue: 1.0)),
        (0.90, 0.78, 6, 6, 0, Color(red: 1.0, green: 0.8, blue: 0.36)),
    ]

    private var trialLine: String {
        guard let status = store.status else { return "Thanks for supporting Mile A Day." }
        let date = status.expiresDate.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
        if status.in_trial == true, let date {
            return "Your free trial runs until \(date). Cancel at least a day before in Settings › Apple ID › Subscriptions."
        }
        switch status.source ?? "" {
        case "lifetime": return "It's yours for good. Thanks for supporting Mile A Day."
        case "subscription":
            if let date { return "Renews \(date). Thanks for supporting Mile A Day." }
            return "Thanks for supporting Mile A Day."
        default: return "Thanks for supporting Mile A Day."
        }
    }

    private var doubleDownLine: String? {
        guard let dd = tokens.payload?.double_down else { return nil }
        if dd.held { return "Your Double Down is ready." }
        let left = max(0, Int((dd.target - dd.progress).rounded(.up)))
        return left == 1 ? "1 more mile day to your Double Down." : "\(left) more mile days to your Double Down."
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: MADTheme.Spacing.md) {
                    ZStack {
                        Canvas { ctx, size in
                            for piece in Self.confetti {
                                let rect = CGRect(x: piece.x * size.width - piece.w / 2, y: piece.y * size.height - piece.h / 2,
                                                  width: piece.w, height: piece.h)
                                var c = ctx
                                c.translateBy(x: rect.midX, y: rect.midY)
                                c.rotate(by: .degrees(piece.angle))
                                c.fill(Path(roundedRect: CGRect(x: -piece.w / 2, y: -piece.h / 2, width: piece.w, height: piece.h),
                                            cornerRadius: min(piece.w, piece.h) / 2.5),
                                       with: .color(piece.color))
                            }
                        }
                        .accessibilityHidden(true)
                        FlameBuddyView(health: .healthy, size: 150, showsMoodBubble: false,
                                       look: PlusLookShowcase.look(.electric), wardrobeReach: 0.9)
                            .frame(width: 150, height: 150)
                            .scaleEffect(popped || reduceMotion ? 1 : 0.6)
                            .accessibilityHidden(true)
                    }
                    .frame(height: 230)
                    .padding(.top, MADTheme.Spacing.lg)

                    Text("YOU'RE ON MILE A DAY+")
                        .madFont(size: 12, weight: .black, design: .rounded, maxScale: 1.3)
                        .tracking(1.8)
                        .foregroundColor(Color(red: 0.56, green: 0.72, blue: 1.0))
                    Text("Flamey's never looked better.")
                        .madFont(size: 30, weight: .black, design: .rounded, maxScale: 1.4)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(trialLine)
                        .madFont(size: 14, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("UNLOCKED JUST NOW")
                            .madFont(size: 12, weight: .black, design: .rounded, maxScale: 1.3)
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.6))
                        unlockedRow(icon: "flame.fill", tint: .orange,
                                    text: "Streak tokens fill about twice as fast",
                                    detail: doubleDownLine)
                        unlockedRow(icon: "paintpalette.fill", tint: Color(red: 0.31, green: 0.55, blue: 1.0),
                                    text: "4 colors and the Skeleton Suit, in your Closet", detail: nil)
                        unlockedRow(icon: "person.3.fill", tint: .green,
                                    text: "Family Sharing for up to 5 people", detail: nil)
                    }
                    .padding(MADTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)))
                }
                .padding(.horizontal, MADTheme.Spacing.screenGutter)
                .padding(.bottom, MADTheme.Spacing.lg)
            }

            VStack(spacing: 6) {
                if showsDressUp {
                    Button {
                        MADHaptics.action()
                        onDressUp()
                    } label: {
                        Text("Dress up Flamey")
                            .madFont(size: 18, weight: .black, design: .rounded, maxScale: 1.4)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(red: 0.31, green: 0.42, blue: 1.0)))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    MADHaptics.tap()
                    onDone()
                } label: {
                    Text(showsDressUp ? "Done" : "Let's go")
                        .madFont(size: 16, weight: .heavy, design: .rounded, maxScale: 1.4)
                        .foregroundColor(showsDressUp ? .white.opacity(0.78) : .white)
                        .frame(maxWidth: .infinity, minHeight: showsDressUp ? 46 : 56)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(showsDressUp ? Color.clear : Color(red: 0.31, green: 0.42, blue: 1.0)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MADTheme.Spacing.screenGutter)
            .padding(.bottom, MADTheme.Spacing.md)
        }
        .madTypeCap(.madCardCap)
        .task {
            if !reduceMotion {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { popped = true }
            }
            await store.refresh()
            await StreakTokensState.shared.refreshStatus()
        }
    }

    private func unlockedRow(icon: String, tint: Color, text: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .madFont(size: 14, weight: .bold, design: .rounded)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .madFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.62))
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Protect-your-streak card (dashboard)

/// The offer at the moment Plus would actually have helped: a streak worth
/// protecting, with this user's own Streak Save numbers free against Plus.
/// Shown when the streak is at risk, or when Plus would already have handed
/// them a Save; dismissible for 5 days (an at-risk day still shows it).
/// The sheet hangs off the always-present VStack, not the card: the card
/// disappears the moment a purchase makes them Plus.
struct PlusStreakCard: View {
    let streak: Int
    /// Developer preview (Debug builds): always shows, with sample numbers.
    var preview = false
    /// Space above the card when it shows. The host sits in a zero-spacing
    /// stack with the card above it, so a hidden card adds no gap.
    var topSpacing: CGFloat = 0

    @ObservedObject private var store = PlusStore.shared
    @ObservedObject private var tokens = StreakTokensState.shared
    @State private var showPaywall = false
    @State private var dismissedAt: Date? = PlusStreakCard.loadDismissed()
    @State private var reportedShown = false

    private struct Offer {
        let atRisk: Bool
        let title: String
        let body: String
        let note: String
        let freeLeft: Double
        let plusLeft: Double
        let freeTarget: Double
        let plusTarget: Double
        let progress: Double
    }

    private var offer: Offer? {
        if preview {
            return Offer(atRisk: true, title: "Your 23-day streak is on the line",
                         body: "With Mile A Day+, a Streak Save would already be waiting to cover a missed day.",
                         note: "With Plus, your Streak Save would already be ready.",
                         freeLeft: 3.5, plusLeft: 0, freeTarget: 7, plusTarget: 3, progress: 3.5)
        }
        guard let status = store.status, !status.is_plus,
              let payload = tokens.payload, !tokens.isPreviewingSampleData,
              streak >= 3 else { return nil }
        let save = payload.streak_save
        guard !save.held else { return nil }
        let freeTarget = save.target
        let plusTarget = Double(status.perks?.streak_save_target ?? 3)
        let progress = save.progress
        let freeLeft = max(0, freeTarget - progress)
        let plusLeft = max(0, plusTarget - progress)
        let atRisk = payload.streak_at_risk
        // Not at risk: only worth a card when Plus is close to (or past) a Save.
        if !atRisk {
            guard plusLeft <= 1 else { return nil }
            if let dismissedAt, Date().timeIntervalSince(dismissedAt) < 5 * 86_400 { return nil }
        }
        let n = StreakTokenMeter.number
        let title = atRisk ? "Your \(streak)-day streak is on the line" : "Protect your \(streak)-day streak"
        let body: String
        if plusLeft == 0 {
            body = atRisk
                ? "With Mile A Day+, a Streak Save would already be waiting to cover a missed day."
                : "With Mile A Day+ you'd already be holding a Streak Save. Free, it's \(n(freeLeft)) more runs."
        } else {
            body = "You're \(n(freeLeft)) runs from a Streak Save. With Mile A Day+: \(n(plusLeft))."
        }
        let note = plusLeft == 0
            ? "With Plus, your Streak Save would already be ready."
            : "With Plus you're \(n(plusLeft)) run\(plusLeft == 1 ? "" : "s") from a Streak Save, not \(n(freeLeft))."
        return Offer(atRisk: atRisk, title: title, body: body, note: note, freeLeft: freeLeft, plusLeft: plusLeft,
                     freeTarget: freeTarget, plusTarget: plusTarget, progress: progress)
    }

    var body: some View {
        let current = offer
        VStack(spacing: 0) {
            if let current {
                card(current)
                    .padding(.top, topSpacing)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .onAppear {
                        guard !reportedShown, !preview else { return }
                        reportedShown = true
                        PlusTelemetry.streakCardShown()
                    }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PlusPaywallView(context: current?.atRisk == true ? .streakAtRisk : .streakTokens,
                            note: current?.note,
                            previewLayout: preview ? .streak : nil)
        }
    }

    private func card(_ offer: Offer) -> some View {
        let ice = Color(red: 0.37, green: 0.78, blue: 1.0)
        return ZStack(alignment: .topTrailing) {
            Button {
                MADHaptics.action()
                if !preview { PlusTelemetry.streakCardTapped() }
                showPaywall = true
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "snowflake")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(ice)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(ice.opacity(0.16)))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(offer.title)
                                .madFont(size: 16, weight: .black, design: .rounded)
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(offer.body)
                                .madFont(size: 13, weight: .semibold, design: .rounded)
                                .foregroundColor(.white.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.trailing, 24)
                        Spacer(minLength: 0)
                    }
                    VStack(spacing: 6) {
                        meterRow(label: "Free", value: offer.progress, target: offer.freeTarget, tint: Color.white.opacity(0.45))
                        meterRow(label: "Plus", value: offer.progress, target: offer.plusTarget, tint: ice)
                    }
                    .accessibilityHidden(true)
                    HStack {
                        Text(store.trialEligible ? "Try Mile A Day+ free for a week" : "See Mile A Day+")
                            .madFont(size: 14, weight: .black, design: .rounded)
                            .foregroundColor(Color(red: 0.06, green: 0.12, blue: 0.2))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(Color(red: 0.06, green: 0.12, blue: 0.2))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(ice))
                }
                .padding(MADTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.13, blue: 0.22), Color(red: 0.06, green: 0.07, blue: 0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(ice.opacity(offer.atRisk ? 0.7 : 0.35), lineWidth: offer.atRisk ? 1.5 : 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Mile A Day+")

            if !offer.atRisk {
                Button {
                    MADHaptics.tap()
                    let now = Date()
                    PlusStreakCard.saveDismissed(now)
                    withAnimation(.easeOut(duration: 0.2)) { dismissedAt = now }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
    }

    private func meterRow(label: String, value: Double, target: Double, tint: Color) -> some View {
        let fraction = target > 0 ? min(1, max(0, value / target)) : 0
        return HStack(spacing: 10) {
            Text(label)
                .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.2)
                .foregroundColor(tint)
                .frame(width: 34, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(tint).frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
            Text("\(StreakTokenMeter.number(value))/\(StreakTokenMeter.number(target))")
                .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.2)
                .foregroundColor(.white.opacity(0.7))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }

    private static var dismissKey: String? {
        guard let id = SessionIdentity.cachedUserId, !id.isEmpty else { return nil }
        return "plusStreakCardDismissedV1|" + id
    }

    private static func loadDismissed() -> Date? {
        guard let key = dismissKey else { return nil }
        let t = UserDefaults.standard.double(forKey: key)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private static func saveDismissed(_ date: Date) {
        guard let key = dismissKey else { return }
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
    }
}
