import Combine
import SwiftUI

// Shared Mile A Day+ pieces: the paywall, Settings › Mile A Day+ and the
// What's New page all show the same things the same way — Flamey trying on
// the Plus looks, the Free-vs-Plus token table, and the Founding Runner card.

// MARK: - Flamey trying on the Plus looks

/// Flamey cycling through every Plus-only look, glowing in its colour. Tap a
/// dot to stop on one. Holds still under Reduce Motion.
struct PlusLookShowcase: View {
    var size: CGFloat = 150

    /// Every Plus-only Flamey item, in showcase order.
    static let looks: [FlameyItem] = [.electric, .roseGold, .skeletonSuit, .obsidian, .tropic]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var pinned = false
    private let ticker = Timer.publish(every: 2.4, on: .main, in: .common).autoconnect()

    private var item: FlameyItem { Self.looks[index % Self.looks.count] }

    /// 10 March: no holiday, no costume day.
    private static let previewDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 10; c.hour = 12
        return Calendar.current.date(from: c) ?? Date()
    }()

    static func glow(_ item: FlameyItem) -> Color {
        FlameyPalette.palette(for: item)?.glow ?? Color(red: 0.62, green: 1.0, blue: 0.76)
    }

    /// Him in `item`, nothing else changed — previewed even when not owned.
    @MainActor
    static func look(_ item: FlameyItem, detail: FlameyRenderDetail = .full) -> FlameyLook {
        var choice = FlameyLookChoice.basic
        choice[item.slot] = item
        // A fixed ordinary day and no signup date: on a holiday or his
        // anniversary the day's own items would dress him over the preview.
        return FlameyLook.resolve(owned: FlameyFacts.ownedItems.union([item]), choice: choice,
                                  date: previewDate, detail: detail)
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Self.glow(item).opacity(0.5), .clear], center: .center,
                                         startRadius: 4, endRadius: size * 0.8))
                    .frame(width: size * 1.6, height: size * 1.6)
                FlameBuddyView(health: .healthy, size: size, showsMoodBubble: false,
                               look: Self.look(item), wardrobeReach: 0.9)
                    .frame(width: size, height: size)
                    .id(item)
                    .transition(.asymmetric(insertion: .scale(scale: 0.86).combined(with: .opacity),
                                            removal: .opacity))
            }
            .frame(height: size * 1.25)

            Text(item.displayName)
                .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(Self.glow(item))
                .contentTransition(.opacity)
                .accessibilityLabel("Flamey in \(item.displayName)")

            HStack(spacing: 8) {
                ForEach(Array(Self.looks.enumerated()), id: \.offset) { i, look in
                    Button {
                        MADHaptics.tap()
                        pinned = true
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { index = i }
                    } label: {
                        Circle()
                            .fill(Self.glow(look))
                            .frame(width: i == index ? 11 : 7, height: i == index ? 11 : 7)
                            .opacity(i == index ? 1 : 0.45)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(look.displayName)
                }
            }
        }
        .onReceive(ticker) { _ in
            guard !reduceMotion, !pinned else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                index = (index + 1) % Self.looks.count
            }
        }
    }
}

// MARK: - Free vs Plus

/// The three streak tokens, free next to Plus. Numbers mirror the backend's
/// meter targets (streakFeatureService / plusCatalog).
struct PlusTokenComparison: View {
    /// Light text for the dark paywall; Settings uses the system colours.
    var onDark = true

    private struct Row: Identifiable {
        let icon: String
        let tint: Color
        let name: String
        let free: String
        let plus: String
        var id: String { name }
    }

    private let rows: [Row] = [
        Row(icon: "flame.fill", tint: .orange, name: "Double Down", free: "14 days", plus: "5 days"),
        Row(icon: "snowflake", tint: .cyan, name: "Streak Save", free: "7 runs", plus: "3 runs"),
        Row(icon: "hands.sparkles.fill", tint: .pink, name: "Streak Assist", free: "30 days", plus: "14 days"),
    ]

    private var primary: Color { onDark ? .white : .primary }
    private var secondary: Color { onDark ? .white.opacity(0.45) : .secondary }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("STREAK TOKENS")
                    .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .tracking(1.1)
                    .foregroundColor(secondary)
                Spacer()
                Text("FREE")
                    .frame(width: 50)
                Text("PLUS")
                    .frame(width: 54)
                    .foregroundColor(.orange)
            }
            .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.3)
            .foregroundColor(secondary)
            .padding(.bottom, 8)
            .accessibilityHidden(true)

            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(row.tint)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(row.tint.opacity(0.15)))
                    Text(row.name)
                        .madFont(size: 15, weight: .bold, design: .rounded)
                        .foregroundColor(primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 4)
                    Text(row.free)
                        .madFont(size: 14, weight: .semibold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(secondary)
                        .strikethrough(true, color: secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 50)
                    Text(row.plus)
                        .madFont(size: 15, weight: .black, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 54)
                }
                .padding(.vertical, 7)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.name): \(row.plus) with Plus, \(row.free) free")
            }

            Text("Walks count too — a walk day is half a run toward a Streak Save.")
                .madFont(size: 12, weight: .medium, design: .rounded)
                .foregroundColor(secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }
}

// MARK: - Founding Runner

/// The Founding Runner card: everyone who joined before Mile A Day+ has it
/// free, for life. Gold, with Flamey in a Plus look beside the medal.
struct FoundingRunnerCard: View {
    var compact = false
    var signupDate: Date? = FlameyFacts.signupDate

    static let gold = Color(red: 1.0, green: 0.80, blue: 0.36)
    static let goldDeep = Color(red: 0.86, green: 0.55, blue: 0.14)

    private var sinceLine: String? {
        guard let signupDate else { return nil }
        return "Running with us since \(signupDate.formatted(.dateTime.month(.wide).year()))"
    }

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 12 : 16) {
            ZStack(alignment: .bottomTrailing) {
                FlameBuddyView(health: .healthy, size: compact ? 58 : 76, still: true, showsMoodBubble: false,
                               look: PlusLookShowcase.look(.roseGold, detail: .compact), wardrobeReach: 0.8)
                    .frame(width: compact ? 58 : 76, height: compact ? 58 : 76)
                Image(systemName: "medal.fill")
                    .font(.system(size: compact ? 18 : 22, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Self.gold, Self.goldDeep], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: 6, y: 4)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("FOUNDING RUNNER")
                    .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                    .tracking(1.4)
                    .foregroundColor(Self.gold)
                Text("Mile A Day+ is yours, free, for life.")
                    .madFont(size: compact ? 16 : 19, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if !compact {
                    Text("You were here before Plus existed, so you never pay for it. No subscription, nothing to do. Thank you.")
                        .madFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let sinceLine {
                    Text(sinceLine)
                        .madFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundColor(Self.gold.opacity(0.85))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 14 : 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.15, blue: 0.05), Color(red: 0.11, green: 0.07, blue: 0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Self.gold.opacity(0.9), Self.goldDeep.opacity(0.4)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
        )
        .shadow(color: Self.gold.opacity(0.18), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }
}
