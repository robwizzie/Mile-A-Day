import SwiftUI

/// The composer's sticker picker.
///
/// Four tabs — Stats, Flamey, Route, Numbers — each a rail of tiles that
/// render the REAL sticker scaled down, so you see exactly what lands on the
/// photo before you pick it (the way Instagram's filter thumbnails work).
/// Every tile is a plain on/off state: a ring means it's on the photo,
/// tapping it again takes it off. Stats, Flamey and Route each hold one
/// sticker (a sibling tile swaps it in place); Numbers can stack.
///
/// Everything here edits the view being shown on the canvas. On a FRONT &
/// BACK the scope row decides whether that's both views or just this one.
struct StickerTrayView: View {
    @ObservedObject var vm: PostComposerViewModel
    @State private var tab: StickerTrayTab = .stats

    private var context: StickerRenderContext { vm.stickerContext }

    /// Route only when there is a route the user shares — Stealth Mode, the
    /// "Share route maps" setting off and indoor walks never offer it.
    private var tabs: [StickerTrayTab] {
        StickerTrayTab.allCases.filter { $0 != .route || vm.hasRoute }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack {
                trayLabel("STICKERS")
                Spacer()
                if tab == .stats, vm.isStatsStickerTransformed { resetButton }
            }

            if vm.isDualPhoto { viewScopeRow }

            tabBar

            Group {
                switch tab {
                case .stats: statsTab
                case .flamey: flameyTab
                case .route: routeTab
                case .numbers: numbersTab
                }
            }
            .transition(.opacity)

            if !vm.activeStickers.isEmpty { colorRow }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.04))
        )
        .animation(.easeInOut(duration: 0.2), value: tab)
        .animation(.easeInOut(duration: 0.2), value: vm.activeStickers.map(\.kind))
        .animation(.easeInOut(duration: 0.2), value: vm.separateViewStickers)
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(tabs) { item in
                let onPhoto = count(in: item)
                let selected = tab == item
                Button {
                    guard !selected else { return }
                    MADHaptics.tap()
                    tab = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .bold))
                            .accessibilityHidden(true)
                        Text(item.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(selected ? .white : .white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(selected ? 0.12 : 0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? MADTheme.Colors.madRed : Color.white.opacity(0.08),
                                          lineWidth: selected ? 1.5 : 1)
                    )
                    // How many of this tab's stickers are on the photo — so
                    // what's on is visible without opening every tab.
                    .overlay(alignment: .topTrailing) {
                        if onPhoto > 0 {
                            Text("\(onPhoto)")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Circle().fill(MADTheme.Colors.madRed))
                                .offset(x: 4, y: -4)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(onPhoto > 0 ? "\(item.title), \(onPhoto) on photo" : item.title)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    private func count(in tab: StickerTrayTab) -> Int {
        vm.activeStickers.filter { StickerTrayTab(for: $0.kind) == tab }.count
    }

    // MARK: Stats

    private var statsIsOn: Bool { vm.sticker(in: .stats) != nil }

    /// A style tile previews ITS style but keeps the user's live accent and
    /// stat selection, so changing a colour or toggling a stat updates every
    /// tile.
    private func statsContext(style: StickerStyle) -> StickerRenderContext {
        var cfg = vm.config
        cfg.style = style
        return StickerRenderContext(input: vm.stats, config: cfg, route: vm.routeSticker)
    }

    @ViewBuilder
    private var statsTab: some View {
        tileRail {
            offTile(selected: !statsIsOn, label: "No stats sticker") {
                vm.removeSticker(in: .stats)
            }
            ForEach(StickerStyle.allCases) { style in
                StickerPreviewTile(
                    kind: .stats,
                    context: statsContext(style: style),
                    title: style.title,
                    selected: statsIsOn && vm.config.style == style,
                    accessibilityName: "\(style.title) stats sticker"
                ) {
                    vm.config.style = style
                    if !statsIsOn { vm.toggleSticker(.stats) }
                }
            }
        }

        if statsIsOn {
            trayLabel("SHOW")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(vm.stats.availableStats()) { kind in
                        trayChip(title: kind.label, icon: kind.icon,
                                 selected: vm.config.isOn(kind)) {
                            MADHaptics.tap()
                            vm.config.toggle(kind)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if vm.config.isOn(.competition), vm.liveCompetitions.count > 1 {
                trayLabel("RACE")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(vm.liveCompetitions, id: \.competitionId) { competition in
                            trayChip(
                                title: competition.name,
                                icon: "trophy.fill",
                                selected: vm.stats.competition?.competitionId == competition.competitionId
                            ) {
                                MADHaptics.tap()
                                vm.selectCompetition(competition)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: Flamey

    @ViewBuilder
    private var flameyTab: some View {
        let current = vm.sticker(in: .flamey)?.kind
        tileRail {
            offTile(selected: current == nil, label: "No Flamey sticker") {
                vm.removeSticker(in: .flamey)
            }
            ForEach(FlameySticker.allCases) { sticker in
                let kind = PostStickerKind.flamey(sticker)
                StickerPreviewTile(
                    kind: kind, context: context, title: sticker.title,
                    selected: current == kind,
                    accessibilityName: kind.accessibilityName
                ) { vm.toggleSticker(kind) }
            }
        }
        caption("Your Flamey, dressed the way you left him in the Closet.")
    }

    // MARK: Route

    @ViewBuilder
    private var routeTab: some View {
        if vm.routeSticker != nil {
            let current = vm.sticker(in: .route)?.kind
            tileRail {
                offTile(selected: current == nil, label: "No route sticker") {
                    vm.removeSticker(in: .route)
                }
                ForEach(RouteStickerStyle.allCases) { style in
                    let kind = PostStickerKind.route(style)
                    StickerPreviewTile(
                        kind: kind, context: context, title: style.title,
                        selected: current == kind,
                        accessibilityName: kind.accessibilityName
                    ) { vm.toggleSticker(kind) }
                }
            }
            caption(RoutePrivacyTrim.currentSettingMeters > 0
                ? "Just the shape of your walk — no map, and your start & end stay hidden."
                : "Just the shape of your walk — no map underneath.")
        } else if vm.routeStickerHiddenByPrivacy {
            caption("Your start & end are hidden from friends, and this walk is too short to show what's left.")
        } else {
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                caption("Loading your route…")
            }
            .frame(height: StickerPreviewTile.tileSize.height, alignment: .center)
        }
    }

    // MARK: Numbers

    @ViewBuilder
    private var numbersTab: some View {
        tileRail {
            ForEach(NumberPostSticker.available(for: vm.stats), id: \.self) { stat in
                let kind = PostStickerKind.number(stat)
                StickerPreviewTile(
                    kind: kind, context: context, title: stat.label,
                    selected: vm.sticker(in: kind.slot) != nil,
                    accessibilityName: kind.accessibilityName
                ) { vm.toggleSticker(kind) }
            }
        }
        caption("Big, bold numbers — add as many as you like.")
    }

    // MARK: - FRONT & BACK scope

    /// Whether the stickers are on both views or this one only. Lives here,
    /// beside the stickers it's about, and says in words which view you're
    /// editing — the canvas hint says it again on the photo.
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

    // MARK: - Shared rows

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            trayLabel("COLOR")
            HStack(spacing: MADTheme.Spacing.md) {
                ForEach(StickerAccent.allCases) { accent in
                    Button {
                        MADHaptics.tap()
                        vm.config.accent = accent
                    } label: {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle().strokeBorder(
                                    Color.white,
                                    lineWidth: vm.config.accent == accent ? 2.5 : 0
                                )
                            )
                            .overlay(
                                Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(accent.rawValue) stickers")
                    .accessibilityAddTraits(vm.config.accent == accent ? [.isSelected] : [])
                }
                Spacer()
            }
        }
    }

    private func tileRail<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MADTheme.Spacing.sm) {
                content()
            }
            // Room for the selected tile's ring + glow, which a ScrollView
            // would otherwise clip at its bounds.
            .padding(6)
        }
        // Pull the rail back out by the same amount so the first tile still
        // lines up with the labels above it.
        .padding(-6)
    }

    private func offTile(selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button {
            guard !selected else { return }
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    StickerTileChrome(selected: selected)
                    Image(systemName: "eye.slash")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white.opacity(selected ? 0.9 : 0.4))
                }
                .frame(width: StickerPreviewTile.tileSize.width,
                       height: StickerPreviewTile.tileSize.height)
                Text("Off")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(selected ? 0.95 : 0.5))
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var resetButton: some View {
        Button {
            MADHaptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                vm.resetStatsStickerPlacement()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .bold))
                Text("Reset")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityLabel("Reset stats sticker position")
    }

    private func trayLabel(_ text: String) -> some View {
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

    private func trayChip(title: String, icon: String, selected: Bool,
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

// MARK: - Tab

enum StickerTrayTab: String, CaseIterable, Identifiable {
    case stats, flamey, route, numbers
    var id: String { rawValue }

    init(for kind: PostStickerKind) {
        switch kind {
        case .stats: self = .stats
        case .flamey: self = .flamey
        case .route: self = .route
        case .number: self = .numbers
        }
    }

    var title: String {
        switch self {
        case .stats: return "Stats"
        case .flamey: return "Flamey"
        case .route: return "Route"
        case .numbers: return "Numbers"
        }
    }

    var icon: String {
        switch self {
        case .stats: return "chart.bar.fill"
        case .flamey: return "flame.fill"
        case .route: return "point.topleft.down.curvedto.point.bottomright.up"
        case .numbers: return "number"
        }
    }
}

// MARK: - Tile

/// Shared tile backdrop so the Off tile and the preview tiles are visually identical.
private struct StickerTileChrome: View {
    let selected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        selected ? MADTheme.Colors.madRed : Color.white.opacity(0.1),
                        lineWidth: selected ? 2 : 1
                    )
            )
            .shadow(color: selected ? MADTheme.Colors.madRed.opacity(0.35) : .clear,
                    radius: selected ? 8 : 0)
    }
}

/// One sticker preview.
///
/// Stickers are `.fixedSize()`, so they can't simply be handed a small
/// frame. Instead the natural size is measured and the sticker is scaled down
/// to fit: `scaleEffect` is layout-neutral, so the surrounding `.frame` still
/// reports tile size upward and `.clipped()` trims anything left over — no
/// layout blowup.
///
/// Rendering the live view (rather than pre-baking each sticker to a
/// `UIImage`) means the tiles are genuinely WYSIWYG and update the instant the
/// accent or a stat toggle changes, with no cache to invalidate.
private struct StickerPreviewTile: View {
    let kind: PostStickerKind
    let context: StickerRenderContext
    let title: String
    let selected: Bool
    let accessibilityName: String
    let action: () -> Void

    static let tileSize = CGSize(width: 84, height: 105)   // 4:5, echoing the canvas
    /// Breathing room so the sticker's own drop shadow doesn't hit the tile edge.
    private static let inset: CGFloat = 14

    @State private var natural: CGSize = .zero

    private var fit: CGFloat {
        guard natural.width > 0, natural.height > 0 else { return 0.001 }
        return min((Self.tileSize.width - Self.inset) / natural.width,
                   (Self.tileSize.height - Self.inset) / natural.height)
    }

    var body: some View {
        Button {
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    StickerTileChrome(selected: selected)
                    PostStickerView(kind: kind, context: context)
                        .equatable()                  // must sit directly on the sticker
                        .background(                  // outside .equatable(), under the
                            GeometryReader { geo in   // scale → reports NATURAL size once
                                Color.clear.preference(
                                    key: StickerNaturalSizeKey.self, value: geo.size)
                            }
                        )
                        .scaleEffect(fit, anchor: .center)
                        // Hide the single frame before the measurement lands, or the
                        // sticker flashes at full size inside a 84pt tile.
                        .opacity(natural == .zero ? 0 : 1)
                }
                .frame(width: Self.tileSize.width, height: Self.tileSize.height)
                .clipped()
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white, MADTheme.Colors.madRed)
                            .padding(5)
                            .accessibilityHidden(true)
                    }
                }

                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(selected ? 0.95 : 0.5))
                    .lineLimit(1)
                    .frame(width: Self.tileSize.width)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .onPreferenceChange(StickerNaturalSizeKey.self) { natural = $0 }
        .accessibilityLabel(accessibilityName)
        .accessibilityHint(selected ? "On the photo. Double-tap to remove." : "Double-tap to add to the photo.")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
