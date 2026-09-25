import SwiftUI

/// ONE card for many medals, instead of an unlock popup per badge. Three
/// occasions, same card:
/// - `.welcome`: once, for a new account that signed in with history.
/// - `.retroactive`: medals that landed in one refresh but were EARNED on
///   earlier days (a server backfill like the holiday medals, or medals earned
///   while the app went unopened). They are listed WITH their dates — a card
///   calling last Halloween's Spooky Mile "today's" is the bug this replaced.
/// - `.burst`: more than a few medals earned today in one go.
struct BadgeSummaryCelebrationView: View {
    enum Mode { case welcome, retroactive, burst }

    let count: Int
    let badges: [Badge]
    var mode: Mode = .welcome

    @State private var showOverlay = false
    @State private var showStack = false
    @State private var showContent = false
    @State private var showButtons = false
    @State private var displayedCount = 0

    private var previewBadges: [Badge] {
        // Prefer the rarest few for the preview row.
        let order: [BadgeRarity] = [.legendary, .rare, .common]
        return Array(
            badges.sorted { a, b in
                (order.firstIndex(of: a.rarity) ?? 9) < (order.firstIndex(of: b.rarity) ?? 9)
            }.prefix(5)
        )
    }

    var body: some View {
        ZStack {
            // Backdrop
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.06, blue: 0.09), .black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .opacity(showOverlay ? 1 : 0)

            VStack(spacing: MADTheme.Spacing.lg) {
                Spacer()

                medalStack
                    .scaleEffect(showStack ? 1 : 0.6)
                    .opacity(showStack ? 1 : 0)

                if showContent {
                    VStack(spacing: MADTheme.Spacing.sm) {
                        Text("\(displayedCount)")
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [.white, MADTheme.Colors.madRed], startPoint: .top, endPoint: .bottom)
                            )
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(headline)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, MADTheme.Spacing.xl)
                        if mode == .retroactive {
                            datedList
                                .padding(.top, MADTheme.Spacing.sm)
                        }
                    }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                Spacer()

                if showButtons {
                    VStack(spacing: MADTheme.Spacing.sm) {
                        Button { viewAll() } label: {
                            Text("View all badges").frame(maxWidth: .infinity)
                        }
                        .madPrimaryButton(fullWidth: true)

                        Button { dismiss() } label: {
                            Text("Back to dashboard")
                                .font(MADTheme.Typography.headline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    .padding(.bottom, MADTheme.Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear(perform: runSequence)
    }

    private var headline: String {
        switch mode {
        case .welcome:
            return count == 1 ? "Badge unlocked" : "Badges unlocked"
        case .retroactive:
            return count == 1 ? "Medal from your history" : "Medals from your history"
        case .burst:
            return "Medals unlocked today"
        }
    }

    private var subtitle: String {
        switch mode {
        case .welcome:
            return "Welcome to Mile A Day! Here's everything you've already earned from your history. 🎉"
        case .retroactive:
            return count == 1
                ? "You'd already earned this one on an earlier day — it's now on your shelf."
                : "You'd already earned these on earlier days — they're now on your shelf."
        case .burst:
            return "A big day. Every one of these is on your shelf."
        }
    }

    /// Retroactive medals, oldest first, each with the day it was EARNED —
    /// the whole point of this card is that none of them are today's.
    private var datedBadges: [Badge] {
        badges.sorted { $0.dateAwarded < $1.dateAwarded }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var datedList: some View {
        let shown = Array(datedBadges.prefix(4))
        let rest = datedBadges.count - shown.count
        return VStack(spacing: 6) {
            ForEach(shown, id: \.id) { badge in
                HStack(spacing: MADTheme.Spacing.sm) {
                    Text(badge.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer(minLength: MADTheme.Spacing.sm)
                    Text(Self.dateFormatter.string(from: badge.dateAwarded))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
            if rest > 0 {
                Text("and \(rest) more in your Medals")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, MADTheme.Spacing.lg)
    }

    private var medalStack: some View {
        HStack(spacing: -18) {
            ForEach(Array(previewBadges.enumerated()), id: \.element.id) { idx, badge in
                miniMedal(badge)
                    .zIndex(Double(previewBadges.count - idx))
                    .rotationEffect(.degrees(Double(idx - previewBadges.count / 2) * 6))
                    .offset(y: idx % 2 == 0 ? 0 : -6)
            }
        }
    }

    private func miniMedal(_ badge: Badge) -> some View {
        // Shared premium medal; shimmer off so the stacked row stays calm.
        MedalView(badge: badge, size: 72, showShimmer: false)
            .frame(width: 88, height: 88)
    }

    private func runSequence() {
        withAnimation(.easeOut(duration: 0.3)) { showOverlay = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { showStack = true }
            MADHaptics.success()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showContent = true }
            animateCount()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showButtons = true }
        }
    }

    private func animateCount() {
        // Quick count-up to the total for a little delight.
        let steps = min(count, 20)
        guard steps > 0 else { displayedCount = count; return }
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * (0.5 / Double(steps))) {
                withAnimation(.easeOut(duration: 0.2)) {
                    displayedCount = Int(Double(count) * Double(i) / Double(steps))
                }
                if i == steps { displayedCount = count }
            }
        }
    }

    private func viewAll() {
        dismiss()
        // Route to the Profile tab where the Badges tab lives.
        NotificationCenter.default.post(name: NSNotification.Name("MAD_SwitchTab"), object: nil, userInfo: ["tab": 4])
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) { showOverlay = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            CelebrationManager.shared.dismissCurrentCelebration()
        }
    }
}
