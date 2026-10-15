import StoreKit
import SwiftUI

/// What Mile A Day+ gives you — ONLY what ships. App Review (2.3.1 / 3.1.2)
/// rejects a paywall that sells features that aren't in the build, so a perk
/// goes here the day it works, never before.
enum PlusPerk: CaseIterable, Identifiable {
    case fasterTokens, flameyColors, family, support

    var id: Self { self }

    var icon: String {
        switch self {
        case .fasterTokens: return "shield.lefthalf.filled"
        case .flameyColors: return "paintpalette.fill"
        case .family: return "person.3.fill"
        case .support: return "heart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .fasterTokens: return .cyan
        case .flameyColors: return .orange
        case .family: return .green
        case .support: return MADTheme.Colors.madRed
        }
    }

    var title: String {
        switch self {
        case .fasterTokens: return "Streak tokens, faster"
        case .flameyColors: return "Plus-only Flamey looks"
        case .family: return "Share with your family"
        case .support: return "Keep Mile A Day independent"
        }
    }

    var detail: String {
        switch self {
        case .fasterTokens:
            return "Double Down in 5 days instead of 14, Streak Save in 3 runs instead of 7, and a Streak Assist every 14 days instead of 30."
        case .flameyColors:
            return "Electric, Rose Gold, Obsidian and Tropic colors, plus the glow-in-the-dark Skeleton Suit."
        case .family:
            return "One subscription covers up to five family members with Family Sharing."
        case .support:
            return "No ads, ever. Plus is how two runners keep building this."
        }
    }
}

/// The Mile A Day+ paywall. Skippable everywhere, prices from the App Store
/// (never hard-coded), and the renewal terms spelled out beside the button —
/// the disclosures App Review checks for (3.1.2). The button, its terms and
/// Restore / Terms / Privacy ride a bar pinned to the bottom, so they're on
/// screen at every scroll position and every iPhone size.
struct PlusPaywallView: View {
    enum Context {
        case onboarding, settings, flamey, streakTokens, streakAtRisk
    }

    /// Three designs, each for the moment it's shown in:
    /// - `.streak`: protect-your-streak + the free-week timeline. The default
    ///   for ad traffic (they don't know Flamey yet; losing a streak is the
    ///   fear everyone has) and for the token / at-risk doors.
    /// - `.flamey`: Flamey trying on the Plus looks over the full perk list.
    ///   Settings, and the other arm of the onboarding A/B test.
    /// - `.closet`: a dressing room, for someone who just tapped a locked look.
    enum Layout { case streak, flamey, closet }

    var context: Context = .settings
    /// A line about THIS user's tokens ("You're 2 runs from a Streak Save…"),
    /// shown on the streak layout.
    var note: String? = nil
    /// Called once when the paywall is done: `true` after a purchase.
    var onFinish: (_ purchased: Bool) -> Void = { _ in }

    @ObservedObject private var store = PlusStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selected = PlusProducts.yearly
    @State private var loadAttempted = false
    @State private var alert: PaywallAlert?
    @State private var legalURL: URL?
    @State private var tryOn: FlameyItem = .roseGold
    @State private var celebrating = false
    @State private var recordedView = false

    private struct PaywallAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var finishAfter = false
    }

    private var layout: Layout {
        switch context {
        case .onboarding: return PlusPaywallVariant.current(store.status) == "flamey" ? .flamey : .streak
        case .streakTokens, .streakAtRisk: return .streak
        case .flamey: return .closet
        case .settings: return .flamey
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            background

            if celebrating {
                PlusWelcomeView(
                    // Onboarding hands off to the app; the Closet door is
                    // already in the Closet.
                    showsDressUp: context != .onboarding && context != .flamey,
                    onDressUp: {
                        finish(purchased: true)
                        FlameyClosetLink.shared.openAfterDismiss(focus: .electric)
                    },
                    onDone: { finish(purchased: true) }
                )
                .transition(.opacity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        if store.isPlus {
                            header
                                .padding(.top, MADTheme.Spacing.lg)
                            alreadyPlus
                        } else {
                            switch layout {
                            case .flamey: flameyContent
                            case .streak: streakContent
                            case .closet: closetContent
                            }
                        }
                    }
                    .padding(.horizontal, MADTheme.Spacing.screenGutter)
                    .padding(.bottom, MADTheme.Spacing.lg)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !store.isPlus { purchaseBar }
                }
                .madTypeCap(.madCardCap)

                Button {
                    MADHaptics.tap()
                    finish(purchased: false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .accessibilityLabel("Close")
                .padding(.trailing, MADTheme.Spacing.md)
                .padding(.top, MADTheme.Spacing.sm)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await store.loadProducts()
            loadAttempted = true
            if store.status == nil { await store.fetchStatus() }
            recordView()
        }
        .alert(item: $alert) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("OK")) {
                    if item.finishAfter { finish(purchased: true) }
                }
            )
        }
        .sheet(item: $legalURL) { url in
            SafariWebView(url: url)
                .ignoresSafeArea()
        }
    }

    /// Which paywall this person saw, once per open: the onboarding A/B arms
    /// (compared against purchases server-side) and the Closet door.
    private func recordView() {
        guard !recordedView, !store.isPlus else { return }
        recordedView = true
        switch (context, layout) {
        case (.onboarding, .streak): PlusTelemetry.paywallStreak()
        case (.onboarding, .flamey): PlusTelemetry.paywallFlamey()
        case (_, .closet): PlusTelemetry.paywallCloset()
        default: break
        }
    }

    private var accent: Color {
        switch layout {
        case .streak: return Color(red: 0.37, green: 0.78, blue: 1.0)
        case .flamey: return .orange
        case .closet: return Color(red: 1.0, green: 0.55, blue: 0.62)
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.06, blue: 0.11), Color(red: 0.05, green: 0.03, blue: 0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(colors: [(celebrating ? Color.orange : accent).opacity(0.2), .clear], center: .top,
                           startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            PlusLookShowcase(size: 120)

            Text("Mile A Day+")
                .madFont(size: 34, weight: .black, design: .rounded, maxScale: 1.4)
                .foregroundStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.82, blue: 0.45), .orange, MADTheme.Colors.madRed],
                                                startPoint: .leading, endPoint: .trailing))
                .accessibilityAddTraits(.isHeader)
            Text(headline)
                .madFont(size: 16, weight: .medium, design: .rounded)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headline: String {
        switch context {
        case .streakTokens, .streakAtRisk: return "Earn your streak tokens in about half the time."
        case .flamey: return "Dress Flamey in looks only Plus members have."
        case .onboarding: return "Your daily mile is free, forever. Plus makes protecting your streak easier and Flamey a lot more fun."
        case .settings: return "Everything you love about Mile A Day stays free. Plus is a little extra."
        }
    }

    // MARK: Layout A — Flamey first

    @ViewBuilder
    private var flameyContent: some View {
        header
            .padding(.top, MADTheme.Spacing.lg)
        tokens
        extras
        plans
    }

    // MARK: Layout B — streak first

    private var streakHeadline: String {
        switch context {
        case .streakAtRisk: return "Don't let one missed day end it."
        case .streakTokens: return "Protect your streak sooner."
        default: return "One bad day won't end your streak."
        }
    }

    @ViewBuilder
    private var streakContent: some View {
        HStack(alignment: .center, spacing: 12) {
            FlameBuddyView(health: .healthy, size: 64, still: true, showsMoodBubble: false,
                           look: FlameyFacts.look(detail: .compact), wardrobeReach: 0.8)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("MILE A DAY+")
                    .madFont(size: 12, weight: .black, design: .rounded, maxScale: 1.3)
                    .tracking(1.4)
                    .foregroundColor(.orange)
                Text(streakHeadline)
                    .madFont(size: 25, weight: .black, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, MADTheme.Spacing.xl)
        .padding(.trailing, 28)

        if let note {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accent)
                    .accessibilityHidden(true)
                Text(note)
                    .madFont(size: 14, weight: .bold, design: .rounded)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.opacity(0.14)))
        }

        saveSpeedCard

        if store.products.isEmpty {
            plans
        } else if showsTrialTimeline {
            trialTimeline
        } else {
            extras
        }
    }

    /// The Streak Save meter, free against Plus: seven grey dots, three lit.
    private var saveSpeedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            (Text("A Streak Save in ") + Text("3 runs").foregroundColor(accent) + Text(", not 7"))
                .madFont(size: 16, weight: .heavy, design: .rounded)
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 8) {
                dotRow(label: "FREE", count: 7, lit: false)
                dotRow(label: "PLUS", count: 3, lit: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("A Streak Save takes 7 runs free, 3 runs with Plus")
            HStack(spacing: 8) {
                speedTile(name: "Double Down", plus: "5 days", free: "14", tint: .orange)
                speedTile(name: "Streak Assist", plus: "14 days", free: "30", tint: Color(red: 1.0, green: 0.48, blue: 0.69))
            }
            Text("Walk days count as half a run. Plus-only Flamey looks and Family Sharing too.")
                .madFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MADTheme.Spacing.md)
        .background(card)
    }

    private func dotRow(label: String, count: Int, lit: Bool) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.2)
                .foregroundColor(lit ? accent : .white.opacity(0.6))
                .frame(width: 40, alignment: .leading)
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle()
                        .fill(lit ? accent : Color.white.opacity(0.14))
                        .frame(width: 20, height: 20)
                }
            }
            if lit {
                Text("Saved.")
                    .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.2)
                    .foregroundColor(accent)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
    }

    private func speedTile(name: String, plus: String, free: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .madFont(size: 12, weight: .bold, design: .rounded)
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(plus)
                    .madFont(size: 16, weight: .black, design: .rounded)
                    .foregroundColor(tint)
                    .lineLimit(1)
                Text(free)
                    .madFont(size: 12, weight: .bold, design: .rounded)
                    .foregroundColor(.white.opacity(0.5))
                    .strikethrough(true, color: .white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    /// The free week, step by step — only when the yearly trial is what the
    /// button will start. Dates and price come from the App Store's product.
    private var showsTrialTimeline: Bool {
        guard selected == PlusProducts.yearly, store.trialEligible,
              let yearly = store.product(PlusProducts.yearly) else { return false }
        return PlusPlanCopy.freeTrial(yearly) != nil
    }

    private var trialTimeline: some View {
        let yearly = store.product(PlusProducts.yearly)
        let trialEnd = Calendar.current.date(byAdding: .day, value: 7, to: Date())
            .map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "day 7"
        let price = yearly.map { PlusPlanCopy.priceLabel($0) } ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            Text("HOW YOUR FREE WEEK WORKS")
                .madFont(size: 12, weight: .black, design: .rounded, maxScale: 1.3)
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.6))
                .padding(.bottom, 10)
            timelineStep(title: "Today", detail: "Everything in Plus unlocks. Your tokens speed up right away.",
                         dot: .filled, last: false)
            timelineStep(title: "Any time this week", detail: "Cancel in Settings › Apple ID › Subscriptions. You won't be charged.",
                         dot: .ring, last: false)
            timelineStep(title: trialEnd, detail: "Your year of Plus begins at \(price), unless you cancelled.",
                         dot: .dim, last: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum TimelineDot { case filled, ring, dim }

    private func timelineStep(title: String, detail: String, dot: TimelineDot, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    switch dot {
                    case .filled: Circle().fill(Color.orange)
                    case .ring: Circle().strokeBorder(Color.orange, lineWidth: 2)
                    case .dim: Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 2)
                    }
                }
                .frame(width: 14, height: 14)
                if !last {
                    Rectangle()
                        .fill(Color.orange.opacity(0.4))
                        .frame(width: 2)
                        .frame(minHeight: 30, maxHeight: .infinity)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .madFont(size: 15, weight: .black, design: .rounded)
                    .foregroundColor(.white)
                Text(detail)
                    .madFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, last ? 0 : 12)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Yearly / Monthly in the pinned bar for the streak layout, with
    /// Lifetime one tap away below it.
    private var billingToggle: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                billingOption(PlusProducts.yearly)
                billingOption(PlusProducts.monthly)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
            if let lifetime = store.product(PlusProducts.lifetime) {
                Button {
                    MADHaptics.tap()
                    withAnimation(.easeOut(duration: 0.15)) { selected = PlusProducts.lifetime }
                } label: {
                    HStack(spacing: 6) {
                        if selected == PlusProducts.lifetime {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.orange)
                                .accessibilityHidden(true)
                        }
                        Text("Or pay once: \(lifetime.displayPrice), no subscription")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .madFont(size: 13, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(selected == PlusProducts.lifetime ? 1 : 0.72))
                    .frame(minHeight: 30)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == PlusProducts.lifetime ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func billingOption(_ id: String) -> some View {
        if let product = store.product(id) {
            let on = selected == id
            Button {
                MADHaptics.tap()
                withAnimation(.easeOut(duration: 0.15)) { selected = id }
            } label: {
                VStack(spacing: 1) {
                    Text("\(PlusPlanCopy.title(product)) · \(PlusPlanCopy.priceLabel(product))")
                        .madFont(size: 14, weight: .black, design: .rounded, maxScale: 1.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if id == PlusProducts.yearly, let savings = yearlySavings {
                        Text("Save \(savings)%")
                            .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.2)
                            .foregroundColor(on ? Color(red: 0.75, green: 0.35, blue: 0.0) : .orange)
                    }
                }
                .foregroundColor(on ? Color(red: 0.1, green: 0.04, blue: 0.06) : .white.opacity(0.78))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? Color.white : Color.clear))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }

    // MARK: Layout C — Closet try-on

    @ViewBuilder
    private var closetContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MILE A DAY+ CLOSET")
                .madFont(size: 12, weight: .black, design: .rounded, maxScale: 1.3)
                .tracking(1.4)
                .foregroundColor(.orange)
            Text("Try it on.")
                .madFont(size: 30, weight: .black, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, MADTheme.Spacing.xl)

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.12, green: 0.07, blue: 0.13))
            Ellipse()
                .fill(Color.black.opacity(0.35))
                .frame(width: 150, height: 24)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 18)
            RadialGradient(colors: [PlusLookShowcase.glow(tryOn).opacity(0.45), .clear], center: .center,
                           startRadius: 4, endRadius: 140)
            FlameBuddyView(health: .healthy, size: 150, showsMoodBubble: false,
                           look: PlusLookShowcase.look(tryOn), wardrobeReach: 0.9)
                .frame(width: 150, height: 150)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 26)
                .id(tryOn)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .accessibilityLabel("Flamey in \(tryOn.displayName)")
            HStack {
                Text(tryOn.displayName)
                    .madFont(size: 14, weight: .black, design: .rounded, maxScale: 1.3)
                    .foregroundColor(PlusLookShowcase.glow(tryOn))
                Spacer()
                Text("PLUS")
                    .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.2)
                    .foregroundColor(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(red: 1.0, green: 0.7, blue: 0.28)))
            }
            .padding(14)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(PlusLookShowcase.looks, id: \.self) { item in
                let on = item == tryOn
                Button {
                    MADHaptics.tap()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.78)) { tryOn = item }
                } label: {
                    VStack(spacing: 2) {
                        FlameBuddyView(health: .healthy, size: 36, still: true, showsMoodBubble: false,
                                       look: PlusLookShowcase.look(item, detail: .compact), wardrobeReach: 0.8)
                            .frame(width: 36, height: 36)
                        Text(item.displayName)
                            .madFont(size: 10, weight: .heavy, design: .rounded, maxScale: 1.2)
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(on ? 0.1 : 0.03)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(on ? PlusLookShowcase.glow(item) : Color.white.opacity(0.12), lineWidth: on ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.displayName)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            perkChip("Double Down in 5 days", tint: .orange)
            perkChip("Streak Save in 3 runs", tint: Color(red: 0.56, green: 0.85, blue: 1.0))
            perkChip("Assist every 14 days", tint: Color(red: 1.0, green: 0.61, blue: 0.77))
            perkChip("Family Sharing", tint: .white.opacity(0.85))
        }

        plans
    }

    private func perkChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.3)
            .foregroundColor(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Capsule().fill(tint.opacity(0.14)))
    }

    // MARK: What you get

    private var tokens: some View {
        PlusTokenComparison()
            .padding(MADTheme.Spacing.md)
            .background(card)
    }

    private var extras: some View {
        VStack(spacing: 0) {
            extraRow(PlusPerk.flameyColors)
            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 52)
            extraRow(PlusPerk.family)
            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 52)
            extraRow(PlusPerk.support)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, 6)
        .background(card)
    }

    private func extraRow(_ perk: PlusPerk) -> some View {
        HStack(alignment: .top, spacing: MADTheme.Spacing.md) {
            Image(systemName: perk.icon)
                .madFont(size: 15, weight: .bold, maxScale: 1.3)
                .foregroundColor(perk.tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(perk.tint.opacity(0.15)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(perk.title)
                    .madFont(size: 15, weight: .bold, design: .rounded)
                    .foregroundColor(.white)
                Text(perk.detail)
                    .madFont(size: 13, weight: .regular, design: .rounded)
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    // MARK: Already Plus

    private var alreadyPlus: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            if store.status?.source == "founding" {
                FoundingRunnerCard()
            } else {
                VStack(spacing: 6) {
                    Label("You're on Mile A Day+", systemImage: "checkmark.seal.fill")
                        .madFont(size: 18, weight: .heavy, design: .rounded)
                        .foregroundColor(.green)
                    if let line = PlusStatusCopy.line(for: store.status) {
                        Text(line)
                            .madFont(size: 14, weight: .medium, design: .rounded)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(MADTheme.Spacing.md)
                .background(card)
            }
            tokens
            Button {
                finish(purchased: false)
            } label: {
                Text("Done")
                    .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MADTheme.Colors.madRed))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Plans

    @ViewBuilder
    private var plans: some View {
        if store.products.isEmpty {
            VStack(spacing: MADTheme.Spacing.sm) {
                if loadAttempted {
                    Text("Plans couldn't load right now.")
                        .madFont(size: 15, weight: .medium, design: .rounded)
                        .foregroundColor(.white.opacity(0.7))
                    Button("Try again") {
                        loadAttempted = false
                        Task {
                            await store.loadProducts()
                            loadAttempted = true
                        }
                    }
                    .foregroundColor(.orange)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: MADTheme.Spacing.sm) {
                Text("CHOOSE YOUR PLAN")
                    .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(PlusProducts.plans, id: \.self) { id in
                    if let product = store.product(id) {
                        planCard(product)
                    }
                }
            }
        }
    }

    private var yearlySavings: Int? {
        guard let yearly = store.product(PlusProducts.yearly),
              let monthly = store.product(PlusProducts.monthly) else { return nil }
        return PlusPlanCopy.savingsPercent(yearly: yearly, monthly: monthly)
    }

    private func planCard(_ product: Product) -> some View {
        let isSelected = selected == product.id
        let savings = product.id == PlusProducts.yearly ? yearlySavings : nil
        return Button {
            MADHaptics.tap()
            withAnimation(.easeOut(duration: 0.15)) { selected = product.id }
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .madFont(size: 22, weight: .semibold, maxScale: 1.3)
                    .foregroundColor(isSelected ? .orange : .white.opacity(0.35))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    // The badge sits on its own line: beside the title it
                    // crowds the price off a 320pt screen.
                    if let badge = PlusPlanCopy.badge(product, trialEligible: store.trialEligible, savings: savings) {
                        Text(badge)
                            .madFont(size: 10, weight: .black, design: .rounded, maxScale: 1.3)
                            .foregroundColor(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(LinearGradient(colors: [Color(red: 1.0, green: 0.82, blue: 0.45), .orange],
                                                                      startPoint: .leading, endPoint: .trailing)))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text(PlusPlanCopy.title(product))
                        .madFont(size: 17, weight: .heavy, design: .rounded)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(PlusPlanCopy.subtitle(product))
                        .madFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 4)
                Text(PlusPlanCopy.priceLabel(product))
                    .madFont(size: 16, weight: .bold, design: .rounded)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.orange.opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.orange : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
            .scaleEffect(isSelected ? 1 : 0.985)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedProduct: Product? { store.product(selected) }

    // MARK: The pinned purchase bar

    private var purchaseBar: some View {
        VStack(spacing: 8) {
            if layout == .streak && !store.products.isEmpty {
                billingToggle
            }
            purchaseButton
            finePrint
            footerLinks
            if context == .onboarding {
                Button {
                    MADHaptics.tap()
                    finish(purchased: false)
                } label: {
                    Text("Not now")
                        .madFont(size: 16, weight: .semibold, design: .rounded, maxScale: 1.4)
                        .foregroundColor(.white.opacity(0.65))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MADTheme.Spacing.screenGutter)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(
            LinearGradient(colors: [Color(red: 0.05, green: 0.03, blue: 0.06).opacity(0.0),
                                    Color(red: 0.05, green: 0.03, blue: 0.06).opacity(0.96),
                                    Color(red: 0.05, green: 0.03, blue: 0.06)],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.25))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var purchaseButton: some View {
        Button {
            guard let product = selectedProduct else { return }
            MADHaptics.action()
            Task { await buy(product) }
        } label: {
            ZStack {
                if store.isBusy {
                    ProgressView().tint(.white)
                } else {
                    Text(selectedProduct.map { PlusPlanCopy.callToAction($0, trialEligible: store.trialEligible) } ?? "Continue")
                        .madFont(size: 18, weight: .heavy, design: .rounded, maxScale: 1.4)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [.orange, MADTheme.Colors.madRed],
                                         startPoint: .leading, endPoint: .trailing))
            )
            .shadow(color: MADTheme.Colors.madRed.opacity(0.45), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(selectedProduct == nil || store.isBusy)
        .opacity(selectedProduct == nil ? 0.5 : 1)
    }

    @ViewBuilder
    private var finePrint: some View {
        if let product = selectedProduct {
            Text(PlusPlanCopy.terms(product, trialEligible: store.trialEligible))
                .madFont(size: 11, weight: .regular, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerLinks: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Button("Restore Purchases") {
                Task { await restore() }
            }
            Text("·").accessibilityHidden(true)
            Button("Terms") { legalURL = PlusLinks.terms }
            Text("·").accessibilityHidden(true)
            Button("Privacy") { legalURL = PlusLinks.privacy }
        }
        .madFont(size: 12, weight: .semibold, design: .rounded, maxScale: 1.3)
        .foregroundColor(.white.opacity(0.6))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .disabled(store.isBusy)
    }

    // MARK: Actions

    private func buy(_ product: Product) async {
        switch await store.purchase(product) {
        case .purchased:
            MADHaptics.success()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { celebrating = true }
        case .pending:
            alert = PaywallAlert(title: "Purchase pending",
                                 message: "It needs approval first. Plus switches on as soon as it's approved.")
        case .cancelled:
            break
        case .awaitingServer:
            alert = PaywallAlert(title: "Thanks for joining!",
                                 message: "Your purchase went through. Plus will switch on in a moment — we'll keep trying in the background.",
                                 finishAfter: true)
        case .failed(let message):
            alert = PaywallAlert(title: "Purchase didn't go through", message: message)
        }
    }

    private func restore() async {
        let restored = await store.restore()
        if restored {
            MADHaptics.success()
            alert = PaywallAlert(title: "Welcome back", message: "Mile A Day+ is active on this account.", finishAfter: true)
        } else {
            alert = PaywallAlert(title: "Nothing to restore",
                                 message: "We couldn't find a Mile A Day+ purchase for this Apple ID.")
        }
    }

    private func finish(purchased: Bool) {
        onFinish(purchased)
        if context != .onboarding { dismiss() }
    }
}

// MARK: - Copy

enum PlusLinks {
    static let terms = URL(string: "https://mileaday.run/terms")!
    static let privacy = URL(string: "https://mileaday.run/privacy")!
}

/// Everything the paywall says about a product, from the App Store's own
/// price and period — never a hard-coded price.
enum PlusPlanCopy {
    static func title(_ product: Product) -> String {
        switch product.id {
        case PlusProducts.yearly: return "Yearly"
        case PlusProducts.monthly: return "Monthly"
        case PlusProducts.lifetime: return "Lifetime"
        default: return product.displayName
        }
    }

    static func badge(_ product: Product, trialEligible: Bool, savings: Int? = nil) -> String? {
        if product.id == PlusProducts.yearly {
            if let trial = freeTrial(product), trialEligible { return "\(trial.uppercased()) FREE" }
            if let savings { return "SAVE \(savings)%" }
            return "BEST VALUE"
        }
        if product.id == PlusProducts.lifetime { return "PAY ONCE" }
        return nil
    }

    /// How much cheaper a year is than twelve months, from the App Store's
    /// own prices; nil when it isn't meaningfully cheaper.
    static func savingsPercent(yearly: Product, monthly: Product) -> Int? {
        let twelve = monthly.price * 12
        guard twelve > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: yearly.price / twelve).doubleValue
        let percent = Int(((1 - ratio) * 100).rounded(.down))
        return percent >= 5 ? percent : nil
    }

    static func subtitle(_ product: Product) -> String {
        switch product.id {
        case PlusProducts.yearly:
            let perMonth = (product.price / 12).formatted(product.priceFormatStyle)
            return "Just \(perMonth)/month, billed yearly"
        case PlusProducts.monthly: return "Billed monthly"
        case PlusProducts.lifetime: return "Pay once, Plus forever — no subscription"
        default: return product.description
        }
    }

    static func priceLabel(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        return "\(product.displayPrice)/\(shortUnit(period))"
    }

    static func callToAction(_ product: Product, trialEligible: Bool) -> String {
        if product.subscription == nil { return "Unlock Plus forever" }
        if trialEligible, let trial = freeTrial(product) { return "Start your \(trial) free trial" }
        return "Subscribe"
    }

    /// The renewal disclosure Guideline 3.1.2 asks for, next to the button.
    static func terms(_ product: Product, trialEligible: Bool) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return "One-time purchase of \(product.displayPrice). No subscription, nothing renews."
        }
        let price = "\(product.displayPrice) per \(longUnit(period))"
        let renew = "Renews automatically unless cancelled at least 24 hours before the end of the period. "
            + "Manage or cancel anytime in your Apple ID's Subscriptions settings."
        if trialEligible, let trial = freeTrial(product, adjective: false) {
            return "Free for \(trial), then \(price). \(renew)"
        }
        return "\(price). \(renew)"
    }

    /// The free-trial length, when this product offers one: "7-day" as an
    /// adjective ("Start your 7-day free trial"), "7 days" as a noun ("Free
    /// for 7 days").
    static func freeTrial(_ product: Product, adjective: Bool = true) -> String? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        return describe(offer.period, adjective: adjective)
    }

    private static func describe(_ period: Product.SubscriptionPeriod, adjective: Bool) -> String {
        let n = period.value
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        if n == 1 { return "1 \(unit)" }
        return adjective ? "\(n)-\(unit)" : "\(n) \(unit)s"
    }

    private static func shortUnit(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day: return "day"
        case .week: return "wk"
        case .month: return period.value == 1 ? "mo" : "\(period.value) mo"
        case .year: return "yr"
        @unknown default: return "period"
        }
    }

    private static func longUnit(_ period: Product.SubscriptionPeriod) -> String {
        if period.value == 1 {
            switch period.unit {
            case .day: return "day"
            case .week: return "week"
            case .month: return "month"
            case .year: return "year"
            @unknown default: return "period"
            }
        }
        return describe(period, adjective: false)
    }
}

/// One line about where the user's Plus comes from and when it ends.
enum PlusStatusCopy {
    static func line(for status: PlusStatus?) -> String? {
        guard let status, status.is_plus else { return nil }
        let date = status.expiresDate.map { $0.formatted(date: .abbreviated, time: .omitted) }
        switch status.source ?? "" {
        case "founding":
            return "Founding Runner — Plus for life, on us. Thank you for being here early."
        case "lifetime":
            return status.family_shared == true ? "Lifetime, shared through Family Sharing." : "Lifetime — it's yours for good."
        case "gift":
            return "A gift — Plus through \(date ?? "next year")."
        case "subscription":
            if status.family_shared == true { return "Shared with you through Family Sharing." }
            guard let date else { return "Subscribed." }
            if status.in_trial == true { return "Free trial — ends \(date)." }
            return status.will_renew == false ? "Ends \(date). It won't renew." : "Renews \(date)."
        default:
            return nil
        }
    }
}
