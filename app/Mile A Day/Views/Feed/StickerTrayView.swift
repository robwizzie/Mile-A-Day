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
        .sheet(isPresented: $showPicker) {
            StickerPickerSheet(vm: vm)
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
                ? "Your stats, your route, your Flamey, the Flamey pack and more."
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

/// Instagram's sticker tray: a sheet of every sticker, drawn for real
/// (`PostStickerView`, so what you tap is what lands), in sections, with
/// search. A tap adds the sticker to the photo, focused, and closes the
/// sheet; one-per-photo kinds already on it are ticked and a tap restyles
/// them instead (`addSticker`).
struct StickerPickerSheet: View {
    @ObservedObject var vm: PostComposerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""

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
    }

    private var sections: [PickerSection] {
        var run: [Item] = StickerStyle.allCases.map { style in
            Item(id: "stats.\(style.rawValue)", kind: .stats, title: style.title,
                 keywords: "stats card \(style.title) distance pace time streak".lowercased(),
                 statsStyle: style)
        }
        if vm.routeSticker != nil {
            run += RouteStickerStyle.allCases.map { style in
                Item(id: "route.\(style.rawValue)", kind: .route(style), title: "Route · \(style.title)",
                     keywords: "route map path line strava gps \(style.title)".lowercased())
            }
        }
        run += NumberPostSticker.available(for: vm.stats).map { stat in
            Item(id: "number.\(stat.rawValue)", kind: .number(stat), title: stat.label,
                 keywords: "number big \(stat.label)".lowercased())
        }
        let own = FlameySticker.allCases.map { sticker in
            Item(id: "flamey.\(sticker.rawValue)", kind: .flamey(sticker), title: sticker.title,
                 keywords: "your flamey custom closet mine \(sticker.keywords)")
        }
        let pack = FlameySticker.allCases.map { sticker in
            Item(id: "basic.\(sticker.rawValue)", kind: .basicFlamey(sticker), title: sticker.title,
                 keywords: "flamey pack basic classic original \(sticker.keywords)")
        }
        let words = vm.offeredBadges.map { badge in
            Item(id: "badge.\(badge.rawValue)", kind: .badge(badge), title: badge.title,
                 keywords: badge.keywords)
        }
        let routeNote: String? = vm.routeStickerAvailable && vm.routeSticker == nil
            ? "Loading your route…" : nil
        return [
            PickerSection(id: "run", title: "YOUR WALK", items: run, note: routeNote),
            PickerSection(id: "own", title: "YOUR FLAMEY", items: own,
                          note: "Dressed the way you left him in the Closet."),
            PickerSection(id: "pack", title: "FLAMEY PACK", items: pack),
            PickerSection(id: "words", title: "WORDS", items: words),
        ]
    }

    private var filtered: [PickerSection] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sections }
        return sections.compactMap { section in
            let items = section.items.filter { $0.keywords.contains(q) || $0.title.lowercased().contains(q) }
            return items.isEmpty ? nil : PickerSection(id: section.id, title: section.title, items: items)
        }
    }

    private let columns = [GridItem(.adaptive(minimum: StickerPickerTile.size.width), spacing: 10)]

    var body: some View {
        let shown = filtered
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.top, 22)
                .padding(.bottom, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                    if shown.isEmpty {
                        Text("No stickers match “\(query)”")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(shown) { section in
                        sectionView(section)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.xl)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Color(white: 0.07).ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(white: 0.07))
        .preferredColorScheme(.dark)
        .madTypeCap(.madCardCap)
    }

    private func sectionView(_ section: PickerSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.45))
            if let note = section.note {
                Text(note)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(section.items) { item in
                    tile(item)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .accessibilityHidden(true)
            TextField("Search stickers", text: $query)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func tile(_ item: Item) -> some View {
        let onPhoto = item.kind.isSingleton
            && vm.activeStickers.contains { $0.kind == item.kind }
            && (item.statsStyle == nil || item.statsStyle == vm.config.style)
        let context: StickerRenderContext = item.statsStyle.map { statsContext(style: $0) } ?? vm.stickerContext
        return StickerPickerTile(
            kind: item.kind,
            context: context,
            text: vm.capturedText(for: item.kind),
            title: item.title,
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

// MARK: - Tile

/// One sticker in the picker, drawn for real and scaled to fit.
///
/// Stickers are `.fixedSize()`, so they can't simply be handed a small
/// frame: the natural size is measured and the sticker scaled down to fit.
/// `scaleEffect` is layout-neutral, so the frame still reports tile size and
/// `.clipped()` trims anything left over.
private struct StickerPickerTile: View {
    let kind: PostStickerKind
    let context: StickerRenderContext
    let text: String?
    let title: String
    /// A one-per-photo sticker already there: ticked, and a tap restyles it.
    let onPhoto: Bool
    let action: () -> Void

    static let size = CGSize(width: 100, height: 100)
    private static let inset: CGFloat = 16

    @State private var natural: CGSize = .zero

    private var fit: CGFloat {
        guard natural.width > 0, natural.height > 0 else { return 0.001 }
        return min(1.4, (Self.size.width - Self.inset) / natural.width,
                   (Self.size.height - Self.inset) / natural.height)
    }

    var body: some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
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
                }
                .frame(width: Self.size.width, height: Self.size.height)
                .clipped()
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(onPhoto ? MADTheme.Colors.madRed : Color.white.opacity(0.08),
                                      lineWidth: onPhoto ? 2 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if onPhoto {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white, MADTheme.Colors.madRed)
                            .padding(5)
                            .accessibilityHidden(true)
                    }
                }
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: Self.size.width)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .onPreferenceChange(StickerNaturalSizeKey.self) { natural = $0 }
        .accessibilityLabel(kind.accessibilityName)
        .accessibilityHint(onPhoto ? "On the photo. Double-tap to restyle it." : "Double-tap to add to the photo.")
        .accessibilityAddTraits(onPhoto ? [.isSelected] : [])
    }
}
