import StoreKit
import SwiftUI

/// Settings › Mile A Day+: what you have, managing it, and gifting it.
struct PlusSettingsView: View {
    @ObservedObject private var store = PlusStore.shared

    @State private var showPaywall = false
    @State private var showManage = false
    @State private var showOfferCode = false
    @State private var showRedeem = false
    @State private var newGift: PlusGift?
    @State private var gifts: [PlusGift] = []
    @State private var message: SimpleMessage?
    @State private var legalURL: URL?

    private struct SimpleMessage: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.lg) {
                statusCard
                perksCard
                giftCard
                if !gifts.isEmpty { giftsList }
                accountCard
                legal
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.md)
            .madTypeCap(.madListCap)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Mile A Day+")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadProducts()
            await store.refresh()
            gifts = await store.gifts()
        }
        .sheet(isPresented: $showPaywall) {
            PlusPaywallView(context: .settings)
        }
        .sheet(isPresented: $showRedeem) {
            PlusRedeemGiftSheet()
                .presentationDetents([.medium])
        }
        .sheet(item: $newGift) { gift in
            PlusGiftCodeSheet(gift: gift)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $legalURL) { url in
            SafariWebView(url: url)
                .ignoresSafeArea()
        }
        .manageSubscriptionsSheet(isPresented: $showManage)
        .offerCodeRedemption(isPresented: $showOfferCode) { _ in
            Task { _ = await store.restore() }
        }
        .alert(item: $message) { item in
            Alert(title: Text(item.title), message: Text(item.body), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusCard: some View {
        if store.status?.source == "founding" {
            FoundingRunnerCard()
        } else if store.isPlus {
            HStack(alignment: .center, spacing: MADTheme.Spacing.md) {
                FlameBuddyView(health: .healthy, size: 64, still: true, showsMoodBubble: false,
                               look: PlusLookShowcase.look(.electric, detail: .compact), wardrobeReach: 0.8)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Label("You're on Mile A Day+", systemImage: "checkmark.seal.fill")
                        .madFont(size: 18, weight: .heavy, design: .rounded)
                        .foregroundColor(.green)
                    if let line = PlusStatusCopy.line(for: store.status) {
                        Text(line)
                            .madFont(size: 14, weight: .regular, design: .rounded)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        } else {
            VStack(spacing: MADTheme.Spacing.sm) {
                PlusLookShowcase(size: 92)
                Text("Mile A Day+")
                    .madFont(size: 24, weight: .black, design: .rounded)
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.82, blue: 0.45), .orange, MADTheme.Colors.madRed],
                                                    startPoint: .leading, endPoint: .trailing))
                Text("Faster streak tokens, Plus-only Flamey looks and Family Sharing — while everything you love stays free.")
                    .madFont(size: 14, weight: .regular, design: .rounded)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    MADHaptics.action()
                    showPaywall = true
                } label: {
                    Text(trialCTA)
                        .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.4)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(colors: [.orange, MADTheme.Colors.madRed],
                                                     startPoint: .leading, endPoint: .trailing))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, MADTheme.Spacing.xs)
            }
            .frame(maxWidth: .infinity)
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
    }

    /// "Try 1 week free" when the App Store says this Apple ID can still
    /// take the yearly trial, else "See plans".
    private var trialCTA: String {
        if store.trialEligible, let yearly = store.product(PlusProducts.yearly),
           let trial = PlusPlanCopy.freeTrial(yearly, adjective: false) {
            return "Try \(trial) free"
        }
        return "See plans"
    }

    // MARK: Gifts

    private var giftCard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            row(icon: "gift.fill", tint: .pink, title: "Gift a year of Plus",
                subtitle: giftSubtitle) {
                Task { await buyGift() }
            }
            .disabled(store.isBusy || store.product(PlusProducts.giftYear) == nil)
            Divider().overlay(Color.white.opacity(0.06))
            row(icon: "ticket.fill", tint: .orange, title: "Redeem a gift code",
                subtitle: "Someone gave you Plus? Enter their code.") {
                showRedeem = true
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var giftSubtitle: String {
        guard let gift = store.product(PlusProducts.giftYear) else { return "Share a code a friend can redeem" }
        return "\(gift.displayPrice) once — you get a code to share"
    }

    private var giftsList: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Text("YOUR GIFTS")
                .madFont(size: 11, weight: .heavy, design: .rounded)
                .tracking(1.2)
                .foregroundColor(.secondary)
            ForEach(gifts) { gift in
                Button {
                    if !gift.redeemed && !gift.voided { newGift = gift }
                } label: {
                    HStack {
                        Text(gift.display_code)
                            .madFont(size: 16, weight: .bold, design: .monospaced)
                            .foregroundColor(gift.voided ? .secondary : .primary)
                            .strikethrough(gift.voided)
                        Spacer(minLength: 0)
                        Text(giftState(gift))
                            .madFont(size: 13, weight: .semibold, design: .rounded)
                            .foregroundColor(gift.redeemed ? .green : .secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private func giftState(_ gift: PlusGift) -> String {
        if gift.voided { return "Refunded" }
        if gift.redeemed {
            if let name = gift.redeemed_by_username { return "Redeemed by @\(name)" }
            return "Redeemed"
        }
        return "Not redeemed yet — tap to share"
    }

    private func buyGift() async {
        let (outcome, gift) = await store.buyGift()
        switch outcome {
        case .purchased:
            MADHaptics.success()
            gifts = await store.gifts()
            newGift = gift
        case .awaitingServer:
            message = SimpleMessage(title: "Gift purchased",
                                    body: "Your code will appear under Your Gifts in a moment.")
        case .pending:
            message = SimpleMessage(title: "Purchase pending",
                                    body: "Your code will appear here once the purchase is approved.")
        case .failed(let text):
            message = SimpleMessage(title: "Purchase didn't go through", body: text)
        case .cancelled:
            break
        }
    }

    // MARK: Account

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            if store.status?.source == "subscription" && store.status?.family_shared != true {
                row(icon: "creditcard.fill", tint: .blue, title: "Manage subscription",
                    subtitle: "Change plan or cancel with Apple") {
                    showManage = true
                }
                Divider().overlay(Color.white.opacity(0.06))
            }
            row(icon: "arrow.clockwise", tint: .teal, title: "Restore purchases",
                subtitle: "Bought Plus on another device?") {
                Task {
                    let restored = await store.restore()
                    message = restored
                        ? SimpleMessage(title: "Restored", body: "Mile A Day+ is active on this account.")
                        : SimpleMessage(title: "Nothing to restore",
                                        body: "We couldn't find a Mile A Day+ purchase for this Apple ID.")
                }
            }
            .disabled(store.isBusy)
            Divider().overlay(Color.white.opacity(0.06))
            row(icon: "tag.fill", tint: .purple, title: "Redeem an App Store offer code",
                subtitle: "Promo codes from us or Apple") {
                showOfferCode = true
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var perksCard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text(store.isPlus ? "WHAT YOU GET" : "WHAT'S INCLUDED")
                .madFont(size: 11, weight: .heavy, design: .rounded)
                .tracking(1.2)
                .foregroundColor(.secondary)
            PlusTokenComparison(onDark: false)
            Divider().overlay(Color.white.opacity(0.06))
            ForEach([PlusPerk.runPlans, .flameyColors, .family, .support]) { perk in
                HStack(alignment: .top, spacing: MADTheme.Spacing.md) {
                    Image(systemName: perk.icon)
                        .madFont(size: 15, weight: .bold, maxScale: 1.3)
                        .foregroundColor(perk.tint)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(perk.title).madFont(size: 15, weight: .bold, design: .rounded)
                        Text(perk.detail)
                            .madFont(size: 13, weight: .regular, design: .rounded)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var legal: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Button("Terms of Use") { legalURL = PlusLinks.terms }
            Button("Privacy Policy") { legalURL = PlusLinks.privacy }
        }
        .madFont(size: 13, weight: .semibold, design: .rounded)
        .foregroundColor(.secondary)
    }

    private func row(icon: String, tint: Color, title: String, subtitle: String,
                     action: @escaping () -> Void) -> some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            MADSettingsRow(icon: icon, title: title, subtitle: subtitle, iconColor: tint)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Gift code sheet

/// A freshly bought (or unredeemed) gift: the code, big, and a share button.
struct PlusGiftCodeSheet: View {
    let gift: PlusGift
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var lengthText: String {
        gift.months == 12 ? "one year" : "\(gift.months) months"
    }

    private var shareText: String {
        "I got you a year of Mile A Day+ 🎁 Open Mile A Day → Settings → Mile A Day+ → Redeem a gift code, and enter \(gift.display_code)"
    }

    var body: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            Image(systemName: "gift.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(.pink)
                .padding(.top, MADTheme.Spacing.xl)
                .accessibilityHidden(true)
            Text("Your gift code")
                .madFont(size: 22, weight: .heavy, design: .rounded)
            Text(gift.display_code)
                .madFont(size: 30, weight: .black, design: .monospaced, maxScale: 1.3)
                .textSelection(.enabled)
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.vertical, MADTheme.Spacing.md)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
            Text("Good for \(lengthText) of Mile A Day+. Anyone can redeem it once in Settings › Mile A Day+.")
                .madFont(size: 14, weight: .regular, design: .rounded)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MADTheme.Spacing.lg)
            HStack(spacing: MADTheme.Spacing.md) {
                Button {
                    UIPasteboard.general.string = gift.display_code
                    MADHaptics.success()
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .madFont(size: 16, weight: .bold, design: .rounded, maxScale: 1.4)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .madFont(size: 16, weight: .bold, design: .rounded, maxScale: 1.4)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MADTheme.Colors.madRed))
                }
            }
            .padding(.horizontal, MADTheme.Spacing.lg)
            Spacer(minLength: 0)
        }
        .madTypeCap(.madCardCap)
    }
}

// MARK: - Redeem sheet

struct PlusRedeemGiftSheet: View {
    @ObservedObject private var store = PlusStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var error: String?
    @State private var redeemedUntil: Date?
    @State private var done = false

    var body: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            Image(systemName: done ? "checkmark.seal.fill" : "ticket.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(done ? .green : .orange)
                .padding(.top, MADTheme.Spacing.xl)
                .accessibilityHidden(true)
            if done {
                Text("Enjoy Mile A Day+!")
                    .madFont(size: 22, weight: .heavy, design: .rounded)
                if let redeemedUntil {
                    Text("Your gift runs through \(redeemedUntil.formatted(date: .abbreviated, time: .omitted)).")
                        .madFont(size: 15, weight: .regular, design: .rounded)
                        .foregroundColor(.secondary)
                }
                Button("Done") { dismiss() }
                    .madFont(size: 17, weight: .bold, design: .rounded)
            } else {
                Text("Redeem a gift")
                    .madFont(size: 22, weight: .heavy, design: .rounded)
                TextField("XXXX-XXXX-XXXX", text: $code)
                    .madFont(size: 22, weight: .bold, design: .monospaced, maxScale: 1.3)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(MADTheme.Spacing.md)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                    .padding(.horizontal, MADTheme.Spacing.lg)
                if let error {
                    Text(error)
                        .madFont(size: 14, weight: .medium, design: .rounded)
                        .foregroundColor(MADTheme.Colors.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.lg)
                }
                Button {
                    Task { await redeem() }
                } label: {
                    ZStack {
                        if store.isBusy {
                            ProgressView().tint(.white)
                        } else {
                            Text("Redeem")
                                .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.4)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MADTheme.Colors.madRed))
                }
                .buttonStyle(.plain)
                .disabled(store.isBusy || code.filter(\.isLetter).count + code.filter(\.isNumber).count < 12)
                .padding(.horizontal, MADTheme.Spacing.lg)
            }
            Spacer(minLength: 0)
        }
        .madTypeCap(.madCardCap)
    }

    private func redeem() async {
        error = nil
        switch await store.redeem(code: code) {
        case .success(let until):
            MADHaptics.success()
            redeemedUntil = until
            done = true
        case .failure(let failure):
            error = failure.message
        }
    }
}
