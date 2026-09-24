import SwiftUI

/// Flamey's Closet: dress him in what you've earned.
///
/// ONE scroll. At the top a compact stage — Flamey as he looks right now, a
/// line about the last thing you touched, and the three whole-look actions
/// (Best look · Surprise me · Basic). Under it a PINNED header: the four tabs
/// (Colour · Outfit · Extras · Bubble) and, on the tabs that hold several
/// slots, a jump row. Each tab is its slots stacked as sections with a count
/// ("Hats · 3 of 19"), four item tiles to a row — nothing hidden behind a
/// sub-chip. Scroll and the stage slides away (a small Flamey docks beside
/// the tabs so you still see him), leaving the grid most of the screen.
///
/// Picking: tap something you own to wear it (tap it again to take it off),
/// every change with an Undo toast; tap something locked — or long-press
/// anything — for its card: the medal it comes from, when you earned it, or
/// how and WHERE to earn it. Nothing is ever put on him that you didn't pick.
///
/// Fun-only by construction: the hosts only present it on Fun.
struct FlameyClosetView: View {
    @State var model: FlameyClosetModel
    var onDone: () -> Void = {}
    /// "What I've unlocked" — the host shows the first-run walkthrough again.
    var onShowJourney: () -> Void = {}
    /// False only for a snapshot (ImageRenderer can't see into a ScrollView).
    var scrollable: Bool = true
    /// Snapshot of the scrolled state (the harness).
    var previewCollapsed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var lineClear: Task<Void, Never>?
    @State private var collapsed = false

    private var columns: [GridItem] {
        let count = typeSize >= .accessibility1 ? 3 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: count)
    }

    private var isCollapsed: Bool { collapsed || previewCollapsed }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if scrollable {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            stageBlock
                                .background(collapseProbe)
                            Section {
                                sections
                            } header: {
                                pinnedHeader { slot in
                                    withAnimation(reduceMotion ? nil : .snappy) {
                                        proxy.scrollTo(anchorId(slot), anchor: .top)
                                    }
                                }
                            }
                        }
                    }
                    .coordinateSpace(name: "closet")
                    .scrollIndicators(.hidden)
                    .onPreferenceChange(StageBottomKey.self) { bottom in
                        let now = bottom < 24
                        guard now != collapsed else { return }
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { collapsed = now }
                    }
                    .onChange(of: model.tab) { _, _ in
                        guard collapsed, let first = model.tab.slots.first else { return }
                        proxy.scrollTo(anchorId(first), anchor: .top)
                    }
                }
            } else {
                if !previewCollapsed { stageBlock }
                pinnedHeader { _ in }
                sections
                Spacer(minLength: 0)
            }
        }
        .background(background.ignoresSafeArea())
        .overlay(alignment: .bottom) { toastOverlay }
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
            .accessibilityHint("Walks you through what your medals have unlocked")
            Spacer(minLength: 0)
            Text("Flamey's Closet")
                .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button(action: onDone) {
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

    // MARK: Stage

    private var stageBlock: some View {
        VStack(spacing: 8) {
            // The whole-look actions stand BESIDE him, not in a row of their
            // own: every point of height up here is a row of tiles lost.
            HStack(alignment: .center, spacing: 10) {
                stage
                actionColumn
                    .frame(width: 138)
            }
            .padding(.horizontal, 16)
            caption
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 6)
    }

    /// Reports where the stage block ends, so the header can dock a small
    /// Flamey once he has scrolled away. Only an opacity/width change hangs
    /// off it — never the height of anything above the scroll.
    private var collapseProbe: some View {
        GeometryReader { geo in
            Color.clear.preference(key: StageBottomKey.self, value: geo.frame(in: .named("closet")).maxY - 70)
        }
    }

    private var stage: some View {
        let size: CGFloat = 104
        var mood = FlameMood(kind: .ready, streak: 0)
        // He speaks only about the selection — except on the Bubble tab,
        // where the bubble IS the item and has to be on screen to be judged.
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
                .accessibilityLabel(stageAccessibilityLabel)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 136, alignment: .bottom)
    }

    private var stageAccessibilityLabel: String {
        let worn = model.stageLook.items.filter { !$0.isMoodProp && $0 != .classic && $0 != .classicBubble }
        guard !worn.isEmpty else { return "Flamey, basic — wearing nothing" }
        return "Flamey, wearing " + worn.map(\.displayName).joined(separator: ", ")
    }

    /// Under him: the item you last touched (with a way to its card), else
    /// what state he's in and how much is unlocked. Fixed height, so tapping
    /// around never shoves the grid.
    @ViewBuilder
    private var caption: some View {
        Group {
            if let item = model.focus {
                Button {
                    MADHaptics.tap()
                    model.detail = item
                } label: {
                    HStack(spacing: 6) {
                        if let medal = model.medal(for: item) {
                            FlameyMedalDisc(medal: medal, size: 22)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.displayName)
                                .madFont(size: 14, weight: .heavy, design: .rounded)
                                .foregroundColor(.white)
                            Text(focusDetail(item))
                                .madFont(size: 11.5, weight: .semibold, design: .rounded)
                                .foregroundColor(.white.opacity(0.55))
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
                        Text(model.isBasic ? "Basic Flamey — tap anything you've unlocked to put it on"
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
        .frame(height: 48)
    }

    private func focusDetail(_ item: FlameyItem) -> String {
        if let medal = model.medal(for: item) {
            let name = medal.name ?? item.unlockCopy
            return model.owns(item) ? "From \(name)" : "Locked · \(name)"
        }
        return "\(item.slot.shortLabel) · always his"
    }

    private var actionColumn: some View {
        VStack(spacing: 8) {
            actionPill("Best look", icon: "sparkles", hint: "Puts on the best thing you own in each slot") {
                MADHaptics.success()
                withAnimation(reduceMotion ? nil : .snappy) { model.bestLook() }
            }
            actionPill("Surprise me", icon: "dice.fill", hint: "A random mix of things you own") {
                MADHaptics.emphasis()
                withAnimation(reduceMotion ? nil : .snappy) { model.surprise() }
            }
            actionPill("Basic", icon: "arrow.uturn.backward", hint: "Takes everything off — the original Flamey",
                       enabled: !model.isBasic) {
                MADHaptics.tap()
                withAnimation(reduceMotion ? nil : .snappy) { model.resetToBasic() }
            }
        }
    }

    private func actionPill(_ title: String, icon: String, hint: String, enabled: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .madFont(size: 11, weight: .bold, maxScale: 1.3)
                    .accessibilityHidden(true)
                Text(title)
                    .madFont(size: 12.5, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(.white.opacity(enabled ? 0.92 : 0.35))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityHint(hint)
    }

    // MARK: Pinned header (tabs + jump row)

    private func pinnedHeader(jump: @escaping (FlameySlot) -> Void) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if isCollapsed {
                    FlameyDressedFigure(look: model.stageLook, health: .healthy, size: 34, scale: 1)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(stageGlow.opacity(0.16)))
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
                tabPicker
            }
            if model.tab.slots.count > 1 {
                jumpRow(jump)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(
            Color(red: 0.08, green: 0.035, blue: 0.045)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                .opacity(isCollapsed ? 1 : 0.0)
        )
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
        VStack(alignment: .leading, spacing: 20) {
            ForEach(model.tab.slots, id: \.self) { slot in
                section(slot)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 96)
    }

    private func section(_ slot: FlameySlot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
            .background(alignment: .top) {
                // The jump target sits ABOVE the title by the pinned
                // header's height, so a jump lands the title under it.
                Color.clear.frame(height: 1).id(anchorId(slot)).padding(.top, -104)
            }
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

    // MARK: Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = model.toast {
            FlameyUndoToast(toast: toast) {
                MADHaptics.tap()
                withAnimation(reduceMotion ? nil : .snappy) { model.undo() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(4))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { model.clearToast(toast.id) }
            }
        }
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

private struct StageBottomKey: PreferenceKey {
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
        .accessibilityLabel(hasNews ? "Flamey's Closet, new" : "Flamey's Closet")
        .accessibilityHint("Dress Flamey in what you've earned")
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
                    Text("Flamey's Closet")
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
        .accessibilityHint("Opens Flamey's Closet")
    }
}
