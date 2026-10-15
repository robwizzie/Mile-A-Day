import SwiftUI

// MARK: - Data (the closet's `monthly_flames` block)

/// Monthly Flames as the server judges them (`GET /users/:id/flamey-closet`,
/// `monthly_flames`): which months have ever been PERFECT, and how this month
/// is going. Never computed on the phone — the server's day rule (a mile, 10k
/// steps or a token-covered day) is the only one.
struct FlameyMonthlyStatus: Codable, Equatable {
    struct Month: Codable, Equatable {
        let month: Int
        let item_id: String
        let name: String
        let earned: Bool
        let earned_year: Int?
    }

    struct Current: Codable, Equatable {
        let year: Int
        let month: Int
        let item_id: String
        let name: String
        let days_in_month: Int
        let day_of_month: Int
        let days_done: Int
        let today_done: Bool
        let still_perfect: Bool
    }

    let months: [Month]
    let current: Current

    func earned(_ month: Int) -> Month? { months.first { $0.month == month && $0.earned } }
}

/// The last `monthly_flames` the server sent, per account.
@MainActor
enum FlameyMonthlyStore {
    private static let prefix = "flameyMonthlyV1|"

    private static var key: String? {
        guard let me = UserDefaults.standard.string(forKey: "backendUserId"), !me.isEmpty else { return nil }
        return prefix + me
    }

    static func save(_ status: FlameyMonthlyStatus) {
        guard let key, let data = try? JSONEncoder().encode(status) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> FlameyMonthlyStatus? {
        guard let key, let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FlameyMonthlyStatus.self, from: data)
    }
}

// MARK: - The screen

/// Monthly Flames: a Flamey FORM for every month, earned by walking your mile
/// every single day of it. This month leads — him already wearing the form,
/// the days so far, and exactly what a miss would cost — then all twelve,
/// each previewed ON him so the reward is visible before it's earned. Owned
/// forms go straight onto the Closet's draft ("Try it on"); Save stays the
/// Closet's.
struct FlameyMonthlyFlamesView: View {
    let model: FlameyClosetModel
    var onClose: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var status: FlameyMonthlyStatus? = FlameyMonthlyStore.load()
    @State private var locked: FlameyItem?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Walk your mile every day of a month and Flamey becomes that month's flame — yours for good. Every outfit still fits.")
                        .madFont(size: 14, weight: .medium, design: .rounded)
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    if let current = status?.current {
                        currentCard(current)
                    }
                    Text("ALL TWELVE")
                        .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.45))
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(FlameyItem.monthlyFlames, id: \.self) { item in
                            monthCard(item)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(FlameyClosetStyle.ground.ignoresSafeArea())
        .madTypeCap(.madCardCap)
        .task {
            await FlameyClosetSync.refreshNow()
            if let fresh = FlameyMonthlyStore.load() { status = fresh }
        }
        .alert(item: $locked) { item in
            let month = FlameyItem.monthName(item.month ?? 1)
            return Alert(
                title: Text(item.displayName),
                message: Text("Walk your mile (or 10,000 steps) every day of \(month) — the 1st through the last — and \(model.displayName) becomes the \(item.displayName) flame for good. Streak tokens count."),
                dismissButton: .default(Text("Got it"))
            )
        }
    }

    private var topBar: some View {
        HStack {
            Color.clear.frame(width: 60, height: 44)
            Spacer(minLength: 0)
            Text("Monthly Flames")
                .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button {
                MADHaptics.tap()
                onClose()
            } label: {
                Text("Done")
                    .madFont(size: 16, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(FlameyClosetStyle.ember)
                    .frame(minWidth: 60, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    // MARK: This month

    private func currentCard(_ c: FlameyMonthlyStatus.Current) -> some View {
        let item = FlameyItem.monthlyFlame(for: c.month) ?? .jackOLantern
        let glow = FlameyPalette.palette(for: item)?.glow ?? FlameyClosetStyle.ember
        let alreadyOwned = status?.earned(c.month)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                figure(item, size: 104, glow: glow)
                VStack(alignment: .leading, spacing: 4) {
                    Text("THIS MONTH · \(FlameyItem.monthName(c.month).uppercased())")
                        .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                        .tracking(1)
                        .foregroundColor(glow)
                    Text(item.displayName)
                        .madFont(size: 24, weight: .black, design: .rounded)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Text("\(c.days_done) of \(c.days_in_month) days")
                        .madFont(size: 15, weight: .bold, design: .rounded, monospacedDigit: true)
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            if c.still_perfect {
                dayDots(c, tint: glow)
            } else {
                ProgressView(value: Double(c.days_done), total: Double(max(1, c.days_in_month)))
                    .tint(glow.opacity(0.6))
            }
            Text(currentLine(c, item: item, owned: alreadyOwned))
                .madFont(size: 14, weight: .semibold, design: .rounded)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [glow.opacity(0.22), Color.white.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(glow.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// One dot per day: done, today (ringed until it's in), still to come.
    private func dayDots(_ c: FlameyMonthlyStatus.Current, tint: Color) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 11)
        return LazyVGrid(columns: cols, spacing: 4) {
            ForEach(1...max(1, c.days_in_month), id: \.self) { day in
                let done = day < c.day_of_month || (day == c.day_of_month && c.today_done)
                let isToday = day == c.day_of_month
                Circle()
                    .fill(done ? tint : Color.white.opacity(0.08))
                    .overlay(Circle().strokeBorder(isToday && !done ? tint : .clear, lineWidth: 2))
                    .frame(height: 14)
            }
        }
        .accessibilityHidden(true)
    }

    private func currentLine(_ c: FlameyMonthlyStatus.Current, item: FlameyItem,
                             owned: FlameyMonthlyStatus.Month?) -> String {
        let month = FlameyItem.monthName(c.month)
        let left = c.days_in_month - c.day_of_month
        if !c.still_perfect {
            let next = c.month % 12 + 1
            let nextItem = FlameyItem.monthlyFlame(for: next)?.displayName ?? ""
            if let owned, let year = owned.earned_year {
                return "This \(month)'s run is broken, but \(item.displayName) is already yours from \(String(year)). \(FlameyItem.monthName(next)) starts fresh on the 1st — \(nextItem) is next."
            }
            return "This \(month)'s run is broken. \(FlameyItem.monthName(next)) starts fresh on the 1st — every day of it unlocks \(nextItem)."
        }
        if !c.today_done {
            return "Perfect so far. Today's mile is still to do — miss it and \(month)'s run ends."
        }
        if left == 0 {
            return "That's every day of \(month). \(item.displayName) is yours!"
        }
        return left == 1
            ? "Perfect so far. One more day and \(item.displayName) is yours for good."
            : "Perfect so far. \(left) more days and \(item.displayName) is yours for good."
    }

    // MARK: The twelve

    private func monthCard(_ item: FlameyItem) -> some View {
        let month = item.month ?? 1
        let owned = model.owns(item)
        let worn = model.isWorn(item)
        let isCurrent = status?.current.month == month
        let glow = FlameyPalette.palette(for: item)?.glow ?? FlameyClosetStyle.ember
        return Button {
            if owned {
                MADHaptics.success()
                model.wear(item)
                onClose()
            } else {
                MADHaptics.tap()
                locked = item
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    figure(item, size: 76, glow: glow)
                    if !owned {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
                Text(FlameyItem.monthName(month).uppercased())
                    .madFont(size: 10, weight: .black, design: .rounded, maxScale: 1.3)
                    .tracking(1)
                    .foregroundColor(glow)
                Text(item.displayName)
                    .madFont(size: 15, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                chip(owned: owned, worn: worn, current: isCurrent, month: month)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(owned ? 0.07 : 0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isCurrent ? glow.opacity(0.6) : Color.white.opacity(0.08), lineWidth: isCurrent ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(owned ? "Puts it on in the Closet" : "How to unlock it")
    }

    @ViewBuilder
    private func chip(owned: Bool, worn: Bool, current: Bool, month: Int) -> some View {
        let (text, tint): (String, Color) = {
            if worn { return ("Wearing", FlameyClosetStyle.worn) }
            if owned, let year = status?.earned(month)?.earned_year { return ("Unlocked \(String(year))", .green) }
            if owned { return ("Unlocked", .green) }
            if current { return ("This month", FlameyClosetStyle.ember) }
            return ("Locked", .white.opacity(0.5))
        }()
        Text(text)
            .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.3)
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.14)))
            .lineLimit(1)
    }

    /// Him in his current outfit, wearing this month's flame.
    private func figure(_ item: FlameyItem, size: CGFloat, glow: Color) -> some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(RadialGradient(colors: [glow.opacity(0.35), .clear], center: .center,
                                     startRadius: 1, endRadius: size * 0.6))
                .frame(width: size * 1.1, height: size * 1.1)
            FlameBuddyView(health: .healthy, size: size * 0.72, still: true,
                           look: model.preview(with: item), wardrobeReach: 0.8)
                .frame(width: size * 0.72, height: size * 0.72)
                .padding(.bottom, size * 0.08)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
