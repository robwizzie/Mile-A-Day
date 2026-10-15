import SwiftUI

/// Dashboard card (Fun, optional): this month's Monthly Flame and the run so
/// far. Flamey stands in the form he's walking toward, the days fill in as
/// dots, and the line under them says exactly what today is worth. Tapping
/// opens the Closet straight onto Monthly Flames.
///
/// Progress is the server's (`monthly_flames` on the closet read, cached in
/// `FlameyMonthlyStore`); the phone never judges a day itself. Until the first
/// read lands the card still shows the month's form and what it takes.
struct MonthlyFlameCard: View {
    @State private var status: FlameyMonthlyStatus? = FlameyMonthlyStore.load()

    private var month: Int {
        status?.current.month ?? Calendar.current.component(.month, from: Date())
    }

    private var item: FlameyItem { FlameyItem.monthlyFlame(for: month) ?? .jackOLantern }

    private var glow: Color { FlameyPalette.palette(for: item)?.glow ?? .orange }

    var body: some View {
        Button {
            MADHaptics.tap()
            FlameyClosetLink.shared.open(focus: item, monthly: true)
        } label: {
            HStack(alignment: .center, spacing: MADTheme.Spacing.md) {
                figure
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(FlameyItem.monthName(month).uppercased()) · MONTHLY FLAME")
                        .madFont(size: 10, weight: .black, design: .rounded, maxScale: 1.3)
                        .tracking(0.8)
                        .foregroundColor(glow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(item.displayName)
                        .madFont(size: 19, weight: .heavy, design: .rounded)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let current = status?.current, current.month == month {
                        progress(current)
                    }
                    Text(line)
                        .madFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .padding(MADTheme.Spacing.md)
            .background(
                ZStack {
                    DashboardCardSurface(style: .fun)
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .fill(LinearGradient(colors: [glow.opacity(0.18), .clear],
                                             startPoint: .leading, endPoint: .trailing))
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Monthly Flames")
        .task {
            await FlameyClosetSync.refreshIfStale()
            if let fresh = FlameyMonthlyStore.load() { status = fresh }
        }
    }

    /// Him, already wearing the month's form over his own outfit.
    private var figure: some View {
        var choice = FlameyFacts.choice
        choice[.color] = item
        let look = FlameyLook.resolve(owned: FlameyFacts.ownedItems.union([item]), choice: choice,
                                      signupDate: FlameyFacts.signupDate, detail: .compact)
        return ZStack(alignment: .bottom) {
            Circle()
                .fill(RadialGradient(colors: [glow.opacity(0.35), .clear], center: .center,
                                     startRadius: 1, endRadius: 40))
                .frame(width: 76, height: 76)
            FlameBuddyView(health: .healthy, size: 56, still: true, look: look, wardrobeReach: 0.8)
                .frame(width: 56, height: 56)
                .padding(.bottom, 6)
        }
        .frame(width: 72, height: 76)
        .accessibilityHidden(true)
    }

    /// One bar per day of the month: done, today (outlined until it's in),
    /// still to come. A broken run shows the count only — which day it broke
    /// on isn't the point any more.
    @ViewBuilder
    private func progress(_ c: FlameyMonthlyStatus.Current) -> some View {
        if c.still_perfect {
            HStack(spacing: 2) {
                ForEach(1...max(1, c.days_in_month), id: \.self) { day in
                    let done = day < c.day_of_month || (day == c.day_of_month && c.today_done)
                    let today = day == c.day_of_month
                    Capsule()
                        .fill(done ? glow : Color.white.opacity(0.10))
                        .overlay(Capsule().strokeBorder(today && !done ? glow : .clear, lineWidth: 1))
                        .frame(height: 8)
                }
            }
            .accessibilityHidden(true)
        } else {
            ProgressView(value: Double(c.days_done), total: Double(max(1, c.days_in_month)))
                .tint(glow.opacity(0.5))
                .accessibilityHidden(true)
        }
    }

    private var line: String {
        let name = FlameyItem.monthName(month)
        guard let c = status?.current, c.month == month else {
            return "Walk your mile every day of \(name) to unlock it for good."
        }
        let owned = status?.earned(month) != nil
        if !c.still_perfect {
            return owned
                ? "\(c.days_done) of \(c.days_in_month) days. Already yours from a perfect \(name) before."
                : "\(c.days_done) of \(c.days_in_month) days. The run broke — next month starts fresh on the 1st."
        }
        let left = c.days_in_month - c.day_of_month
        if !c.today_done {
            return "Perfect so far — today's mile keeps it alive. \(left + 1) to go."
        }
        if left == 0 { return "Every day of \(name)! It's yours." }
        return left == 1 ? "Perfect so far. 1 day to go." : "Perfect so far. \(left) days to go."
    }
}
