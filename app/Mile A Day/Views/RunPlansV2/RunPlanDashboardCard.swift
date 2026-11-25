import SwiftUI

/// The dashboard's way into Run Plans (Mile A Day+ only), mounted by
/// `DashboardCardsBlock` under the special-event card. Self-hiding: draws
/// nothing for non-members, so it stays out of `DashboardView.body` and its
/// modifier chain. With a plan: today's run and any suggestion waiting.
/// Without one: a quiet one-line offer the user can dismiss.
struct RunPlanDashboardCard: View {
    let style: DashboardStyle
    @ObservedObject private var store = RunPlanV2Store.shared
    @ObservedObject private var plus = PlusStore.shared
    @AppStorage("runPlanV2OfferDismissed") private var offerDismissed = false

    init(style: DashboardStyle) {
        self.style = style
        // An empty body gets no lifecycle (ios.md): load from init.
        Task { @MainActor in await RunPlanV2Store.shared.refreshIfStale() }
    }

    var body: some View {
        Group {
            if plus.isPlus, !store.plusRequired {
                if let current = store.current {
                    NavigationLink { RunPlanHomeView() } label: { planCard(current) }
                        .buttonStyle(.plain)
                } else if store.loaded, !offerDismissed {
                    offer
                }
            }
        }
        .task(id: plus.isPlus) { if plus.isPlus { await store.refreshIfStale() } }
    }

    private func planCard(_ current: RunPlanV2Current) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .madFont(size: 14, weight: .bold, maxScale: 1.3)
                    .foregroundStyle(RPV2Colors.orange)
                    .accessibilityHidden(true)
                Text(String(localized: "Run plan · Week \(current.plan.week_index ?? 1)"))
                    .madFont(size: 13, weight: .bold, design: .rounded)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 4)
                RPV2TierBadge(ai: store.coachTier.isAI)
            }
            if let today = current.today {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(today.dayStatus.isComplete ? String(localized: "Done: \(RPV2Format.title(today))") : RPV2Format.title(today))
                        .madFont(size: 20, weight: .black, design: .rounded, maxScale: 1.5)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    RPV2KindPill(kind: today.dayKind)
                }
                if let sub = today.subtitle, !sub.isEmpty, !today.dayStatus.isComplete {
                    Text(sub)
                        .madFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundStyle(.white.opacity(0.55))
                        .madBodyLines(2)
                }
            } else if let next = current.next_run {
                Text(String(localized: "Next: \(RPV2Format.title(next)) · \(RPV2Format.weekdayShort(next.dateKey))"))
                    .madFont(size: 16, weight: .black, design: .rounded)
                    .foregroundStyle(.white)
                    .madBodyLines(2)
            }
            let waiting = store.pendingProposals.count + store.suggestions.count
            if waiting > 0 {
                HStack(spacing: 6) {
                    Circle().fill(RPV2Colors.gold).frame(width: 7, height: 7)
                    Text(waiting == 1 ? String(localized: "1 suggested change to decide")
                                      : String(localized: "\(waiting) suggested changes to decide"))
                        .madFont(size: 12, weight: .heavy, design: .rounded)
                        .foregroundStyle(RPV2Colors.gold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(DashboardCardSurface.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardCardSurface(style: style))
        .contentShape(Rectangle())
    }

    private var offer: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink { RunPlanHomeView() } label: {
                DashboardQuietCard(style: style, icon: "flame.fill", tint: RPV2Colors.orange,
                                   title: String(localized: "Run plan"),
                                   subtitle: String(localized: "A plan built from your runs, with walk days that keep your streak."))
            }
            .buttonStyle(.plain)
            Button {
                MADHaptics.tap()
                offerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .madFont(size: 11, weight: .bold, maxScale: 1.3)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "Hide"))
            .padding(4)
        }
    }
}
