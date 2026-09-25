import SwiftUI

/// Flamey's Closet: dress him in what you've earned.
///
/// The PREVIEW NEVER LEAVES. Everything above the grid is a fixed header —
/// never part of the scroll — so he is always on screen, fully dressed, while
/// you pick: at the top of the grid a roomy stage (him, his bubble with room
/// to speak, a caption naming the last thing you touched and the MEDAL it
/// came from, and Best look · Surprise me · Basic beside him); once you scroll
/// the stage shrinks to a compact but readable one (~140pt, the caption and
/// the three actions beside him) instead of scrolling away. Under it the
/// tabs (Color · Outfit · Extras · Bubble) and a jump row, then a hairline;
/// the grid scrolls in its own frame below that line, so nothing can ever
/// slide under the tabs.
///
/// Each tab is its slots stacked as sections — "Shoes · 5 of 8", the one
/// sentence saying which medals fill that slot, then 4-up item tiles, each
/// wearing its medal on the corner. Tap something you own to try it on (tap
/// again to take it off), every change with an Undo toast; tap something
/// locked — or long-press anything — for its card.
///
/// It is an EDITING SESSION: every tap changes a draft on the stage, and
/// nothing he wears elsewhere changes until Save. While the draft differs
/// from what's saved, `FlameySaveBar` sits at the bottom (Discard · Save),
/// and Done asks "Save changes to Sparky's look?". Saved outfits sit under
/// the stage as a shortcut row (and a full page of cards behind "See all")
/// and load into the draft the same way. His NAME is the plate under him
/// ("Sparky ✎" / "Name your flame") — the title is just a title.
///
/// Fun-only by construction: the hosts only present it on Fun.
struct FlameyClosetView: View {
    @State var model: FlameyClosetModel
    var onDone: () -> Void = {}
    /// "What I've unlocked" — the host shows the first-run walkthrough again.
    var onShowJourney: () -> Void = {}
    /// False only for a snapshot (ImageRenderer can't see into a ScrollView).
    var scrollable: Bool = true
    /// Snapshot of the scrolled state (the harness): compact stage, and the
    /// grid drawn this far up under the header's hairline.
    var previewCollapsed: Bool = false
    var previewScroll: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var lineClear: Task<Void, Never>?
    @State private var collapsed = false
    @State private var sheet: ClosetSheet?

    /// The Closet's own sheets (the item card rides `model.detail`, on a
    /// different node — two sheets on one node drop one).
    enum ClosetSheet: String, Identifiable {
        case name, saveOutfit, outfits
        var id: String { rawValue }
    }

    private var columns: [GridItem] {
        let count = typeSize >= .accessibility1 ? 3 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: count)
    }

    private var isCollapsed: Bool { collapsed || previewCollapsed }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .sheet(item: $sheet) { which in
                    sheetView(which)
                }
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    header { slot in
                        withAnimation(reduceMotion ? nil : .snappy) {
                            proxy.scrollTo(anchorId(slot), anchor: .top)
                        }
                    }
                    grid
                }
                .onChange(of: model.tab) { _, _ in
                    proxy.scrollTo("closet-top", anchor: .top)
                }
                .onAppear {
                    // Opened ON an item (a medal's "See it in Flamey's
                    // Closet", the unlock card): land on its section.
                    guard scrollable, let focus = model.focus else { return }
                    DispatchQueue.main.async { proxy.scrollTo(anchorId(focus.slot), anchor: .top) }
                }
            }
        }
        // The Closet has no field of its own; a keyboard raised by one of
        // its sheets must not shrink it (the header, the grid, the dock).
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(background.ignoresSafeArea())
        .overlay(alignment: .bottom) { bottomDock }
        .overlay {
            if model.leavePrompt != nil {
                FlameyLeavePromptCard(name: model.displayName, saved: model.look(for: model.savedChoice),
                                      draft: model.stageLook, changes: model.changedSlotCount) { answer in
                    switch answer {
                    case .save: MADHaptics.success()
                    case .discard: MADHaptics.warning()
                    case .keepEditing: MADHaptics.tap()
                    }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { model.answerLeave(answer) }
                }
                .transition(.opacity)
            }
        }
        .madTypeCap(.madCardCap)
        .onChange(of: model.lineAt) { _, _ in scheduleLineClear() }
        .sheet(item: $model.detail) { item in
            FlameyItemDetailView(item: item, model: model, onClose: { model.detail = nil })
                .presentationDetents([.height(500), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(FlameyClosetStyle.ground)
        }
    }

    private func anchorId(_ slot: FlameySlot) -> String { "section-\(slot.rawValue)" }

    @ViewBuilder
    private func sheetView(_ which: ClosetSheet) -> some View {
        switch which {
        // Typing sheets are LARGE: their Save lives in the bar at the top,
        // and a large sheet never has to move for the keyboard.
        case .name:
            FlameyNameEditor(model: model) { sheet = nil }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(FlameyClosetStyle.ground)
        case .saveOutfit:
            FlameyOutfitNameSheet(model: model) { sheet = nil }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(FlameyClosetStyle.ground)
        case .outfits:
            FlameyOutfitsSheet(model: model) { sheet = nil }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(FlameyClosetStyle.ground)
        }
    }

    /// Done / close: asks first when the draft isn't saved.
    private func close() {
        MADHaptics.tap()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { model.leave(onDone) }
    }

    // MARK: The grid (the only thing that scrolls)

    @ViewBuilder
    private var grid: some View {
        if scrollable {
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("closet-top")
                        .background(scrollProbe)
                    sections
                }
            }
            .coordinateSpace(name: "closet-grid")
            .scrollIndicators(.hidden)
            .onPreferenceChange(GridScrollKey.self) { top in
                // Hysteresis, so the header can't flicker at the boundary.
                let next = collapsed ? top < -6 : top < -48
                guard next != collapsed else { return }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { collapsed = next }
            }
        } else {
            Color.clear
                .overlay(alignment: .top) { sections.offset(y: -previewScroll) }
                .clipped()
        }
    }

    private var scrollProbe: some View {
        GeometryReader { geo in
            Color.clear.preference(key: GridScrollKey.self, value: geo.frame(in: .named("closet-grid")).minY)
        }
    }

    // MARK: Chrome

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.20, green: 0.07, blue: 0.09),
                                    Color(red: 0.09, green: 0.04, blue: 0.05), .black],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [stageGlow.opacity(0.2), .clear], center: UnitPoint(x: 0.5, y: 0.14),
                           startRadius: 0, endRadius: 280)
        }
    }

    private var stageGlow: Color {
        FlameyPalette.palette(for: model.stageLook.color)?.glow ?? Color(red: 1, green: 0.55, blue: 0.2)
    }

    private var topBar: some View {
        HStack {
            Button {
                MADHaptics.tap()
                onShowJourney()
            } label: {
                Image(systemName: "sparkles")
                    .madFont(size: 16, weight: .bold, maxScale: 1.3)
                    .foregroundColor(FlameyClosetStyle.ember)
                    .frame(width: 60, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("What I've unlocked")
            .accessibilityHint("Walks you through dressing him in what your medals have unlocked")
            Spacer(minLength: 0)
            // Just a title: renaming lives on his name plate, under him.
            Text("\(model.possessiveName) Closet")
                .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button(action: close) {
                Text("Done")
                    .madFont(size: 16, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(FlameyClosetStyle.ember)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 60, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    // MARK: The fixed header — stage, tabs, jump row

    private func header(jump: @escaping (FlameySlot) -> Void) -> some View {
        VStack(spacing: 0) {
            if isCollapsed {
                HStack(alignment: .center, spacing: 10) {
                    stage(size: 80)
                        .frame(width: 142)
                    VStack(alignment: .leading, spacing: 10) {
                        compactCaption
                        HStack(spacing: 8) { actionButtons(compact: true) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .transition(.opacity)
            } else {
                VStack(spacing: 6) {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(spacing: -4) {
                            stage(size: 100)
                            FlameyNamePlate(name: model.name) {
                                MADHaptics.tap()
                                sheet = .name
                            }
                        }
                        VStack(spacing: 8) { actionButtons(compact: false) }
                            .frame(width: 138)
                    }
                    caption
                }
                .padding(.horizontal, 16)
                .transition(.opacity)
                FlameyOutfitsShortcut(model: model, scrollable: scrollable) {
                    MADHaptics.tap()
                    sheet = .outfits
                } onSaveLook: {
                    MADHaptics.tap()
                    sheet = .saveOutfit
                }
                .padding(.top, 8)
                .transition(.opacity)
            }
            tabsAndJump(jump)
            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
        }
    }

    // MARK: Stage

    /// Him, as he looks right now. Room for his bubble is RESERVED above him
    /// (`FlameyStage.bubbleRoom`) at every size, so every bubble style draws
    /// whole — the old stage let the scroll view's edge slice it to a bar.
    private func stage(size: CGFloat) -> some View {
        var mood = FlameMood(kind: .ready, streak: 0)
        // He speaks about the selection — and always on the Bubble tab, where
        // the bubble IS the item and has to be on screen to be judged.
        let line = model.line ?? (model.tab == .style ? "How do I sound?" : nil)
        mood.pokeQuip = line
        mood.pokedAt = model.lineAt
        return ZStack(alignment: .bottom) {
            Ellipse()
                .fill(RadialGradient(colors: [stageGlow.opacity(0.35), Color.white.opacity(0.04), .clear],
                                     center: .center, startRadius: 1, endRadius: size * 0.9))
                .frame(width: size * 1.9, height: size * 0.24)
            FlameBuddyView(health: .healthy, size: size, mood: mood, still: !scrollable,
                           showsMoodBubble: line != nil, look: model.stageLook)
                .frame(width: size, height: size)
                .padding(.bottom, size * 0.11)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(FlameyStage.accessibilityLabel(model.stageLook, name: model.displayName))
        }
        .frame(maxWidth: .infinity)
        .frame(height: size * 1.11 + FlameyStage.bubbleRoom(size), alignment: .bottom)
    }

    /// Under him: the item you last touched and the MEDAL it came from (with
    /// a way to its card), else what state he's in. Fixed height, so tapping
    /// around never shoves the grid.
    @ViewBuilder
    private var caption: some View {
        Group {
            if let item = model.focus {
                Button {
                    MADHaptics.tap()
                    model.detail = item
                } label: {
                    HStack(spacing: 8) {
                        focusBadge(item, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.displayName)
                                .madFont(size: 14, weight: .heavy, design: .rounded)
                                .foregroundColor(.white)
                            Text(FlameyStage.medalLine(item, model: model))
                                .madFont(size: 11.5, weight: .semibold, design: .rounded)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        Spacer(minLength: 6)
                        Text("Details")
                            .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.3)
                            .foregroundColor(FlameyClosetStyle.ember)
                            .fixedSize()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(FlameyClosetStyle.ember)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens its card")
            } else {
                Button {
                    MADHaptics.tap()
                    onShowJourney()
                } label: {
                    VStack(spacing: 2) {
                        Text(model.isBasic ? "Basic \(model.displayName) — tap anything you've unlocked to try it on"
                                           : "Tap what he's wearing to take it off")
                            .madFont(size: 12.5, weight: .semibold, design: .rounded)
                            .foregroundColor(.white.opacity(0.62))
                        HStack(spacing: 4) {
                            Text("\(model.tally.owned) of \(model.tally.total) unlocked")
                                .madFont(size: 12, weight: .heavy, design: .rounded, monospacedDigit: true)
                                .foregroundColor(.white.opacity(0.85))
                            Text("· See what you've unlocked")
                                .madFont(size: 12, weight: .heavy, design: .rounded)
                                .foregroundColor(FlameyClosetStyle.ember)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Walks you through what your medals have unlocked")
            }
        }
        .frame(height: 46)
    }

    /// The scrolled caption, beside him: what you last touched and its medal
    /// on two lines, tappable for the card — else the tally.
    @ViewBuilder
    private var compactCaption: some View {
        if let item = model.focus {
            Button {
                MADHaptics.tap()
                model.detail = item
            } label: {
                HStack(spacing: 7) {
                    focusBadge(item, size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.displayName)
                            .madFont(size: 13.5, weight: .heavy, design: .rounded, maxScale: 1.3)
                            .foregroundColor(.white)
                        Text(FlameyStage.medalLine(item, model: model))
                            .madFont(size: 11, weight: .semibold, design: .rounded, maxScale: 1.3)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens its card")
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.isBasic ? "Basic \(model.displayName)" : (model.choice.items.count == 1 ? "Wearing 1 pick" : "Wearing \(model.choice.items.count) picks"))
                    .madFont(size: 13.5, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                Text("\(model.tally.owned) of \(model.tally.total) unlocked")
                    .madFont(size: 11, weight: .semibold, design: .rounded, maxScale: 1.3, monospacedDigit: true)
                    .foregroundColor(.white.opacity(0.6))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func focusBadge(_ item: FlameyItem, size: CGFloat) -> some View {
        if let medal = model.medal(for: item) {
            FlameyMedalDisc(medal: medal, size: size)
        } else {
            Image(systemName: "gift.fill")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(FlameyClosetStyle.ember)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    // MARK: Whole-look actions

    /// Best look · Surprise me · Basic — labelled pills beside the big stage,
    /// labelled icon discs beside the compact one.
    @ViewBuilder
    private func actionButtons(compact: Bool) -> some View {
        actionPill("Best look", icon: "sparkles", compact: compact,
                   hint: "Tries on the best thing you own in each slot") {
            MADHaptics.success()
            withAnimation(reduceMotion ? nil : .snappy) { model.bestLook() }
        }
        actionPill("Surprise me", icon: "dice.fill", compact: compact, hint: "Tries on a random mix of things you own") {
            MADHaptics.emphasis()
            withAnimation(reduceMotion ? nil : .snappy) { model.surprise() }
        }
        actionPill("Basic", icon: "arrow.uturn.backward", compact: compact,
                   hint: "Takes everything off — the original look", enabled: !model.isBasic) {
            MADHaptics.tap()
            withAnimation(reduceMotion ? nil : .snappy) { model.resetToBasic() }
        }
    }

    private func actionPill(_ title: String, icon: String, compact: Bool, hint: String, enabled: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if compact {
                    Image(systemName: icon)
                        .madFont(size: 13, weight: .bold, maxScale: 1.3)
                        .frame(width: 40, height: 36)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                        .contentShape(Capsule())
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .madFont(size: 11, weight: .bold, maxScale: 1.3)
                            .accessibilityHidden(true)
                        Text(title)
                            .madFont(size: 12.5, weight: .heavy, design: .rounded, maxScale: 1.3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .contentShape(Capsule())
                }
            }
            .foregroundColor(.white.opacity(enabled ? 0.92 : 0.35))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    // MARK: Tabs + jump row

    private func tabsAndJump(_ jump: @escaping (FlameySlot) -> Void) -> some View {
        VStack(spacing: 8) {
            tabPicker
            if model.tab.slots.count > 1 {
                jumpRow(jump)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(FlameyClosetTab.allCases) { tab in
                let selected = model.tab == tab
                let counts = model.counts(for: tab)
                Button {
                    guard model.tab != tab else { return }
                    MADHaptics.tap()
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { model.tab = tab }
                } label: {
                    Text(tab.title)
                        .madFont(size: 14, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundColor(selected ? .black : .white.opacity(0.66))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selected { Capsule().fill(Color.white) }
                        }
                        .overlay(alignment: .topTrailing) {
                            if model.hasNew(in: tab) { newDot.offset(x: -6, y: 5) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tab.title), \(counts.owned) of \(counts.total) unlocked"
                                    + (model.hasNew(in: tab) ? ", new items" : ""))
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private func jumpRow(_ jump: @escaping (FlameySlot) -> Void) -> some View {
        let row = HStack(spacing: 6) {
            ForEach(model.tab.slots, id: \.self) { slot in
                Button {
                    MADHaptics.tap()
                    jump(slot)
                } label: {
                    HStack(spacing: 4) {
                        Text(slot.shortLabel)
                            .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.3)
                            .foregroundColor(.white.opacity(0.85))
                        Text("\(model.ownedCount(in: slot))")
                            .madFont(size: 11, weight: .bold, design: .rounded, maxScale: 1.3, monospacedDigit: true)
                            .foregroundColor(.white.opacity(0.45))
                        if model.hasNew(in: slot) { newDot }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Jump to \(slot.closetLabel), \(model.ownedCount(in: slot)) unlocked")
            }
        }
        if scrollable {
            ScrollView(.horizontal) { row }
                .scrollIndicators(.hidden)
        } else {
            Color.clear.frame(height: 30).overlay(alignment: .leading) { row.fixedSize() }.clipped()
        }
    }

    private var newDot: some View {
        Circle().fill(FlameyClosetStyle.newDot).frame(width: 7, height: 7).accessibilityHidden(true)
    }


    // MARK: Sections

    private var sections: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(model.tab.slots, id: \.self) { slot in
                section(slot)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        // Constant: room for the dock whether or not it's up, so showing it
        // never changes the scroll content under it.
        .padding(.bottom, FlameySaveBar.height + 40)
    }

    private func section(_ slot: FlameySlot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(slot.closetLabel)
                        .madFont(size: 13, weight: .black, design: .rounded, maxScale: 1.4)
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(model.ownedCount(in: slot)) of \(model.totalCount(in: slot))")
                        .madFont(size: 12, weight: .bold, design: .rounded, maxScale: 1.4, monospacedDigit: true)
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                        .accessibilityLabel("\(model.ownedCount(in: slot)) of \(model.totalCount(in: slot)) unlocked")
                    Spacer(minLength: 8)
                    if let worn = model.worn(in: slot) {
                        Text("Wearing \(worn.displayName)")
                            .madFont(size: 11.5, weight: .bold, design: .rounded, maxScale: 1.3)
                            .foregroundColor(FlameyClosetStyle.worn)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                // Which medals fill this slot — said once, here, so the medal
                // on each tile below reads as a ladder, not a coincidence.
                Text(slot.familyRule)
                    .madFont(size: 12, weight: .semibold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(anchorId(slot))
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(model.items(in: slot), id: \.self) { item in
                    FlameyClosetTile(item: item, model: model) {
                        if model.owns(item) { MADHaptics.success() } else { MADHaptics.tap() }
                        withAnimation(reduceMotion ? nil : .snappy) { model.tap(item) }
                    } onDetails: {
                        MADHaptics.action()
                        model.detail = item
                    }
                }
            }
        }
    }

    // MARK: The bottom dock — the save bar, or a toast

    /// Pinned to the BOTTOM SAFE AREA and nothing else. It used to be an
    /// overlay on a view that honoured the KEYBOARD inset too, so whenever
    /// one of the Closet's own sheets raised the keyboard (naming him, naming
    /// an outfit) the inset reached the cover underneath and the bar rode up
    /// with it, then dropped back — and it sat inside every `withAnimation`
    /// the Closet runs (each tap, the header collapsing on scroll), so its
    /// insertion and its note were animated by whatever else was moving. Now:
    /// `.ignoresSafeArea(.keyboard)`, a fixed height, always in the tree
    /// (shown by opacity + a short slide keyed ONLY on the draft state), and
    /// every other transaction stripped from it.
    private var bottomDock: some View {
        let dirty = model.hasUnsavedChanges
        return ZStack(alignment: .bottom) {
            FlameySaveBar(changes: model.changedSlotCount, possessiveName: model.possessiveName,
                          note: dirty ? model.toast?.text : nil,
                          onUndo: model.toast?.undo == nil ? nil : {
                              MADHaptics.tap()
                              withAnimation(reduceMotion ? nil : .snappy) { model.undo() }
                          }) {
                MADHaptics.tap()
                withAnimation(reduceMotion ? nil : .snappy) { model.discardDraft() }
            } onSave: {
                MADHaptics.success()
                withAnimation(reduceMotion ? nil : .snappy) { model.saveDraft() }
            }
            .transaction { $0.animation = nil }
            .opacity(dirty ? 1 : 0)
            .offset(y: dirty ? 0 : 24)
            .allowsHitTesting(dirty)
            .accessibilityHidden(!dirty)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: dirty)
            if !dirty, let toast = model.toast {
                FlameyUndoToast(toast: toast) {
                    MADHaptics.tap()
                    withAnimation(reduceMotion ? nil : .snappy) { model.undo() }
                }
                .padding(.horizontal, 8)
                .frame(height: FlameySaveBar.height, alignment: .bottom)
                .id(toast.id)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(height: FlameySaveBar.height + 8, alignment: .bottom)
        .task(id: model.toast?.id) {
            // The bar's note fades back to the change count, and a toast
            // goes, after a few seconds.
            guard let id = model.toast?.id else { return }
            try? await Task.sleep(for: .seconds(4))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { model.clearToast(id) }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func scheduleLineClear() {
        lineClear?.cancel()
        lineClear = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2600))
            guard !Task.isCancelled else { return }
            model.clearLine()
        }
    }
}

private struct GridScrollKey: PreferenceKey {
    static let defaultValue: CGFloat = 1000
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension FlameyItem: Identifiable {
    var id: String { rawValue }
}

// MARK: - Entry-point faces (pure; the live wrappers open the Closet)

/// The hero's Closet capsule: hanger + "Closet", the savers chip's outlined
/// weight so it reads as a sibling control, never louder than Share. A dot
/// (and "New" to VoiceOver) while there's something to see — the first-run
/// walkthrough not yet taken, or items unlocked since the last visit.
struct FlameyClosetPill: View {
    var hasNews: Bool = false
    /// His name, for VoiceOver ("Sparky's Closet").
    var name: String = FlameyNameRules.fallback
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "hanger")
                    .madFont(size: 11, weight: .bold, maxScale: 1.3)
                    .accessibilityHidden(true)
                Text("Closet")
                    .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .overlay(Capsule().strokeBorder(hasNews ? FlameyClosetStyle.ember.opacity(0.7) : Color.white.opacity(0.16), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if hasNews {
                    Circle().fill(FlameyClosetStyle.newDot)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
                        .offset(x: 2, y: -2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasNews ? "\(FlameyNameRules.possessive(name)) Closet, new" : "\(FlameyNameRules.possessive(name)) Closet")
        .accessibilityHint("Dress \(name) in what you've earned")
    }
}

/// The profile's "Flamey's Closet" row: his current look, the tally, and
/// how many things are new.
struct FlameyClosetProfileCard: View {
    let look: FlameyLook
    let unlocked: Int
    let total: Int
    let fresh: Int
    /// The first-run walkthrough hasn't been taken.
    var firstVisit: Bool = false
    /// His name ("Sparky's Closet").
    var name: String = FlameyNameRules.fallback
    var action: () -> Void

    private var subtitle: String {
        if firstVisit { return unlocked > 0 ? "Your medals unlocked \(unlocked) items — take a look" : "See what your medals unlock" }
        if fresh > 0 { return "\(fresh) new · \(unlocked) of \(total) unlocked" }
        return "\(unlocked) of \(total) unlocked"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                FlameyDressedFigure(look: look, health: .healthy, size: 44, scale: 1)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(FlameyNameRules.possessive(name)) Closet")
                        .madFont(size: 15, weight: .heavy, design: .rounded)
                        .foregroundColor(.white)
                    Text(subtitle)
                        .madFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundColor(fresh > 0 || firstVisit ? FlameyClosetStyle.ember : .white.opacity(0.55))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if firstVisit || fresh > 0 {
                    Text("NEW")
                        .madFont(size: 9, weight: .black, design: .rounded, maxScale: 1.2)
                        .tracking(0.6)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(FlameyClosetStyle.newDot))
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right")
                    .madFont(size: 13, weight: .bold, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.4))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(FlameyNameRules.possessive(name)) Closet")
    }
}
