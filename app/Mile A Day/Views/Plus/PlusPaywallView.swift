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
        case onboarding, settings, flamey, streakTokens
    }

    var context: Context = .settings
    /// Called once when the paywall is done: `true` after a purchase.
    var onFinish: (_ purchased: Bool) -> Void = { _ in }

    @ObservedObject private var store = PlusStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selected = PlusProducts.yearly
    @State private var loadAttempted = false
    @State private var alert: PaywallAlert?
    @State private var legalURL: URL?

    private struct PaywallAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var finishAfter = false
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: MADTheme.Spacing.lg) {
                    header
                        .padding(.top, MADTheme.Spacing.lg)
                    if store.isPlus {
                        alreadyPlus
                    } else {
                        if context == .flamey {
                            extras
                            tokens
                        } else {
                            tokens
                            extras
                        }
                        plans
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
        .preferredColorScheme(.dark)
        .task {
            await store.loadProducts()
            loadAttempted = true
            if store.status == nil { await store.fetchStatus() }
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

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.06, blue: 0.11), Color(red: 0.05, green: 0.03, blue: 0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(colors: [Color.orange.opacity(0.22), .clear], center: .top,
                           startRadius: 10, endRadius: 360)
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
        case .streakTokens: return "Earn your streak tokens in about half the time."
        case .flamey: return "Dress Flamey in looks only Plus members have."
        case .onboarding: return "Your daily mile is free, forever. Plus makes protecting your streak easier and Flamey a lot more fun."
        case .settings: return "Everything you love about Mile A Day stays free. Plus is a little extra."
        }
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
            finish(purchased: true)
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
