import SwiftUI

// The pieces every Settings screen is built from.
//
// Settings used to say "this is a section" three times: a tinted icon and a
// tracked ALL-CAPS label over each group, a 36pt filled icon disc on every
// row, and a glass card per group. Now it's the dashboard's grammar: a plain
// sentence-case header, rows with a small tinted glyph, and ONE flat surface
// (`DashboardCardSurface`'s fill). Colour lives in the glyphs, not the cards.

extension View {
    /// The one card a Settings group sits on: `DashboardCardSurface`, inset by
    /// its padding. No glass, gradient, rim or shadow.
    func settingsCard(padding: CGFloat = DashboardCardSurface.padding) -> some View {
        self
            .padding(padding)
            .background(DashboardCardSurface(style: .fun))
    }
}

/// A group of settings: an optional sentence-case header, the rows on one flat
/// card, and an optional one-line footer under it.
struct SettingsSection<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            if let title {
                Text(LocalizedStringKey(title))
                    .madFont(size: 15, weight: .semibold, design: .rounded)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, MADTheme.Spacing.xs)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsCard(padding: 14)

            if let footer {
                Text(LocalizedStringKey(footer))
                    .madFont(size: 12, design: .rounded)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MADTheme.Spacing.xs)
            }
        }
    }
}

/// One settings row: a small tinted SF Symbol (no disc), the title, an
/// optional subtitle, and what the row does at its trailing edge.
struct SettingsRow: View {
    enum Accessory {
        /// Pushes or presents a screen.
        case chevron
        /// Leaves the app (iOS Settings, Apple Health, a web page).
        case external
        /// Acts in place (sign out, run a repair).
        case none
    }

    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = .secondary
    var titleColor: Color = .primary
    var accessory: Accessory = .chevron

    var body: some View {
        HStack(spacing: 12) {
            SettingsGlyph(icon: icon, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                // `String` properties: wrapping in a key looks each up in the
                // String Catalog and falls back to the text itself.
                Text(LocalizedStringKey(title))
                    .madFont(size: 16, weight: .medium, design: .rounded)
                    .foregroundColor(titleColor)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .madFont(size: 12, design: .rounded)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: MADTheme.Spacing.sm)

            switch accessory {
            case .chevron:
                Image(systemName: "chevron.right")
                    .madFont(size: 12, weight: .semibold, maxScale: 1.5)
                    .foregroundColor(.secondary.opacity(0.7))
                    .accessibilityHidden(true)
            case .external:
                Image(systemName: "arrow.up.forward")
                    .madFont(size: 12, weight: .semibold, maxScale: 1.5)
                    .foregroundColor(.secondary.opacity(0.7))
                    .accessibilityHidden(true)
            case .none:
                EmptyView()
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// A row that ends in a switch. No chevron: a chevron beside a switch promises
/// a page that isn't there.
struct SettingsToggleRow: View {
    let icon: String?
    let title: String
    var subtitle: String? = nil
    var tint: Color = .secondary
    @Binding var isOn: Bool

    init(icon: String? = nil, title: String, subtitle: String? = nil, tint: Color = .secondary, isOn: Binding<Bool>) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                SettingsGlyph(icon: icon, tint: tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .madFont(size: 16, weight: .medium, design: .rounded)
                    .foregroundColor(.primary)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .madFont(size: 12, design: .rounded)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: MADTheme.Spacing.sm)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(MADTheme.Colors.madRed)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// The small glyph that leads a row: tinted, fixed width so titles align.
struct SettingsGlyph: View {
    let icon: String
    var tint: Color = .secondary

    var body: some View {
        Image(systemName: icon)
            .madFont(size: 16, weight: .medium, maxScale: 1.3)
            .foregroundColor(tint)
            .frame(width: 24)
            .accessibilityHidden(true)
    }
}

/// The hairline between rows on a settings card.
struct SettingsDivider: View {
    /// Rows with a glyph inset the line to the title (24pt glyph + 12pt gap).
    var inset: CGFloat = 36

    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.06))
            .padding(.leading, inset)
    }
}
