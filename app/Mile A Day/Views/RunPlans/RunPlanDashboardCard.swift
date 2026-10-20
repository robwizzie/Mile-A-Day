import SwiftUI
import UIKit

/// The Fun dashboard's door into Run Plans.
/// - Plus + plan: today's run and one-tap check-in chips.
/// - Plus, no plan: "Build your plan".
/// - Not Plus: a teaser that opens the paywall (`.runPlans`).
/// Draws nothing until Plus status is known, so a member never sees the
/// teaser flash. The paywall sheet hangs off the always-present VStack (the
/// teaser disappears the moment a purchase lands), like `PlusStreakCard`.
struct RunPlanDashboardCard: View {
    /// Space above the card when it shows (zero-spacing host stack).
    var topSpacing: CGFloat = 0

    @ObservedObject private var plus = PlusStore.shared
    @ObservedObject private var store = RunPlanStore.shared
    @State private var showPaywall = false

    private enum Mode { case hidden, teaser, build, today(RunPlanDay, RunPlan), planNoDay(RunPlan) }

    private var mode: Mode {
        guard let status = plus.status else { return .hidden }
        guard status.is_plus else { return .teaser }
        guard store.loaded else { return .hidden }
        guard let plan = store.plan else { return .build }
        if let today = store.today { return .today(today, plan) }
        return .planNoDay(plan)
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .sheet(isPresented: $showPaywall) {
            PlusPaywallView(context: .runPlans)
        }
        .task {
            if plus.isPlus {
                await store.refreshIfStale()
            } else if plus.status != nil {
                await plus.loadProducts()
            }
        }
        .onChange(of: plus.isPlus) {
            if plus.isPlus { Task { await store.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            if plus.isPlus { Task { await store.refreshIfStale() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .hidden:
            // Not EmptyView: that gets no lifecycle, and `.task` is what
            // loads the plan that un-hides the card.
            Color.clear.frame(height: 0)
        case .teaser:
            teaser.padding(.top, topSpacing)
        case .build:
            build.padding(.top, topSpacing)
        case .today(let day, let plan):
            todayCard(day, plan: plan).padding(.top, topSpacing)
        case .planNoDay(let plan):
            NavigationLink { RunPlanScreen() } label: { header(plan).runPlanCard() }
                .buttonStyle(.plain)
                .padding(.top, topSpacing)
        }
    }

    // MARK: Plus + plan

    private func header(_ plan: RunPlan) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .madFont(size: 14, weight: .black, maxScale: 1.3)
                .foregroundColor(RunPlanColors.orange)
                .accessibilityHidden(true)
            Text("\(RunPlanFormat.goalsLine(plan.goals)) · week \(RunPlanFormat.week(plan))".uppercased())
                .madFont(size: 12, weight: .black, design: .rounded)
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .madFont(size: 13, weight: .bold, maxScale: 1.3)
                .foregroundColor(.white.opacity(0.35))
                .accessibilityHidden(true)
        }
    }

    private func todayCard(_ day: RunPlanDay, plan: RunPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                RunPlanScreen()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    header(plan)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            dayTitle(day)
                            daySubtitle(day)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            dayTitle(day)
                            daySubtitle(day)
                        }
                    }
                    if day.isDone {
                        Label("Today's run is done", systemImage: "checkmark.circle.fill")
                            .madFont(size: 13, weight: .heavy, design: .rounded)
                            .foregroundColor(RunPlanColors.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your plan")

            if !day.isDone {
                // Each chip opens the plan and checks in from there, so
                // Flamey's answer and any proposal land where they can be read.
                HStack(spacing: 6) {
                    ForEach(RunPlanFeeling.allCases) { feeling in
                        NavigationLink {
                            RunPlanScreen(initialFeeling: feeling)
                        } label: {
                            VStack(spacing: 2) {
                                Text(feeling.emoji)
                                    .font(.system(size: 16))
                                    .accessibilityHidden(true)
                                Text(feeling.label)
                                    .madFont(size: 10, weight: .heavy, design: .rounded, maxScale: 1.3)
                                    .foregroundColor(.white.opacity(0.6))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Check in: \(feeling.label)")
                    }
                }
            }
        }
        .runPlanCard()
    }

    private func dayTitle(_ day: RunPlanDay) -> some View {
        Text(day.dayKind == .streak ? "Streak mile" : RunPlanFormat.title(day))
            .madFont(size: 28, weight: .black, design: .rounded, maxScale: 1.4)
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func daySubtitle(_ day: RunPlanDay) -> some View {
        Text(RunPlanFormat.subtitle(day))
            .madFont(size: 12, weight: .heavy, design: .rounded)
            .foregroundColor(.white.opacity(0.5))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    // MARK: Plus, no plan

    private var build: some View {
        NavigationLink {
            RunPlanScreen()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                RunPlanCoachAvatar(size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Build your plan")
                        .madFont(size: 17, weight: .black, design: .rounded)
                        .foregroundColor(.white)
                    Text("Tell Flamey your goal. Your daily mile still counts.")
                        .madFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .madFont(size: 13, weight: .bold, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .runPlanCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: Not Plus

    /// The trial length comes from the App Store's offer, never a literal (3.1.2).
    private var teaserButtonTitle: String {
        if plus.trialEligible, let yearly = plus.product(PlusProducts.yearly),
           let trial = PlusPlanCopy.freeTrial(yearly, adjective: false) {
            return "Try free for \(trial)"
        }
        return "See Mile A Day+"
    }

    private var teaser: some View {
        Button {
            MADHaptics.action()
            showPaywall = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .madFont(size: 14, weight: .bold, maxScale: 1.3)
                        .foregroundColor(RunPlanColors.gold)
                        .accessibilityHidden(true)
                    Text("RUN PLANS")
                        .madFont(size: 12, weight: .black, design: .rounded, maxScale: 1.3)
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer(minLength: 4)
                    RunPlanPlusChip()
                }
                Text("A plan that adjusts to how you feel.")
                    .madFont(size: 20, weight: .black, design: .rounded)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tell Flamey your goal: a first 5K, a faster mile, a half. Your daily mile still counts.")
                    .madFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text(teaserButtonTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "arrow.right")
                        .accessibilityHidden(true)
                }
                .madFont(size: 13, weight: .black, design: .rounded, maxScale: 1.4)
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Capsule().fill(RunPlanColors.plusGradient))
                .padding(.top, 6)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(RunPlanColors.plum))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(RunPlanColors.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Mile A Day+")
    }
}
