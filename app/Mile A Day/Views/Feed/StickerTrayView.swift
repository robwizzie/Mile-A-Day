import SwiftUI

// MARK: - Action bar

/// What sits under the composer's photo, Instagram-style: one "Add
/// stickers" button that opens the picker sheet, and — while a sticker is
/// focused on the photo — that sticker's own options instead: its colour,
/// the stats card's stats, remove and done. Moving, resizing and turning all
/// happen on the photo itself (`StickerGestureSurface`), never here.
///
/// Everything edits the view being shown on the canvas. On a FRONT & BACK
/// the scope row decides whether that's both views or just this one.
struct StickerActionBar: View {
    @ObservedObject var vm: PostComposerViewModel
    @State private var showPicker = false
    /// The picker's "Aa" asked for the text editor; it opens once the sheet
    /// is down (one presentation at a time).
    @State private var textAfterPicker = false
    @State private var textEdit: TextEditRequest?
    /// The NEW tag on the button, until the picker has been opened once.
    @AppStorage("post.stickers.pickerSeen.v1") private var pickerSeen = false

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            if vm.isDualPhoto { viewScopeRow }

            if let focused = vm.selectedSticker {
                focusedPanel(focused)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                addRow
                    .transition(.opacity)
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.04))
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.selectedStickerId)
        .animation(.easeInOut(duration: 0.2), value: vm.separateViewStickers)
        // Its own node: nothing else in the composer presents from here.
        .sheet(isPresented: $showPicker, onDismiss: {
            guard textAfterPicker else { return }
            textAfterPicker = false
            textEdit = TextEditRequest(stickerId: nil, text: "", style: .classic, accent: .mono)
        }) {
            StickerPickerSheet(vm: vm) { textAfterPicker = true }
        }
        // The text editor on a node of its own: two presentations on one
        // node silently drop one.
        .background {
            Color.clear
                .fullScreenCover(item: $textEdit) { request in
                    TextStickerEditor(request: request) { done in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            if let id = done.stickerId {
                                vm.updateText(id: id, text: done.text, style: done.style, accent: done.accent)
                            } else {
                                vm.addText(done.text, style: done.style, accent: done.accent)
                            }
                        }
                    }
                }
        }
    }

    // MARK: Nothing focused

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                MADHaptics.tap()
                pickerSeen = true
                showPicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "face.smiling.inverse")
                        .font(.system(size: 18, weight: .bold))
                        .accessibilityHidden(true)
                    Text("Add stickers")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if !pickerSeen {
                        Text("NEW")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(0.6)
                            .foregroundColor(MADTheme.Colors.madRed)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white))
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .black))
                        .opacity(0.6)
                        .accessibilityHidden(true)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MADTheme.Colors.redGradient)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityHint("Your stats, route, Flamey and more.")

            caption(vm.activeStickers.isEmpty
                ? "Text, emoji, your stats, your route, your Flamey and the Flamey pack."
                : "Tap a sticker to edit it. Drag to move, pinch to resize, twist to turn.")
        }
    }

    // MARK: Focused

    private func focusedPanel(_ sticker: PlacedSticker) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(spacing: 10) {
                Text(sticker.kind.accessibilityName.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if sticker.kind == .stats, vm.isStatsStickerTransformed {
                    pillButton(title: "Reset", icon: "arrow.counterclockwise",
                               label: "Reset stats sticker position") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            vm.resetStatsStickerPlacement()
                        }
                    }
                }
                if case .text(let style) = sticker.kind {
                    pillButton(title: "Edit", icon: "character.cursor.ibeam", label: "Edit text") {
                        textEdit = TextEditRequest(stickerId: sticker.id, text: sticker.text ?? "",
                                                   style: style, accent: vm.accent(of: sticker))
                    }
                }
                pillButton(title: nil, icon: "trash", label: "Remove sticker") {
                    withAnimation(.easeOut(duration: 0.15)) { vm.removeStickerWithUndo(id: sticker.id) }
                }
                pillButton(title: "Done", icon: nil, label: "Done editing sticker", filled: true) {
                    withAnimation(.easeOut(duration: 0.15)) { vm.selectedStickerId = nil }
                }
            }

            colorRow(sticker)

            if sticker.kind == .stats { statsOptions }

            caption("Tap it again on the photo to change its style.")
        }
    }

    private func colorRow(_ sticker: PlacedSticker) -> some View {
        let current = vm.accent(of: sticker)
        return HStack(spacing: MADTheme.Spacing.sm) {
            ForEach(StickerAccent.allCases) { accent in
                Button {
                    MADHaptics.tap()
                    vm.setAccent(accent, for: sticker.id)
                } label: {
                    Circle()
                        .fill(accent.color)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: current == accent ? 2.5 : 0))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        .scaleEffect(current == accent ? 1.1 : 1)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(accent.rawValue) sticker")
                .accessibilityAddTraits(current == accent ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: current)
    }

    @ViewBuilder
    private var statsOptions: some View {
        label("SHOW")
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MADTheme.Spacing.sm) {
                ForEach(vm.stats.availableStats()) { kind in
                    chip(title: kind.label, icon: kind.icon, selected: vm.config.isOn(kind)) {
                        MADHaptics.tap()
                        vm.config.toggle(kind)
                    }
                }
            }
            .padding(.vertical, 2)
        }

        if vm.config.isOn(.competition), vm.liveCompetitions.count > 1 {
            label("RACE")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(vm.liveCompetitions, id: \.competitionId) { competition in
                        chip(title: competition.name, icon: "trophy.fill",
                             selected: vm.stats.competition?.competitionId == competition.competitionId) {
                            MADHaptics.tap()
                            vm.selectCompetition(competition)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: FRONT & BACK scope

    /// Whether the stickers are on both views or this one only, and in words
    /// which view you're editing — the canvas footer says it again on the
    /// photo.
    private var viewScopeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                scopeChip(title: "Same on both", separate: false)
                scopeChip(title: "Each view", separate: true)
            }
            .padding(4)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))

            caption(vm.separateViewStickers
                ? "Editing the \(vm.dualLeadIsFront ? "front" : "back") view. Tap the corner photo to edit the \(vm.dualLeadIsFront ? "back" : "front") view's stickers."
                : "These stickers show whichever camera is big.")
        }
    }

    private func scopeChip(title: String, separate: Bool) -> some View {
        let selected = vm.separateViewStickers == separate
        return Button {
            guard !selected else { return }
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.2)) { vm.setSeparateViewStickers(separate) }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundColor(selected ? .black : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Color.white : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(separate ? "Different stickers for each view" : "Same stickers on both views")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Bits

    private func pillButton(title: String?, icon: String?, label: String, filled: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .bold))
                }
                if let title {
                    Text(title).font(.system(size: 13, weight: .black, design: .rounded))
                }
            }
            .foregroundColor(filled ? .black : .white.opacity(0.9))
            .padding(.horizontal, title == nil ? 0 : 12)
            .frame(minWidth: 34, minHeight: 34)
            .background(Capsule().fill(filled ? Color.white : Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.4))
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func chip(title: String, icon: String, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(selected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                Capsule().fill(selected
                    ? AnyShapeStyle(MADTheme.Colors.redGradient)
                    : AnyShapeStyle(Color.white.opacity(0.07)))
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(selected ? 0 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Picker sheet

/// Instagram's sticker tray: a dark sheet with search, a cloud of white
/// "tool" chips (text, numbers, words — each with its own coloured icon,
/// tilted a touch the way Instagram's are), then grids of picture stickers
/// drawn for real (`PostStickerView`, so what you tap is what lands). A tap
/// adds the sticker to the photo, focused, and closes the sheet; one-per-photo
/// kinds already on it are ticked and a tap restyles them (`addSticker`).
struct StickerPickerSheet: View {
    @ObservedObject var vm: PostComposerViewModel
    /// The "Aa" chip: the host opens the text editor once this sheet is down.
    let onText: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""

    struct Chip: Identifiable {
        let id: String
        let title: String
        let icon: String
        let tint: Color
        let keywords: String
        /// nil = the "Aa" text chip.
        let kind: PostStickerKind?
        var isNew = false
    }

    struct Item: Identifiable {
        let id: String
        let kind: PostStickerKind
        let title: String
        let keywords: String
        /// Stats card tiles: the style the tile previews (and picks).
        var statsStyle: StickerStyle? = nil
    }

    struct PickerSection: Identifiable {
        let id: String
        let title: String
        let items: [Item]
        var note: String? = nil
        var compact = false
    }

    // Instagram's chip palette.
    private static let tints: [Color] = [
        Color(red: 0.55, green: 0.27, blue: 0.95), Color(red: 0.98, green: 0.45, blue: 0.1),
        Color(red: 0.93, green: 0.16, blue: 0.48), Color(red: 0.1, green: 0.6, blue: 0.95),
        Color(red: 0.13, green: 0.72, blue: 0.35), Color(red: 0.8, green: 0.1, blue: 0.75),
    ]

    private var chips: [Chip] {
        var out: [Chip] = [
            Chip(id: "text", title: "Text", icon: "textformat", tint: Self.tints[0],
                 keywords: "text aa type words caption write", kind: nil, isNew: true),
        ]
        out += NumberPostSticker.available(for: vm.stats).map { stat in
            Chip(id: "number.\(stat.rawValue)", title: stat.label, icon: stat.icon, tint: .clear,
                 keywords: "number big stat \(stat.label)".lowercased(), kind: .number(stat))
        }
        out += vm.offeredBadges.map { badge in
            Chip(id: "badge.\(badge.rawValue)", title: chipTitle(for: badge),
                 icon: badge.icon, tint: .clear, keywords: badge.keywords, kind: .badge(badge),
                 isNew: badge == .buddies)
        }
        // Colour each by position so neighbours never match.
        return out.enumerated().map { i, chip in
            Chip(id: chip.id, title: chip.title, icon: chip.icon,
                 tint: chip.kind == nil ? chip.tint : Self.tints[(i + 1) % Self.tints.count],
                 keywords: chip.keywords, kind: chip.kind, isNew: chip.isNew)
        }
    }

    /// A word sticker's chip says what it will print where that's short
    /// ("Day 42", "With Alex & Sam"), else its name.
    private func chipTitle(for badge: FunBadge) -> String {
        switch badge {
        case .dayCount, .buddies:
            return vm.capturedText(for: .badge(badge))?.capitalizedWords ?? badge.title
        case .clock:
            return badge.title
        default:
            return badge.text(captured: nil).capitalizedWords
        }
    }

    private var sections: [PickerSection] {
        var cards: [Item] = StickerStyle.allCases.map { style in
            Item(id: "stats.\(style.rawValue)", kind: .stats, title: style.title,
                 keywords: "stats card \(style.title) distance pace time streak".lowercased(),
                 statsStyle: style)
        }
        if vm.routeSticker != nil {
            cards += RouteStickerStyle.allCases.map { style in
                Item(id: "route.\(style.rawValue)", kind: .route(style), title: "Route · \(style.title)",
                     keywords: "route map path line strava gps \(style.title)".lowercased())
            }
        }
        let own = FlameySticker.allCases.map { sticker in
            Item(id: "flamey.\(sticker.rawValue)", kind: .flamey(sticker), title: sticker.title,
                 keywords: "your flamey custom closet mine \(sticker.keywords)")
        }
        let pack = FlameyPackSticker.allCases.map { sticker in
            Item(id: "pack.\(sticker.rawValue)", kind: .pack(sticker), title: sticker.title,
                 keywords: sticker.keywords)
        }
        let classic = FlameySticker.allCases.map { sticker in
            Item(id: "basic.\(sticker.rawValue)", kind: .basicFlamey(sticker), title: sticker.title,
                 keywords: "flamey basic classic original \(sticker.keywords)")
        }
        let emoji = StickerEmoji.all.map { e in
            Item(id: "emoji.\(e)", kind: .emoji(e), title: e, keywords: "emoji \(e)")
        }
        let routeNote: String? = vm.routeStickerAvailable && vm.routeSticker == nil
            ? "Loading your route…" : nil
        return [
            PickerSection(id: "pack", title: "FLAMEY PACK", items: pack),
            PickerSection(id: "cards", title: "YOUR WALK", items: cards, note: routeNote),
            PickerSection(id: "own", title: "YOUR FLAMEY", items: own),
            PickerSection(id: "classic", title: "CLASSIC FLAMEY", items: classic),
            PickerSection(id: "emoji", title: "EMOJI", items: emoji, compact: true),
        ]
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private func matches(_ keywords: String, _ title: String) -> Bool {
        let q = trimmedQuery
        return q.isEmpty || keywords.contains(q) || title.lowercased().contains(q)
    }

    var body: some View {
        let shownChips = chips.filter { matches($0.keywords, $0.title) }
        let shownSections = sections.compactMap { section -> PickerSection? in
            let items = section.items.filter { matches($0.keywords, $0.title) }
            guard !items.isEmpty else { return nil }
            return PickerSection(id: section.id, title: section.title, items: items,
                                 note: trimmedQuery.isEmpty ? section.note : nil, compact: section.compact)
        }
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.top, 22)
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                    if shownChips.isEmpty && shownSections.isEmpty {
                        Text("No stickers match “\(query)”")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    if !shownChips.isEmpty {
                        ChipCloud(spacing: 10, rowSpacing: 12) {
                            ForEach(Array(shownChips.enumerated()), id: \.element.id) { i, chip in
                                chipButton(chip, tilt: Self.tilts[i % Self.tilts.count])
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    ForEach(shownSections) { section in
                        sectionView(section)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.xl)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .madTypeCap(.madCardCap)
    }

    /// Instagram's chips sit a little askew, never in a ruler-straight grid.
    private static let tilts: [Double] = [-2, 1.5, -1, 2, 0.5, -1.5, 1]

    private func chipButton(_ chip: Chip, tilt: Double) -> some View {
        let onPhoto = chip.kind.map { kind in
            kind.isSingleton && vm.activeStickers.contains { $0.kind == kind }
        } ?? false
        return Button {
            MADHaptics.tap()
            if let kind = chip.kind {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15)
                                           : .spring(response: 0.38, dampingFraction: 0.6)) {
                    vm.addSticker(kind)
                }
            } else {
                onText()
            }
            dismiss()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: onPhoto ? "checkmark.circle.fill" : chip.icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(chip.tint)
                    .accessibilityHidden(true)
                Text(chip.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.08, green: 0.08, blue: 0.1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 15)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
            .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 2)
            .overlay(alignment: .bottomTrailing) {
                if chip.isNew {
                    Text("New")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(chip.tint))
                        .offset(x: 6, y: 9)
                        .accessibilityHidden(true)
                }
            }
            .rotationEffect(.degrees(reduceMotion ? 0 : tilt))
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(chip.kind?.accessibilityName ?? "Add your own text")
        .accessibilityAddTraits(onPhoto ? [.isSelected] : [])
    }

    private func sectionView(_ section: PickerSection) -> some View {
        let size = section.compact ? StickerPickerTile.compactSize : StickerPickerTile.size
        return VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.5))
            if let note = section.note {
                Text(note)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: size.width), spacing: 8)], spacing: 8) {
                ForEach(section.items) { item in
                    tile(item, size: size, showsTitle: !section.compact && section.id != "pack")
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .accessibilityHidden(true)
            TextField("Search", text: $query)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.14)))
    }

    private func tile(_ item: Item, size: CGSize, showsTitle: Bool) -> some View {
        let onPhoto = item.kind.isSingleton
            && vm.activeStickers.contains { $0.kind == item.kind }
            && (item.statsStyle == nil || item.statsStyle == vm.config.style)
        let context: StickerRenderContext = item.statsStyle.map { statsContext(style: $0) } ?? vm.stickerContext
        return StickerPickerTile(
            kind: item.kind,
            context: context,
            text: vm.capturedText(for: item.kind),
            title: showsTitle ? item.title : nil,
            size: size,
            onPhoto: onPhoto
        ) {
            if let style = item.statsStyle { vm.config.style = style }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15)
                                       : .spring(response: 0.38, dampingFraction: 0.6)) {
                vm.addSticker(item.kind)
            }
            dismiss()
        }
    }

    /// A style tile previews ITS style with the poster's own stats.
    private func statsContext(style: StickerStyle) -> StickerRenderContext {
        var cfg = vm.config
        cfg.style = style
        return StickerRenderContext(input: vm.stats, config: cfg, route: vm.routeSticker)
    }
}

private extension String {
    /// "NO DAYS OFF" → "No Days Off", for a chip label.
    var capitalizedWords: String { lowercased().capitalized }
}

// MARK: - Chip cloud

/// Rows of chips, each row centred, wrapping at the sheet's width — the
/// layout of Instagram's sticker tray.
struct ChipCloud: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let w = min(size.width, width)
            if x > 0, x + spacing + w > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((i, CGSize(width: w, height: size.height)))
            x += (x > 0 ? spacing : 0) + w
        }
        return rows.map { $0.map { (index: $0.0, size: $0.1) } }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = arrange(subviews, width: width)
        let height = rows.reduce(CGFloat(0)) { sum, row in
            sum + (row.map(\.size.height).max() ?? 0)
        } + rowSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            let rowWidth = row.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(row.count - 1, 0))
            let rowHeight = row.map(\.size.height).max() ?? 0
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            for item in row {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (rowHeight - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += rowHeight + rowSpacing
        }
    }
}

// MARK: - Tile

/// One picture sticker in the picker, drawn for real and scaled to fit, on
/// no tile at all — the sticker is the button, as in Instagram.
///
/// Stickers are `.fixedSize()`, so they can't simply be handed a small
/// frame: the natural size is measured and the sticker scaled down to fit.
/// `scaleEffect` is layout-neutral, so the frame still reports tile size and
/// `.clipped()` trims anything left over.
private struct StickerPickerTile: View {
    let kind: PostStickerKind
    let context: StickerRenderContext
    let text: String?
    let title: String?
    let size: CGSize
    /// A one-per-photo sticker already there: ticked, and a tap restyles it.
    let onPhoto: Bool
    let action: () -> Void

    static let size = CGSize(width: 100, height: 100)
    static let compactSize = CGSize(width: 54, height: 54)

    @State private var natural: CGSize = .zero

    private var fit: CGFloat {
        guard natural.width > 0, natural.height > 0 else { return 0.001 }
        let inset: CGFloat = size.width > 80 ? 12 : 4
        return min(1.4, (size.width - inset) / natural.width, (size.height - inset) / natural.height)
    }

    var body: some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            VStack(spacing: 4) {
                PostStickerView(kind: kind, context: context, text: text)
                    .equatable()
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: StickerNaturalSizeKey.self, value: geo.size)
                        }
                    )
                    .scaleEffect(fit, anchor: .center)
                    // Hide the one frame before the measurement lands, or
                    // the sticker flashes at full size inside the tile.
                    .opacity(natural == .zero ? 0 : 1)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        if onPhoto {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.white, MADTheme.Colors.madRed)
                                .padding(2)
                                .accessibilityHidden(true)
                        }
                    }
                if let title {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: size.width)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .onPreferenceChange(StickerNaturalSizeKey.self) { natural = $0 }
        .accessibilityLabel(kind.accessibilityName)
        .accessibilityHint(onPhoto ? "On the photo. Double-tap to restyle it." : "Double-tap to add to the photo.")
        .accessibilityAddTraits(onPhoto ? [.isSelected] : [])
    }
}

// MARK: - Text editor

/// What the text editor is editing: a new text sticker, or one on the photo.
struct TextEditRequest: Identifiable {
    let id = UUID()
    var stickerId: UUID?
    var text: String
    var style: TextStickerStyle
    var accent: StickerAccent
}

/// Instagram's "Aa": the photo dims, the keyboard comes up, the words are
/// drawn in their real style as you type, with the style and colours along
/// the top and bottom.
struct TextStickerEditor: View {
    let request: TextEditRequest
    let onDone: (TextEditRequest) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TextEditRequest
    @FocusState private var focused: Bool

    init(request: TextEditRequest, onDone: @escaping (TextEditRequest) -> Void) {
        self.request = request
        self.onDone = onDone
        _draft = State(initialValue: request)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    MADHaptics.tap()
                    draft.style = draft.style.cycled
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "textformat")
                            .font(.system(size: 14, weight: .bold))
                        Text(draft.style.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Text style, \(draft.style.title)")
                .accessibilityHint("Double-tap for the next style.")
                Spacer()
                Button {
                    MADHaptics.tap()
                    onDone(draft)
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16).frame(height: 36)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.md)

            Spacer(minLength: 12)

            // The words in their real style as you type, in a native field
            // (caret, selection, dictation all just work).
            styledField
                .frame(maxWidth: .infinity)
                .padding(.horizontal, MADTheme.Spacing.lg)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: draft.style)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                ForEach(StickerAccent.allCases) { accent in
                    Button {
                        MADHaptics.tap()
                        draft.accent = accent
                    } label: {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: draft.accent == accent ? 3 : 1.5))
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(accent.rawValue) text")
                    .accessibilityAddTraits(draft.accent == accent ? [.isSelected] : [])
                }
            }
            .padding(.bottom, MADTheme.Spacing.md)
        }
        .presentationBackground(Color.black.opacity(0.72))
        .preferredColorScheme(.dark)
        .madTypeCap(.madCardCap)
        .onAppear { focused = true }
    }

    private var ink: Color { draft.accent == .mono ? Color(red: 0.08, green: 0.06, blue: 0.08) : .white }

    /// The field dressed like `TextPostSticker`'s style of the same name.
    @ViewBuilder
    private var styledField: some View {
        let field = TextField("", text: $draft.text,
                              prompt: Text("Say something").foregroundColor(.white.opacity(0.4)),
                              axis: .vertical)
            .focused($focused)
            .lineLimit(1...4)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: draft.text) { _, text in
                if text.count > PostComposerViewModel.maxStickerText {
                    draft.text = String(text.prefix(PostComposerViewModel.maxStickerText))
                }
            }
            .accessibilityLabel("Sticker text")
        switch draft.style {
        case .classic:
            field
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(draft.accent.color)
                .tint(.white)
                .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 2)
        case .pill:
            field
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(ink)
                .tint(ink)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(draft.accent.color))
        case .neon:
            field
                .font(.system(size: 30, weight: .bold, design: .rounded).italic())
                .foregroundColor(.white)
                .tint(.white)
                .shadow(color: draft.accent.color, radius: 2)
                .shadow(color: draft.accent.color, radius: 8)
        case .typewriter:
            field
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.08))
                .tint(.black)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Rectangle().fill(Color.white))
        }
    }
}
