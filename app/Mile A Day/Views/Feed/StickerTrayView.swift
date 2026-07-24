import SwiftUI

/// The composer's sticker picker.
///
/// Replaces the old "Show run stats" toggle + abstract-icon STYLE chip row. Each
/// tile renders the REAL `RunStatsStickerView` for its style, using the user's
/// current accent and enabled stats, scaled down to fit — so you can see what a
/// style looks like before you pick it, the way Instagram's filter thumbnails work.
/// The leading "Off" tile takes the place of the toggle.
struct StickerTrayView: View {
    let input: RunStatsInput
    @Binding var config: StickerConfig
    @Binding var isEnabled: Bool
    /// True when the sticker has been dragged / pinched / twisted off its default
    /// placement — gates the Reset control so it isn't permanent chrome.
    let isTransformed: Bool
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack {
                trayLabel("STICKER")
                Spacer()
                if isEnabled, isTransformed { resetButton }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    offTile
                    ForEach(StickerStyle.allCases) { style in
                        StickerStyleTile(
                            input: input,
                            config: tileConfig(for: style),
                            selected: isEnabled && config.style == style
                        ) {
                            MADHaptics.tap()
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isEnabled = true
                                config.style = style
                            }
                        }
                    }
                }
                // Room for the selected tile's ring + glow, which a ScrollView
                // would otherwise clip at its bounds.
                .padding(6)
            }
            // Pull the rail back out by the same amount so the first tile still
            // lines up with the labels above it.
            .padding(-6)

            if isEnabled {
                trayLabel("SHOW")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(input.availableStats()) { kind in
                            trayChip(title: kind.label, icon: kind.icon,
                                     selected: config.isOn(kind)) {
                                MADHaptics.tap()
                                config.toggle(kind)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                trayLabel("COLOR")
                HStack(spacing: MADTheme.Spacing.md) {
                    ForEach(StickerAccent.allCases) { accent in
                        Button {
                            MADHaptics.tap()
                            config.accent = accent
                        } label: {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle().strokeBorder(
                                        Color.white,
                                        lineWidth: config.accent == accent ? 2.5 : 0
                                    )
                                )
                                .overlay(
                                    Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accent.rawValue)
                    }
                    Spacer()
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.04))
        )
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }

    /// The tile previews ITS style but keeps the user's live accent and stat
    /// selection, so changing a colour or toggling a stat updates every tile.
    private func tileConfig(for style: StickerStyle) -> StickerConfig {
        var cfg = config
        cfg.style = style
        return cfg
    }

    private var offTile: some View {
        Button {
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.15)) { isEnabled = false }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    StickerTileChrome(selected: !isEnabled)
                    Image(systemName: "eye.slash")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white.opacity(!isEnabled ? 0.9 : 0.4))
                }
                .frame(width: StickerStyleTile.tileSize.width,
                       height: StickerStyleTile.tileSize.height)
                Text("Off")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(!isEnabled ? 0.95 : 0.5))
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("No sticker")
    }

    private var resetButton: some View {
        Button {
            MADHaptics.tap()
            onReset()
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
        .accessibilityLabel("Reset sticker position")
    }

    private func trayLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.4))
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

// MARK: - Tile

/// Shared tile backdrop so the Off tile and the style tiles are visually identical.
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

/// One style preview.
///
/// `RunStatsStickerView` is `.fixedSize()`, so it can't simply be handed a small
/// frame. Instead the natural size is measured and the sticker is scaled down to
/// fit: `scaleEffect` is layout-neutral, so the surrounding `.frame` still reports
/// tile size upward and `.clipped()` trims anything left over — no layout blowup.
///
/// Rendering the live view (rather than pre-baking each style to a `UIImage`) means
/// the tiles are genuinely WYSIWYG and update the instant the accent or a stat
/// toggle changes, with no cache to invalidate.
private struct StickerStyleTile: View {
    let input: RunStatsInput
    let config: StickerConfig
    let selected: Bool
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
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    StickerTileChrome(selected: selected)
                    RunStatsStickerView(input: input, config: config)
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

                Text(config.style.title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(selected ? 0.95 : 0.5))
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .onPreferenceChange(StickerNaturalSizeKey.self) { natural = $0 }
        .accessibilityLabel("\(config.style.title) sticker")
    }
}
