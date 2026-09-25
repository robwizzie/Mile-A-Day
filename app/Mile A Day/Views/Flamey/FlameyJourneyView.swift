import SwiftUI

// FLAMEY'S CLOSET — the first-run "unboxing". The first time someone opens
// the Closet (and whenever they ask, from "What I've unlocked"), a few pages
// walk them through dressing him in what their medals have ALREADY unlocked:
// welcome → up to five DRESSING STEPS → what's next to earn.
//
// A step is one part of him (his flame · head & face · outfit · by his side ·
// his voice), and inside it every SLOT is its own labelled row — "Shoes",
// "Hat" — with that slot's owned items in tier order, a None, and each
// tile's medal on its corner. Never an unlabelled mixed grid: a hat and a
// trail are different questions. Why body regions and not one step per
// slot: a long-time user owns something in ten or more slots, and ten
// dressing pages is a chore; five steps of two-to-four labelled rows is one
// screen each, and a step with nothing owned is skipped.
//
// Picking: a tap SELECTS for its row (one per slot; tap again = none) and
// the stage shows the whole outfit at once. Picks are a DRAFT the whole way
// through — Next, Back and a swipe only move between steps — and the last
// page asks: "Save this look" or "Keep him basic" (his current look, if he
// has one). Skip with picks on the stage asks the same question as leaving
// the Closet with a draft (Save / Discard / Keep going). The welcome page
// also names him ("What should we call him?", optional). Pure: renders from
// stub data in the harness.

// MARK: - The steps

/// One dressing step: a part of him, and the slots that dress it.
enum FlameyJourneyStep: String, CaseIterable, Hashable {
    case flame, face, outfit, side, voice

    var slots: [FlameySlot] {
        switch self {
        case .flame: return [.color, .aura]
        case .face: return [.head, .eyes]
        case .outfit: return [.chest, .back, .feet, .costume]
        case .side: return [.held, .trail, .companion]
        case .voice: return [.bubble]
        }
    }

    var title: String {
        switch self {
        case .flame: return "Pick his flame"
        case .face: return "Dress his head"
        case .outfit: return "Pick his outfit"
        case .side: return "What's by his side"
        case .voice: return "Pick his voice"
        }
    }

    /// For the button that leads here ("Next: Head & face").
    var shortTitle: String {
        switch self {
        case .flame: return "His flame"
        case .face: return "Head & face"
        case .outfit: return "Outfit"
        case .side: return "By his side"
        case .voice: return "His voice"
        }
    }

    var hint: String {
        switch self {
        case .voice: return "How he talks on your dashboard. Tap one to hear it."
        default: return "One per row — tap again to take it off."
        }
    }
}

struct FlameyJourneyPage: Identifiable, Hashable {
    enum Kind: Hashable {
        case welcome
        case step(FlameyJourneyStep)
        case more
    }

    let kind: Kind
    /// Welcome: everything unlocked. More: the holiday outfits owned.
    let items: [FlameyItem]
    /// A step's rows: each slot with something owned, and what's owned in it.
    var rows: [FlameyJourneyRow] = []

    var id: Kind { kind }
}

/// One labelled row of a dressing step: a slot and what's owned in it.
struct FlameyJourneyRow: Hashable {
    let slot: FlameySlot
    let items: [FlameyItem]
}

enum FlameyJourney {
    /// Welcome, a step per part of him with something owned, then "what's
    /// next". At most seven pages by construction (5 steps + 2).
    static func pages(owned: Set<FlameyItem>) -> [FlameyJourneyPage] {
        let earned = owned.filter { $0.unlock != .always && !$0.isMoodProp }
        var pages = [FlameyJourneyPage(kind: .welcome, items: sorted(Array(earned)))]
        for step in FlameyJourneyStep.allCases {
            let rows = rows(for: step, owned: owned)
            guard !rows.isEmpty else { continue }
            pages.append(FlameyJourneyPage(kind: .step(step), items: rows.flatMap(\.items), rows: rows))
        }
        pages.append(FlameyJourneyPage(kind: .more, items: sorted(Array(earned.filter(\.isHolidayOutfit)))))
        return pages
    }

    /// A step's rows: every slot where something has been EARNED (the
    /// starter colour/bubble alone doesn't make a row), in tier order with
    /// the starter first. Holiday outfits stay out — the day puts them on.
    static func rows(for step: FlameyJourneyStep, owned: Set<FlameyItem>) -> [FlameyJourneyRow] {
        step.slots.compactMap { slot in
            let items = FlameyWardrobe.items(in: slot).filter { owned.contains($0) && !$0.isHolidayOutfit }
            guard items.contains(where: { $0.unlock != .always }) else { return nil }
            return FlameyJourneyRow(slot: slot, items: items)
        }
    }

    /// Best first: by slot (colour, head, …), then the hardest medal.
    static func sorted(_ items: [FlameyItem]) -> [FlameyItem] {
        items.sorted { ($0.slot.sortIndex, -$0.tier, $0.rawValue) < ($1.slot.sortIndex, -$1.tier, $1.rawValue) }
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
    @State private var index: Int
    /// The picks on screen; nil until the first tap (= the Closet's draft).
    @State private var draft: FlameyLookChoice?
    /// The Closet's draft when the walkthrough opened — what "discard" puts back.
    @State private var startChoice: FlameyLookChoice
    /// The last tile tapped, for the caption.
    @State private var tapped: FlameyItem?
    @State private var forward = true
    /// The welcome page's name field.
    @State private var nameText: String
    @State private var nameError: String?
    @State private var naming = false
    /// Skip with picks: "Save changes?" is up.
    @State private var asking = false

    init(model: FlameyClosetModel, still: Bool = false, startPage: Int = 0,
         draft: FlameyLookChoice? = nil, tapped: FlameyItem? = nil, nameText: String? = nil,
         nameError: String? = nil, asking: Bool = false, onFinish: @escaping () -> Void = {}) {
        self.model = model
        self.still = still
        self.startPage = startPage
        self.onFinish = onFinish
        _index = State(initialValue: max(0, min(startPage, FlameyJourney.pages(owned: model.owned).count - 1)))
        _draft = State(initialValue: draft)
        _tapped = State(initialValue: tapped)
        _startChoice = State(initialValue: model.choice)
        _nameText = State(initialValue: nameText ?? (model.name ?? ""))
        _nameError = State(initialValue: nameError)
        _asking = State(initialValue: asking)
    }

    private var pages: [FlameyJourneyPage] { FlameyJourney.pages(owned: model.owned) }
    private var page: FlameyJourneyPage { pages[min(index, pages.count - 1)] }
    private var isLast: Bool { index >= pages.count - 1 }
    private var picks: FlameyLookChoice { draft ?? model.choice }
    /// The picks differ from what he WEARS — they need a Save.
    private var hasUnsaved: Bool { picks != model.savedChoice }
    private var changeCount: Int { FlameySlot.allCases.filter { picks[$0] != model.savedChoice[$0] }.count }
    /// The name as typed, if it would be accepted — the title says it live.
    private var shownName: String {
        if nameError == nil, case .success(let name) = FlameyNameRules.validate(nameText) { return name }
        return model.displayName
    }
    private var stepCount: Int { pages.filter { if case .step = $0.kind { return true } else { return false } }.count }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                topBar
                ZStack {
                    pageBody(page, compact: geo.size.height < 700)
                        .id(page.id)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(swipe)
                footer
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .background(background.ignoresSafeArea())
        .overlay {
            if asking {
                FlameyLeavePromptCard(name: shownName, saved: model.look(for: model.savedChoice), draft: stageLook,
                                      changes: changeCount) { answer in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { asking = false }
                    switch answer {
                    case .save: finish(save: true)
                    case .discard: finish(save: false)
                    case .keepEditing: break
                    }
                }
                .transition(.opacity)
            }
        }
        .madTypeCap(.madCardCap)
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                           removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                if value.translation.width < -50 { go(index + 1) }
                if value.translation.width > 50 { go(index - 1) }
            }
    }

    /// Moving between pages never saves: the picks stay a draft until the
    /// last page's "Save this look". Leaving the welcome page forward names
    /// him first (a refused name keeps you there, saying why).
    private func go(_ next: Int) {
        guard next >= 0, !naming else { return }
        if case .welcome = page.kind, next > index, nameChanged {
            commitName { go(next) }
            return
        }
        guard next < pages.count else { return finish(save: hasUnsaved ? true : nil) }
        guard next != index else { return }
        MADHaptics.tap()
        forward = next > index
        tapped = nil
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { index = next }
    }

    /// Skip / Done: straight out when nothing is picked, else ask.
    private func skip() {
        guard !naming else { return }
        if hasUnsaved {
            MADHaptics.tap()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { asking = true }
        } else {
            finish(save: nil)
        }
    }

    /// save: true = wear the picks; false = put back what he had on; nil =
    /// there was nothing to decide.
    private func finish(save: Bool?) {
        switch save {
        case .some(true):
            model.commit(picks)
            model.announce("Saved \(model.possessiveName) look")
        case .some(false):
            model.setDraft(startChoice)
        case .none:
            break
        }
        onFinish()
    }

    private var nameChanged: Bool {
        let typed = FlameyNameRules.normalize(nameText)
        return typed != (model.name ?? "") && !(typed == FlameyNameRules.fallback && model.name == nil)
    }

    private func commitName(then next: @escaping () -> Void) {
        naming = true
        Task { @MainActor in
            let outcome = await model.rename(nameText)
            naming = false
            if case .rejected(let message) = outcome {
                nameError = message
                MADHaptics.error()
            } else {
                nameError = nil
                next()
            }
        }
    }

    private func pick(_ item: FlameyItem?, in slot: FlameySlot) {
        let current = picks[slot] ?? slot.basicItem
        let next: FlameyItem? = (item == current) ? nil : item
        withAnimation(reduceMotion ? nil : .snappy) {
            draft = picks.picking(next, in: slot)
            tapped = next
        }
    }

    // MARK: Chrome

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.22, green: 0.07, blue: 0.10), Color(red: 0.09, green: 0.04, blue: 0.05), .black],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [glow.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.3),
                           startRadius: 0, endRadius: 300)
        }
    }

    private var stageLook: FlameyLook { model.look(for: picks) }

    private var glow: Color {
        FlameyPalette.palette(for: stageLook.color)?.glow ?? Color(red: 1, green: 0.55, blue: 0.2)
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
                skip()
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
            .accessibilityHint(hasUnsaved ? "Asks whether to save what you picked"
                                          : "Goes straight to the Closet")
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if case .step = page.kind {
                // Reserved even when empty, so the button never jumps.
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .accessibilityHidden(true)
                    Text("Just trying on — you'll save at the end")
                        .madFont(size: 12, weight: .semibold, design: .rounded, maxScale: 1.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundColor(FlameyClosetStyle.ember)
                .opacity(hasUnsaved ? 1 : 0)
                .frame(height: 16)
                .accessibilityHidden(!hasUnsaved)
            }
            if isLast && hasUnsaved {
                picksSummary
                FlameyWideButton(title: "Save this look", icon: "checkmark") {
                    MADHaptics.success()
                    finish(save: true)
                }
                FlameyTextButton(title: model.savedChoice.isBasic ? "Keep him basic" : "Keep his current look") {
                    MADHaptics.tap()
                    finish(save: false)
                }
                .accessibilityHint("Puts back what he had on — nothing you picked is saved")
            } else {
                Button {
                    MADHaptics.action()
                    go(index + 1)
                } label: {
                    HStack(spacing: 8) {
                        if naming { ProgressView().tint(.white).controlSize(.small) }
                        Text(primaryTitle)
                            .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FlameyClosetStyle.primaryFill))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The last page decides about a look it doesn't show — so it shows it:
    /// him in the picks, and what they are.
    private var picksSummary: some View {
        let names = picks.items.filter { $0.slot.basicItem != $0 }.map(\.displayName)
        return HStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                Circle().fill(glow.opacity(0.18))
                FlameyDressedFigure(look: model.look(for: picks, detail: .compact), health: .healthy, size: 44, scale: 1)
                    .frame(width: 44, height: 44)
                    .padding(.bottom, 3)
            }
            .frame(width: 54, height: 54)
            .clipShape(Circle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR PICKS")
                    .madFont(size: 10.5, weight: .black, design: .rounded, maxScale: 1.3)
                    .tracking(1)
                    .foregroundColor(FlameyClosetStyle.ember)
                Text(names.isEmpty ? "Back to basic" : names.joined(separator: ", "))
                    .madFont(size: 13.5, weight: .bold, design: .rounded)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var primaryTitle: String {
        if isLast { return "Open the Closet" }
        switch pages[index + 1].kind {
        case .step(let next):
            if case .welcome = page.kind { return "Let's dress him" }
            return "Next: \(next.shortTitle)"
        case .more:
            if case .welcome = page.kind { return "Show me how to unlock things" }
            return "Next: what's left to earn"
        case .welcome:
            return "Next"
        }
    }

    // MARK: Pages

    @ViewBuilder
    private func pageBody(_ page: FlameyJourneyPage, compact: Bool) -> some View {
        switch page.kind {
        case .welcome:
            scrolling { welcome(page, compact: compact) }
        case .step(let step):
            stepPage(step, page: page, compact: compact)
        case .more:
            scrolling { morePage(page) }
        }
    }

    /// A small phone or big text can outgrow a page; it scrolls rather than
    /// clips (a snapshot draws it flat).
    @ViewBuilder
    private func scrolling<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        if still {
            content()
        } else {
            ScrollView { content().padding(.bottom, 12) }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// Him in the current picks. `line` makes him speak — the bubble step
    /// always does, so the bubble being chosen is on screen to be judged.
    /// Room for the bubble is reserved above him either way, so choosing a
    /// voice never moves anything and no bubble is ever clipped.
    private func stage(size: CGFloat, line: String?) -> some View {
        var mood = FlameMood(kind: .ready, streak: 0)
        mood.pokeQuip = line
        return ZStack(alignment: .bottom) {
            Ellipse()
                .fill(RadialGradient(colors: [glow.opacity(0.4), .clear], center: .center, startRadius: 1, endRadius: size * 0.8))
                .frame(width: size * 1.7, height: size * 0.24)
                .offset(y: size * 0.04)
            FlameBuddyView(health: .healthy, size: size, mood: mood, still: still, showsMoodBubble: line != nil,
                           look: stageLook)
                .frame(width: size, height: size)
                .padding(.bottom, size * 0.12)
        }
        .frame(height: size * 1.12 + FlameyStage.bubbleRoom(size), alignment: .bottom)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FlameyStage.accessibilityLabel(stageLook, name: shownName))
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

    private func welcome(_ page: FlameyJourneyPage, compact: Bool) -> some View {
        let count = page.items.count
        return VStack(spacing: 14) {
            stage(size: compact ? 104 : 150, line: "I've got a closet!")
                .padding(.top, 4)
            titleBlock(eyebrow: "New for \(shownName)",
                       title: "\(shownName) has a closet!",
                       body: count > 0
                           ? "Your medals unlock things he can wear. Try things on — nothing changes until you save."
                           : "Your medals unlock things he can wear. He stays just as he is until you pick something.")
            nameField
                .padding(.horizontal, 20)
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

    /// "What should we call him?" — optional; blank leaves him Flamey. Saved
    /// when the welcome page is left forward.
    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
                Text("What should we call him?")
                    .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.3)
                Text("Optional")
                    .madFont(size: 11.5, weight: .semibold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.4))
            }
            .foregroundColor(.white.opacity(0.85))
            FlameyTextField(placeholder: FlameyNameRules.fallback, text: $nameText, maxLength: FlameyNameRules.maxLength,
                            still: still, isError: nameError != nil, submitLabel: .next) { go(index + 1) }
            if let nameError {
                FlameyFieldNote(error: nameError, hint: "")
            }
        }
        .onChange(of: nameText) { _, new in
            if case .failure(let issue) = FlameyNameRules.validate(new), issue != .empty {
                nameError = issue.message()
            } else {
                nameError = nil
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

    // A dressing step

    /// The header and the stage are PINNED; only the rows scroll, under a
    /// hairline — so the title is never cut off by the top bar and he is
    /// always in view while you pick.
    private func stepPage(_ step: FlameyJourneyStep, page: FlameyJourneyPage, compact: Bool) -> some View {
        let number = (pages.firstIndex { $0.kind == page.kind } ?? 1)
        let line: String? = step.slots.contains(.bubble) ? "How do I sound?" : nil
        return VStack(spacing: 0) {
            VStack(spacing: 3) {
                Text("STEP \(number) OF \(stepCount)")
                    .madFont(size: 11.5, weight: .black, design: .rounded, maxScale: 1.3)
                    .tracking(1.4)
                    .foregroundColor(FlameyClosetStyle.ember)
                Text(step.title)
                    .madFont(size: compact ? 24 : 27, weight: .black, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Text(step.hint)
                    .madFont(size: 13.5, weight: .semibold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .combine)
            stage(size: compact ? 84 : 108, line: line)
            stepCaption(step)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            Group {
                if still {
                    Color.clear.overlay(alignment: .top) { stepRows(page) }
                } else {
                    ScrollView { stepRows(page) }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
        }
    }

    /// What the last tap put on him and the medal it came from — else what
    /// to do.
    private func stepCaption(_ step: FlameyJourneyStep) -> some View {
        HStack(spacing: 8) {
            if let item = tapped, picks[item.slot] == item || item.slot.basicItem == item {
                if let medal = model.medal(for: item) {
                    FlameyMedalDisc(medal: medal, size: 24)
                } else {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(FlameyClosetStyle.ember)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.displayName)
                        .madFont(size: 14.5, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white)
                    Text(FlameyStage.medalLine(item, model: model))
                        .madFont(size: 12, weight: .semibold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.6))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            } else {
                Text("Every tile wears the medal that unlocked it.")
                    .madFont(size: 12.5, weight: .semibold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .accessibilityElement(children: .combine)
    }

    private func stepRows(_ page: FlameyJourneyPage) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4)
        return VStack(alignment: .leading, spacing: 18) {
            ForEach(page.rows, id: \.slot) { row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.slot.pickLabel)
                            .madFont(size: 13, weight: .black, design: .rounded, maxScale: 1.4)
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Text(selectionLabel(row.slot))
                            .madFont(size: 11.5, weight: .bold, design: .rounded, maxScale: 1.3)
                            .foregroundColor(picks[row.slot] != nil ? .white : .white.opacity(0.4))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(row.slot.familyRule)
                        .madFont(size: 12, weight: .semibold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: columns, spacing: 8) {
                        if row.slot.basicItem == nil {
                            FlameyPickTile(item: nil, slot: row.slot, selected: picks[row.slot] == nil,
                                           medal: nil, color: stageLook.color) {
                                MADHaptics.tap()
                                pick(nil, in: row.slot)
                            }
                        }
                        ForEach(row.items, id: \.self) { item in
                            FlameyPickTile(item: item, slot: row.slot, selected: isPicked(item),
                                           medal: model.medal(for: item), color: stageLook.color,
                                           isNew: model.newItems.contains(item)) {
                                MADHaptics.tap()
                                pick(item, in: row.slot)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private func isPicked(_ item: FlameyItem) -> Bool {
        if let picked = picks[item.slot] { return picked == item }
        return item.slot.basicItem == item
    }

    private func selectionLabel(_ slot: FlameySlot) -> String {
        if let item = picks[slot] { return item.displayName }
        return slot.basicItem?.displayName ?? "None"
    }

    // What's next

    private func morePage(_ page: FlameyJourneyPage) -> some View {
        let next = FlameyJourney.nextToEarn(model)
        let left = model.tally.total - model.tally.owned
        return VStack(spacing: 14) {
            titleBlock(eyebrow: "More to earn",
                       title: left == 0 ? "You've unlocked it all" : "\(left) more to unlock",
                       body: left == 0 ? "Every medal, every item. He's the best-dressed flame there is." : "Every medal adds something. Here's what you're closest to.")
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
