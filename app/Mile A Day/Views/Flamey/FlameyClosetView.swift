import SwiftUI

/// Flamey's Closet: dress him in what you've earned.
///
/// A live Flamey on a stage (full detail, animated, saying something about
/// what he just put on), then four tabs of 3-column grids — Flame · Outfit ·
/// Extras · Style — each slot opening with AUTO ("best I own") and, where it
/// means anything, NONE. Owned items wear on tap; a LOCKED one is tried on
/// (the stage shows it with its unlock line, nothing is saved). Every change
/// leaves through `model.onChoiceChange`, which the live glue debounces to
/// the server.
///
/// Fun-only by construction: the hosts only present it on Fun.
struct FlameyClosetView: View {
    @State var model: FlameyClosetModel
    var onDone: () -> Void = {}
    /// False only for a snapshot (ImageRenderer can't see into a ScrollView).
    var scrollable: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lineClear: Task<Void, Never>?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                topBar
                stage(height: stageHeight(for: geo.size.height))
                statusStrip
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                tabPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                if scrollable {
                    ScrollView { grid }
                        .scrollIndicators(.hidden)
                } else {
                    grid
                    Spacer(minLength: 0)
                }
            }
        }
        .background(background.ignoresSafeArea())
        .madTypeCap(.madCardCap)
        .onChange(of: model.lineAt) { _, _ in scheduleLineClear() }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.tab.slots.count > 1 { slotChips }
            sectionHeader
            LazyVGrid(columns: columns, spacing: 10) {
                tiles
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 32)
    }

    private func stageHeight(for available: CGFloat) -> CGFloat {
        min(300, max(190, available * 0.31))
    }

    // MARK: Chrome

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.20, green: 0.07, blue: 0.09),
                                    Color(red: 0.09, green: 0.04, blue: 0.05), .black],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [stageGlow.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.22),
                           startRadius: 0, endRadius: 320)
        }
    }

    private var stageGlow: Color {
        FlameyPalette.palette(for: model.stageLook.color)?.glow ?? Color(red: 1, green: 0.55, blue: 0.2)
    }

    private var topBar: some View {
        HStack {
            // Balances Done so the title centres on the screen.
            Color.clear.frame(width: 60, height: 1)
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
        .frame(height: 48)
    }

    // MARK: Stage

    private func stage(height: CGFloat) -> some View {
        let size = min(176, height * 0.62)
        var mood = FlameMood(kind: .ready, streak: 0)
        // He speaks only about the selection (never the dashboard's rotating
        // mood lines) — except on the Style tab, where the bubble IS the item
        // and has to be on screen to be judged.
        let line = model.line ?? (model.tab == .style ? "How do I sound?" : nil)
        mood.pokeQuip = line
        mood.pokedAt = model.lineAt
        return ZStack(alignment: .bottom) {
            // The floor he stands on.
            Ellipse()
                .fill(RadialGradient(colors: [stageGlow.opacity(0.35), Color.white.opacity(0.04), .clear],
                                     center: .center, startRadius: 1, endRadius: size * 0.9))
                .frame(width: size * 1.9, height: size * 0.26)
                .offset(y: -size * 0.02)
            Ellipse()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: size * 1.7, height: size * 0.22)
                .offset(y: -size * 0.03)

            FlameBuddyView(health: .healthy, size: size, mood: mood, showsMoodBubble: line != nil,
                           look: model.stageLook)
                .frame(width: size, height: size)
                .padding(.bottom, size * 0.14)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stageAccessibilityLabel)

            // The top corners are the stage's one empty space: his hat and
            // bubble are centred, capes and trails spread at mid-height and
            // jets reach the floor.
            stageButtons
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .bottom)
    }

    private var stageAccessibilityLabel: String {
        let worn = model.stageLook.items.filter { !$0.isMoodProp && $0 != .classic && $0 != .classicBubble }
        guard !worn.isEmpty else { return "Flamey, wearing nothing special" }
        return "Flamey, wearing " + worn.map(\.displayName).joined(separator: ", ")
    }

    private var stageButtons: some View {
        HStack {
            stagePill("Best look", icon: "sparkles") {
                MADHaptics.tap()
                withAnimation(reduceMotion ? nil : .snappy) { model.bestLook() }
            }
            .accessibilityHint("Puts every slot back on Auto — the best items you own")
            Spacer(minLength: 8)
            stagePill("Surprise me", icon: "dice.fill") {
                MADHaptics.emphasis()
                withAnimation(reduceMotion ? nil : .snappy) { model.surprise() }
            }
            .accessibilityHint("Dresses Flamey in a random mix of things you own")
        }
        .padding(.horizontal, 16)
    }

    private func stagePill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .madFont(size: 11, weight: .bold, maxScale: 1.3)
                    .accessibilityHidden(true)
                Text(title)
                    .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundColor(.white.opacity(0.92))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Status strip (try-on banner / caption)

    @ViewBuilder
    private var statusStrip: some View {
        if let item = model.tryingOn {
            tryOnBanner(item)
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if let item = model.focus {
            caption(item)
                .transition(.opacity)
        } else {
            caption(nil)
        }
    }

    private func tryOnBanner(_ item: FlameyItem) -> some View {
        let progress = model.progress(for: item)
        return HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .madFont(size: 13, weight: .bold, maxScale: 1.3)
                .foregroundColor(.black.opacity(0.8))
                .frame(width: 30, height: 30)
                .background(Circle().fill(FlameyClosetStyle.ember))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Trying on \(item.displayName)")
                    .madFont(size: 14, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(unlockLine(item, progress: progress))
                    .madFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.66))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 6)
            Button {
                MADHaptics.tap()
                withAnimation(reduceMotion ? nil : .snappy) { model.takeOff() }
            } label: {
                Text("Take off")
                    .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 58)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.16, green: 0.10, blue: 0.06))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(FlameyClosetStyle.ember.opacity(0.55), lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
    }

    private func unlockLine(_ item: FlameyItem, progress: FlameyUnlockProgress?) -> String {
        var line = "Unlock: " + lowercasedFirst(item.unlockCopy)
        if let progress { line += " · " + progress.short }
        return line
    }

    private func lowercasedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }

    /// Under the stage: what the focused item is (and when a holiday item goes
    /// on by itself), or the tab's tally when nothing is focused. Always the
    /// same height, so tapping around never shoves the grid.
    private func caption(_ item: FlameyItem?) -> some View {
        VStack(spacing: 3) {
            if let item {
                Text(item.displayName)
                    .madFont(size: 15, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                Text(captionDetail(item))
                    .madFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
            } else {
                Text(tallyLine)
                    .madFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 58)
        .accessibilityElement(children: .combine)
    }

    private func captionDetail(_ item: FlameyItem) -> String {
        if let holiday = FlameyClosetCopy.holidayLine(item) { return holiday }
        if item.unlock == .always { return "\(item.slot.closetLabel) · always yours" }
        return "\(item.slot.closetLabel) · earned: " + lowercasedFirst(item.unlockCopy)
    }

    private var tallyLine: String {
        let all = FlameyClosetTab.allCases.map { model.counts(for: $0) }
        let owned = all.map(\.owned).reduce(0, +)
        let total = all.map(\.total).reduce(0, +)
        return "\(owned) of \(total) unlocked · tap anything locked to try it on"
    }

    // MARK: Tabs

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(FlameyClosetTab.allCases) { tab in
                let selected = model.tab == tab
                Button {
                    guard model.tab != tab else { return }
                    MADHaptics.tap()
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { model.tab = tab }
                } label: {
                    Text(tab.title)
                        .madFont(size: 14, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundColor(selected ? .black : .white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selected { Capsule().fill(Color.white) }
                        }
                        .overlay(alignment: .topTrailing) {
                            if model.hasNew(in: tab) && !selected { newDot.offset(x: -8, y: 6) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title + (model.hasNew(in: tab) ? ", new items" : ""))
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private var slotChips: some View {
        if scrollable {
            ScrollView(.horizontal) { slotChipRow }
                .scrollIndicators(.hidden)
        } else {
            slotChipRow
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()
        }
    }

    private var slotChipRow: some View {
            HStack(spacing: 8) {
                ForEach(model.tab.slots, id: \.self) { slot in
                    let selected = model.slot == slot
                    Button {
                        guard model.slot != slot else { return }
                        MADHaptics.tap()
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { model.slotForTab[model.tab] = slot }
                    } label: {
                        HStack(spacing: 5) {
                            Text(slot.closetLabel)
                                .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.3)
                            Text("\(model.ownedCount(in: slot))/\(model.items(in: slot).count)")
                                .madFont(size: 11, weight: .bold, design: .rounded, maxScale: 1.3, monospacedDigit: true)
                                .opacity(0.7)
                            if model.hasNew(in: slot) { newDot }
                        }
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundColor(selected ? .white : .white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(selected ? FlameyClosetStyle.chipSelected : Color.white.opacity(0.06)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(selected ? 0 : 0.08), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(slot.closetLabel), \(model.ownedCount(in: slot)) of \(model.items(in: slot).count) unlocked"
                                        + (model.hasNew(in: slot) ? ", new items" : ""))
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
    }

    private var sectionHeader: some View {
        let counts = model.counts(for: model.tab)
        return HStack(alignment: .firstTextBaseline) {
            Text(sectionTitle)
                .madFont(size: 12, weight: .black, design: .rounded, maxScale: 1.4)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundColor(FlameyClosetStyle.ember)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(counts.owned) of \(counts.total)")
                .madFont(size: 12, weight: .bold, design: .rounded, maxScale: 1.4, monospacedDigit: true)
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
                .accessibilityLabel("\(counts.owned) of \(counts.total) \(model.tab.title) items unlocked")
        }
    }

    private var sectionTitle: String {
        switch model.slot {
        case .color: return "Flame colours"
        case .bubble: return "Speech bubbles"
        default: return model.slot.closetLabel
        }
    }

    private var newDot: some View {
        Circle().fill(FlameyClosetStyle.newDot).frame(width: 7, height: 7).accessibilityHidden(true)
    }

    // MARK: Tiles

    @ViewBuilder
    private var tiles: some View {
        let slot = model.slot
        FlameyClosetTile(kind: .auto(model.autoItem(in: slot)), slot: slot, model: model) {
            wear(.auto, in: slot)
        }
        if slot.offersNone {
            FlameyClosetTile(kind: .none, slot: slot, model: model) {
                wear(.bare, in: slot)
            }
        }
        ForEach(model.items(in: slot), id: \.self) { item in
            FlameyClosetTile(kind: .item(item), slot: slot, model: model) {
                if model.owns(item) {
                    wear(.item(item), in: slot)
                } else {
                    MADHaptics.tap()
                    withAnimation(reduceMotion ? nil : .snappy) { model.tryOn(item) }
                }
            }
        }
    }

    private func wear(_ choice: FlameySlotChoice, in slot: FlameySlot) {
        MADHaptics.success()
        withAnimation(reduceMotion ? nil : .snappy) { model.select(choice, in: slot) }
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

// MARK: - Style

enum FlameyClosetStyle {
    static let ember = Color(red: 1.0, green: 0.72, blue: 0.35)
    static let newDot = Color(red: 1.0, green: 0.36, blue: 0.40)
    static let chipSelected = Color(red: 0.78, green: 0.15, blue: 0.33)
    static let tileFill = Color.white.opacity(0.055)
    static let tileStroke = Color.white.opacity(0.08)
}

// MARK: - A tile

struct FlameyClosetTile: View {
    enum Kind: Equatable {
        case auto(FlameyItem?)
        case none
        case item(FlameyItem)
    }

    let kind: Kind
    let slot: FlameySlot
    let model: FlameyClosetModel
    var action: () -> Void

    private var item: FlameyItem? {
        switch kind {
        case .auto(let item): return item
        case .none: return nil
        case .item(let item): return item
        }
    }

    private var owned: Bool {
        if case .item(let item) = kind { return model.owns(item) }
        return true
    }

    private var chosen: Bool {
        switch kind {
        case .auto: return model.isChosen(.auto, in: slot)
        case .none: return model.isChosen(.bare, in: slot)
        case .item(let item): return model.isChosen(.item(item), in: slot)
        }
    }

    private var tried: Bool {
        if case .item(let item) = kind { return model.tryingOn == item }
        return false
    }

    private var isNew: Bool {
        if case .item(let item) = kind { return model.newItems.contains(item) }
        return false
    }

    private var progress: FlameyUnlockProgress? {
        if case .item(let item) = kind { return model.progress(for: item) }
        return nil
    }

    private var title: String {
        switch kind {
        case .auto: return "Auto"
        case .none: return "None"
        case .item(let item): return item.displayName
        }
    }

    private var subtitle: String {
        switch kind {
        case .auto(let item): return item.map { "Best I own · \($0.displayName)" } ?? "Best I own"
        case .none: return "Nothing here"
        case .item(let item):
            if !owned { return item.unlockCopy }
            if chosen { return "Wearing" }
            if let tag = FlameyClosetCopy.holidayTag(item) { return tag }
            return item.unlock == .always ? "Always yours" : "Owned"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                FlameyClosetTileArt(kind: kind, slot: slot, color: model.savedLook.color, locked: !owned)
                    .frame(height: 78)
                    .frame(maxWidth: .infinity)
                    // Faded, not clipped: a hard clip cut his glow into a
                    // visible box behind every figure.
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                                 .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(.top, 8)

                Text(title)
                    .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.4)
                    .foregroundColor(owned ? .white : .white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)

                Text(subtitle)
                    .madFont(size: 10.5, weight: .semibold, design: .rounded, maxScale: 1.4)
                    .foregroundColor(subtitleColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.top, 2)

                if let progress {
                    progressBar(progress)
                        .padding(.horizontal, 10)
                        .padding(.top, 5)
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 156)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
            .overlay(border)
            .overlay(alignment: .topTrailing) { badge.padding(7) }
            .overlay(alignment: .topLeading) {
                if isNew {
                    Text("NEW")
                        .madFont(size: 8.5, weight: .black, design: .rounded, maxScale: 1.3)
                        .tracking(0.6)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(FlameyClosetStyle.newDot))
                        .padding(7)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(FlameyTilePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(owned ? (chosen ? "" : "Double-tap to wear") : "Double-tap to try it on")
        .accessibilityAddTraits(chosen ? [.isSelected, .isButton] : .isButton)
    }

    private var subtitleColor: Color {
        if !owned { return FlameyClosetStyle.ember.opacity(0.85) }
        return chosen ? .white.opacity(0.85) : .white.opacity(0.45)
    }

    private var fill: Color {
        chosen ? Color.white.opacity(0.10) : FlameyClosetStyle.tileFill
    }

    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if tried {
            shape.strokeBorder(FlameyClosetStyle.ember, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        } else if chosen {
            shape.strokeBorder(Color.white, lineWidth: 2)
        } else {
            shape.strokeBorder(FlameyClosetStyle.tileStroke, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if chosen {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.black)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white))
                .accessibilityHidden(true)
        } else if !owned {
            Image(systemName: "lock.fill")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .accessibilityHidden(true)
        }
    }

    private func progressBar(_ progress: FlameyUnlockProgress) -> some View {
        VStack(spacing: 3) {
            Text(progress.short)
                .madFont(size: 10, weight: .bold, design: .rounded, maxScale: 1.4, monospacedDigit: true)
                .foregroundColor(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [FlameyClosetStyle.ember, FlameyClosetStyle.chipSelected],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * progress.fraction))
                }
            }
            .frame(height: 4)
        }
    }

    private var accessibilityLabel: String {
        switch kind {
        case .auto(let item):
            var s = "Auto, best I own"
            if let item { s += ", currently \(item.displayName)" }
            return s + (chosen ? ", selected" : "")
        case .none:
            return "None" + (chosen ? ", selected" : "")
        case .item(let item):
            var parts = [item.displayName]
            if !owned {
                parts.append("locked")
                parts.append(lowercasedFirst(item.unlockCopy))
                if let progress { parts.append(progress.spoken) }
            } else if chosen {
                parts.append("wearing")
            } else {
                parts.append("owned")
            }
            if isNew { parts.append("new") }
            if let holiday = FlameyClosetCopy.holidayLine(item) { parts.append(holiday) }
            return parts.joined(separator: ", ")
        }
    }

    private func lowercasedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }
}

/// A gentle press: tiles dip a touch, never flash.
struct FlameyTilePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Tile art

/// The picture on a tile: Flamey (in the colour he wears) with ONLY this
/// item on, framed on the part of him the item is about — the hat's top
/// half, the shoes' bottom, the trail off to one side. A still, so a grid of
/// forty never runs forty clocks. Locked items draw as a greyed silhouette.
struct FlameyClosetTileArt: View {
    let kind: FlameyClosetTile.Kind
    let slot: FlameySlot
    let color: FlameyItem
    var locked: Bool = false
    /// 1 = the Closet tile's 78pt art box; smaller boxes pass their ratio.
    var scale: CGFloat = 1

    /// A day with no holiday, so a tile is the item and nothing else.
    static let neutralDate: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 10; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }()

    private var item: FlameyItem? {
        switch kind {
        case .auto(let item): return item
        case .none: return nil
        case .item(let item): return item
        }
    }

    var body: some View {
        Group {
            if slot == .bubble {
                bubble
            } else {
                figure
            }
        }
        .saturation(locked ? 0 : 1)
        .brightness(locked ? -0.18 : 0)
        .opacity(locked ? 0.5 : 1)
        .accessibilityHidden(true)
    }

    private var look: FlameyLook {
        var choice = FlameyLookChoice.auto
        for s in FlameySlot.allCases where s != .color && s != .bubble { choice[s] = .bare }
        var owned: Set<FlameyItem> = [color]
        if slot == .color {
            let c = item ?? .classic
            choice[.color] = .item(c)
            owned = [c]
        } else {
            choice[.color] = .item(color)
            if let item {
                owned.insert(item)
                choice[slot] = .item(item)
            }
        }
        return FlameyLook.resolve(owned: owned, choice: choice, date: Self.neutralDate, detail: .full)
    }

    /// (figure size, x, y) in points — where he stands so the item is centred.
    private var framing: (CGFloat, CGFloat, CGFloat) {
        switch slot {
        case .color: return (62, 0, 0)
        case .head: return (96, 0, 30)
        case .eyes: return (118, 0, 18)
        case .chest: return (120, 0, -30)
        case .feet: return (110, 0, -32)
        case .costume: return (64, 0, 2)
        case .back: return (58, 0, 4)
        case .held: return (74, 16, -2)
        case .trail: return (52, 22, 4)
        case .companion: return (54, -16, 4)
        case .aura: return (56, 0, 2)
        case .bubble: return (60, 0, 0)
        }
    }

    private var figure: some View {
        let (size, x, y) = framing
        return FlameyDressedFigure(look: look, health: .healthy, size: size * scale, scale: 1)
            .frame(width: size * scale, height: size * scale)
            .offset(x: x * scale, y: y * scale)
    }

    @ViewBuilder
    private var bubble: some View {
        let style = item ?? .classicBubble
        if style == .classicBubble {
            Text("Let's go!")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .padding(.bottom, 6)
                .background(FlameyBubbleShape(cornerRadius: 10, tailHeight: 6, tailWidth: 10).fill(Color.white))
                .scaleEffect(scale)
        } else {
            FlameyStyledBubble(text: "Let's go!", style: style, size: 140)
                .scaleEffect(0.85 * scale)
        }
    }
}

// MARK: - Entry-point faces (pure; the live wrappers open the Closet)

/// The hero's Closet capsule: hanger + "Closet", the savers chip's outlined
/// weight so it reads as a sibling control, never louder than Share.
struct FlameyClosetPill: View {
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
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Flamey's Closet")
        .accessibilityHint("Dress Flamey in what you've earned")
    }
}

/// The profile's "Customize Flamey" row: his current look, the tally, and
/// how many things are new.
struct FlameyClosetProfileCard: View {
    let look: FlameyLook
    let unlocked: Int
    let total: Int
    let fresh: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                FlameyDressedFigure(look: look, health: .healthy, size: 44, scale: 1)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Customize Flamey")
                        .madFont(size: 15, weight: .heavy, design: .rounded)
                        .foregroundColor(.white)
                    Text(fresh > 0 ? "\(fresh) new · \(unlocked) of \(total) unlocked" : "\(unlocked) of \(total) unlocked")
                        .madFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundColor(fresh > 0 ? FlameyClosetStyle.ember : .white.opacity(0.55))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
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
