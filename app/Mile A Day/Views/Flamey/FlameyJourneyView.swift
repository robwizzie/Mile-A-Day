import SwiftUI

// FLAMEY'S CLOSET — the first-run "unboxing". The first time someone opens
// the Closet (and whenever they ask, from "What I've unlocked"), a few pages
// walk them through what their medals have ALREADY unlocked, one medal family
// at a time, before the grid: welcome → one page per family they hold
// something in → what's next to earn. At most six pages, Skip on every one,
// and nothing goes on him unless they tap "Wear it". Pure: renders from stub
// data in the harness.

// MARK: - The pages

/// Medal families, grouped the way people think about what they did.
enum FlameyJourneyGroup: String, CaseIterable, Hashable {
    case streaks, distance, challenges, social

    var families: Set<FlameyFamily> {
        switch self {
        case .streaks: return [.streakDays]
        case .distance: return [.lifetimeMiles, .pace, .distanceInADay, .firsts]
        case .challenges: return [.dailyChallenges, .weeklyChallenges, .ghosts]
        case .social: return [.competitionsEntered, .competitionsWon, .organizer, .hypes, .buddyWalks, .stories, .nudges]
        }
    }

    static func group(for family: FlameyFamily) -> FlameyJourneyGroup? {
        allCases.first { $0.families.contains(family) }
    }

    var eyebrow: String {
        switch self {
        case .streaks: return "Your streak medals"
        case .distance: return "Your distance & speed medals"
        case .challenges: return "Your challenge medals"
        case .social: return "Your friends & competition medals"
        }
    }

    /// "8 flame colours" / "6 things to wear".
    func headline(_ count: Int) -> String {
        switch self {
        case .streaks: return count == 1 ? "1 flame colour" : "\(count) flame colours"
        default: return count == 1 ? "1 thing to wear" : "\(count) things to wear"
        }
    }

    var blurb: String {
        switch self {
        case .streaks: return "Every streak medal lights him up in a new colour."
        case .distance: return "Miles, pace and big days earn hats, shoes and trails."
        case .challenges: return "Daily and weekly challenges and ghost races earn eyewear and more."
        case .social: return "Walking with friends, hyping and competing earn capes, props and companions."
        }
    }
}

struct FlameyJourneyPage: Identifiable, Equatable {
    enum Kind: Hashable {
        case welcome
        case group(FlameyJourneyGroup)
        case more
    }

    let kind: Kind
    /// What this page shows as unlocked (best first).
    let items: [FlameyItem]

    var id: Kind { kind }
}

enum FlameyJourney {
    /// Welcome, then a page per family group with at least one unlock, then
    /// "what's next". At most six pages by construction (4 groups + 2).
    static func pages(owned: Set<FlameyItem>) -> [FlameyJourneyPage] {
        let earned = owned.filter { $0.unlock != .always && !$0.isMoodProp }
        var pages = [FlameyJourneyPage(kind: .welcome, items: sorted(Array(earned)))]
        for group in FlameyJourneyGroup.allCases {
            let items = earned.filter { !$0.isHolidayOutfit && group.families.contains($0.family) }
            guard !items.isEmpty else { continue }
            pages.append(FlameyJourneyPage(kind: .group(group), items: sorted(Array(items))))
        }
        pages.append(FlameyJourneyPage(kind: .more, items: sorted(Array(earned.filter(\.isHolidayOutfit)))))
        return pages
    }

    /// Best first: by slot (colour, head, …), then the hardest medal.
    static func sorted(_ items: [FlameyItem]) -> [FlameyItem] {
        items.sorted { ($0.slot.sortIndex, -$0.tier, $0.rawValue) < ($1.slot.sortIndex, -$1.tier, $1.rawValue) }
    }

    /// The medals behind a page's items, hardest first, one per medal.
    static func medalIds(for items: [FlameyItem]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in items.sorted(by: { $0.tier > $1.tier }) {
            guard let id = item.badgeId, seen.insert(id).inserted else { continue }
            out.append(id)
        }
        return out
    }

    /// "Next to earn": locked items the user is closest to (known progress
    /// first), else the first rung of a few different families.
    @MainActor
    static func nextToEarn(_ model: FlameyClosetModel, limit: Int = 3) -> [FlameyItem] {
        let locked = FlameyItem.closet.filter { !model.owns($0) && $0.unlock != .always && !$0.isHolidayOutfit }
        let withProgress = locked.compactMap { item in model.progress(for: item).map { (item, $0.fraction) } }
            .sorted { $0.1 > $1.1 }
        var picked: [FlameyItem] = []
        var families = Set<FlameyFamily>()
        for (item, _) in withProgress where !families.contains(item.family) {
            picked.append(item)
            families.insert(item.family)
            if picked.count == limit { return picked }
        }
        for item in locked.sorted(by: { $0.tier < $1.tier }) where !families.contains(item.family) {
            picked.append(item)
            families.insert(item.family)
            if picked.count == limit { break }
        }
        return picked
    }
}

// MARK: - The view

struct FlameyJourneyView: View {
    let model: FlameyClosetModel
    var still: Bool = false
    /// Where to open (the harness renders each page).
    var startPage: Int = 0
    var onFinish: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var previewing: [FlameyJourneyPage.Kind: FlameyItem] = [:]
    @State private var started = false
    @State private var forward = true

    private var pages: [FlameyJourneyPage] { FlameyJourney.pages(owned: model.owned) }
    private var page: FlameyJourneyPage { pages[min(index, pages.count - 1)] }
    private var isLast: Bool { index >= pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                Group {
                    if still {
                        pageBody(page)
                    } else {
                        // A small phone or big text can outgrow a page; it
                        // scrolls rather than clips.
                        ScrollView { pageBody(page).padding(.bottom, 12) }
                            .scrollIndicators(.hidden)
                            .scrollBounceBehavior(.basedOnSize)
                    }
                }
                .id(page.id)
                .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)
            bottomButtons
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .background(background.ignoresSafeArea())
        .madTypeCap(.madCardCap)
        .onAppear {
            guard !started else { return }
            started = true
            index = min(startPage, pages.count - 1)
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                           removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -50 { go(index + 1) }
                if value.translation.width > 50 { go(index - 1) }
            }
    }

    private func go(_ next: Int) {
        guard next >= 0 else { return }
        guard next < pages.count else { return onFinish() }
        guard next != index else { return }
        MADHaptics.tap()
        forward = next > index
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { index = next }
    }

    // MARK: Chrome

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.22, green: 0.07, blue: 0.10), Color(red: 0.09, green: 0.04, blue: 0.05), .black],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [glow.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.42),
                           startRadius: 0, endRadius: 300)
        }
    }

    private var glow: Color {
        FlameyPalette.palette(for: stageLook(page).color)?.glow ?? Color(red: 1, green: 0.55, blue: 0.2)
    }

    private var topBar: some View {
        HStack {
            if index > 0 {
                Button { go(index - 1) } label: {
                    Image(systemName: "chevron.left")
                        .madFont(size: 17, weight: .bold, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color.white : Color.white.opacity(0.25))
                        .frame(width: i == index ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(index + 1) of \(pages.count)")
            Spacer(minLength: 0)
            Button {
                MADHaptics.tap()
                onFinish()
            } label: {
                Text(isLast ? "Done" : "Skip")
                    .madFont(size: 16, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Goes straight to Flamey's Closet")
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    private var bottomButtons: some View {
        Button {
            MADHaptics.action()
            go(index + 1)
        } label: {
            Text(primaryTitle)
                .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FlameyClosetStyle.primaryFill))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var primaryTitle: String {
        if isLast { return "Open the Closet" }
        switch page.kind {
        case .welcome: return pages.count > 2 ? "Show me what I've unlocked" : "Show me how to unlock things"
        default:
            if case .group(let next) = pages[index + 1].kind {
                return "Next: \(nextName(next))"
            }
            return "Next: what's left to earn"
        }
    }

    private func nextName(_ group: FlameyJourneyGroup) -> String {
        switch group {
        case .streaks: return "streak medals"
        case .distance: return "distance & speed"
        case .challenges: return "challenges"
        case .social: return "friends & competitions"
        }
    }

    // MARK: Pages

    @ViewBuilder
    private func pageBody(_ page: FlameyJourneyPage) -> some View {
        switch page.kind {
        case .welcome: welcome(page)
        case .group(let group): groupPage(group, page: page)
        case .more: morePage(page)
        }
    }

    private func stageLook(_ page: FlameyJourneyPage) -> FlameyLook {
        model.preview(with: previewing[page.kind])
    }

    private func stage(_ page: FlameyJourneyPage, size: CGFloat, line: String?) -> some View {
        var mood = FlameMood(kind: .ready, streak: 0)
        mood.pokeQuip = line
        return ZStack(alignment: .bottom) {
            Ellipse()
                .fill(RadialGradient(colors: [glow.opacity(0.4), .clear], center: .center, startRadius: 1, endRadius: size * 0.8))
                .frame(width: size * 1.7, height: size * 0.24)
                .offset(y: size * 0.04)
            FlameBuddyView(health: .healthy, size: size, mood: mood, still: still, showsMoodBubble: line != nil,
                           look: stageLook(page))
                .frame(width: size, height: size)
                .padding(.bottom, size * 0.12)
        }
        .frame(height: size * (line != nil ? 1.5 : 1.2), alignment: .bottom)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func titleBlock(eyebrow: String, title: String, body: String) -> some View {
        VStack(spacing: 6) {
            Text(eyebrow.uppercased())
                .madFont(size: 12, weight: .black, design: .rounded, maxScale: 1.4)
                .tracking(1.4)
                .foregroundColor(FlameyClosetStyle.ember)
                .multilineTextAlignment(.center)
            Text(title)
                .madFont(size: 30, weight: .black, design: .rounded)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Text(body)
                .madFont(size: 15, weight: .semibold, design: .rounded)
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    // Welcome

    private func welcome(_ page: FlameyJourneyPage) -> some View {
        let count = page.items.count
        return VStack(spacing: 14) {
            stage(page, size: 150, line: "I've got a closet!")
                .padding(.top, 4)
            titleBlock(eyebrow: "New for Flamey",
                       title: "Flamey has a closet!",
                       body: "Your medals unlock things he can wear. He stays just as he is until you pick something.")
            if count > 0 {
                unlockedSummary(page.items)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            } else {
                Text("Earn your first medal — a 3-day streak or your first mile — and his first unlock is yours.")
                    .madFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    /// "Your medals unlocked 33 things" + one chip per closet section.
    private func unlockedSummary(_ items: [FlameyItem]) -> some View {
        let bySlot = Dictionary(grouping: items, by: \.slot)
        let slots = FlameySlot.allCases.filter { bySlot[$0] != nil }
        return VStack(spacing: 10) {
            (Text("Your medals unlocked ")
                + Text("\(items.count)").foregroundColor(FlameyClosetStyle.ember)
                + Text(items.count == 1 ? " item" : " items"))
                .madFont(size: 17, weight: .heavy, design: .rounded)
                .foregroundColor(.white)
            FlowRows(spacing: 6) {
                ForEach(slots, id: \.self) { slot in
                    Text("\(slot.shortLabel) · \(bySlot[slot]?.count ?? 0)")
                        .madFont(size: 12, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // A family group

    private func groupPage(_ group: FlameyJourneyGroup, page: FlameyJourneyPage) -> some View {
        let selected = previewing[page.kind]
        return VStack(spacing: 12) {
            titleBlock(eyebrow: group.eyebrow, title: group.headline(page.items.count), body: group.blurb)
                .padding(.top, 2)
            medalRow(FlameyJourney.medalIds(for: page.items))
            stage(page, size: 118, line: nil)
            previewCaption(page: page, selected: selected)
            itemStrip(page)
        }
    }

    private func medalRow(_ ids: [String]) -> some View {
        let shown = Array(ids.prefix(4))
        return HStack(alignment: .top, spacing: 10) {
            ForEach(shown, id: \.self) { id in
                let info = model.medals[id].map { var m = $0; m.isEarned = true; return m }
                    ?? { var m = FlameyMedalInfo.placeholder(badgeId: id); m.isEarned = true; return m }()
                VStack(spacing: 4) {
                    FlameyMedalDisc(medal: info, size: 38)
                    Text(info.name ?? FlameyItem.unlockCopy(badgeId: id))
                        .madFont(size: 10, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 70)
                .accessibilityElement(children: .combine)
            }
            if ids.count > shown.count {
                VStack(spacing: 4) {
                    Text("+\(ids.count - shown.count)")
                        .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                    Text("more")
                        .madFont(size: 10, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(width: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("and \(ids.count - shown.count) more medals")
            }
        }
    }

    private func previewCaption(page: FlameyJourneyPage, selected: FlameyItem?) -> some View {
        HStack(spacing: 10) {
            if let selected {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.isWorn(selected) ? "WEARING" : "TRYING ON")
                        .madFont(size: 10, weight: .black, design: .rounded, maxScale: 1.3)
                        .tracking(1)
                        .foregroundColor(model.isWorn(selected) ? FlameyClosetStyle.worn : .white.opacity(0.45))
                    Text(selected.displayName)
                        .madFont(size: 15, weight: .heavy, design: .rounded)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                if !model.isWorn(selected) {
                    Button {
                        MADHaptics.success()
                        withAnimation(reduceMotion ? nil : .snappy) { model.wear(selected) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .black)).accessibilityHidden(true)
                            Text("Wear it").madFont(size: 14, weight: .heavy, design: .rounded, maxScale: 1.3).lineLimit(1).fixedSize()
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(Color.white))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Wear \(selected.displayName)")
                }
            } else {
                Text("Tap one to try it on — nothing changes until you wear it.")
                    .madFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 40)
    }

    private func itemStrip(_ page: FlameyJourneyPage) -> some View {
        // A GRID, not a strip: this page's job is to show EVERYTHING the
        // family unlocked, and a sideways scroll hid most of it.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(page.items, id: \.self) { item in
                let selected = previewing[page.kind] == item
                Button {
                    MADHaptics.tap()
                    withAnimation(reduceMotion ? nil : .snappy) {
                        previewing[page.kind] = selected ? nil : item
                    }
                } label: {
                    VStack(spacing: 3) {
                        FlameyItemArt(item: item, color: model.stageLook.color)
                            .frame(height: 46)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(item.displayName)
                            .madFont(size: 10, weight: .bold, design: .rounded, maxScale: 1.2)
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(selected ? 0.14 : 0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? Color.white : (model.isWorn(item) ? FlameyClosetStyle.worn : Color.white.opacity(0.08)),
                                      lineWidth: selected || model.isWorn(item) ? 2 : 1))
                }
                .buttonStyle(FlameyTilePressStyle())
                .accessibilityLabel(item.displayName + (model.isWorn(item) ? ", wearing" : ""))
                .accessibilityHint("Tries it on Flamey")
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 20)
    }

    // What's next

    private func morePage(_ page: FlameyJourneyPage) -> some View {
        let next = FlameyJourney.nextToEarn(model)
        let left = model.tally.total - model.tally.owned
        return VStack(spacing: 14) {
            titleBlock(eyebrow: "More to earn",
                       title: "\(left) more to unlock",
                       body: "Every medal adds something. Here's what you're closest to.")
                .padding(.top, 6)
            VStack(spacing: 8) {
                ForEach(next, id: \.self) { item in
                    nextRow(item)
                }
            }
            .padding(.horizontal, 20)
            if !page.items.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(FlameyClosetStyle.ember)
                        .accessibilityHidden(true)
                    Text("Holiday outfits (you have \(page.items.count)) go on by themselves on the day — no need to pick them.")
                        .madFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .accessibilityElement(children: .combine)
            }
            Text("Tap anything locked in the Closet to see its medal and where to earn it.")
                .madFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func nextRow(_ item: FlameyItem) -> some View {
        let progress = model.progress(for: item)
        let medal = model.medal(for: item)
        return HStack(spacing: 12) {
            FlameyItemArt(item: item, color: model.stageLook.color)
                .frame(width: 58, height: 50)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FlameyClosetStyle.artFill))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .madFont(size: 15, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let medal {
                        FlameyMedalDisc(medal: medal, size: 16)
                    }
                    Text(item.unlockCopy)
                        .madFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                if let progress {
                    HStack(spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.10))
                                Capsule().fill(FlameyClosetStyle.ember)
                                    .frame(width: max(4, geo.size.width * progress.fraction))
                            }
                        }
                        .frame(height: 4)
                        Text(progress.short)
                            .madFont(size: 11, weight: .bold, design: .rounded, maxScale: 1.3, monospacedDigit: true)
                            .foregroundColor(FlameyClosetStyle.ember)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A wrapping row

/// Chips that wrap onto a second line instead of squeezing (the counts row).
struct FlowRows: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(i)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
