import SwiftUI

/// Visual treatment for a `MADHeaderAction`. Different styles encode different
/// meanings — a notification badge implies "look at me, something needs you",
/// while an achievement count is a positive flex, and a CTA is a call to add.
enum MADHeaderActionStyle {
    /// Subtle white-on-glass circle. Default for navigation icons (settings,
    /// edit, etc.) where there's nothing to count.
    case standard
    /// Red badge in the corner. For *alerts* the user should react to —
    /// notifications, friend requests.
    case notification(count: Int)
    /// Gold inline pill next to the icon. For *positive counts* — wins,
    /// trophies, achievements. Reads as a flex, not an alarm.
    case achievement(count: Int)
    /// Filled red circle with white icon. For prominent calls-to-action —
    /// create competition, log workout. Higher visual weight than `standard`.
    case cta
}

/// Action button that lives in the right-hand cluster of a `MADTabHeader`.
/// Style determines visual treatment and whether/how a count is displayed.
struct MADHeaderAction: Identifiable {
    let id: String
    let systemImage: String
    let style: MADHeaderActionStyle
    let action: () -> Void

    init(id: String, systemImage: String, style: MADHeaderActionStyle = .standard, action: @escaping () -> Void) {
        self.id = id
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }
}

/// Shared top-of-tab header. Big rounded title on the left, a horizontal row
/// of action buttons on the right. First introduced on the Friends tab —
/// extracted so Compete / Profile all share the same visual language.
struct MADTabHeader: View {
    let title: String
    let actions: [MADHeaderAction]

    init(title: String, actions: [MADHeaderAction] = []) {
        self.title = title
        self.actions = actions
    }

    var body: some View {
        // Center alignment: baseline-aligning the 38pt icon circles against the
        // big title pushed the buttons below the title's visual line. Centering
        // keeps title and buttons level at any text size.
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer(minLength: MADTheme.Spacing.sm)

            HStack(spacing: 8) {
                ForEach(actions) { action in
                    headerButton(action)
                }
            }
            // Buttons keep their intrinsic size; the title scales down first,
            // so the two sides can never compress into each other or overlap.
            .fixedSize()
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.top, MADTheme.Spacing.sm)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func headerButton(_ action: MADHeaderAction) -> some View {
        switch action.style {
        case .standard:
            circleButton(action: action, iconColor: .white.opacity(0.85), fill: Color.white.opacity(0.08), strokeColor: Color.white.opacity(0.10), badge: nil)
        case .notification(let count):
            circleButton(
                action: action,
                iconColor: .white.opacity(0.85),
                fill: Color.white.opacity(0.08),
                strokeColor: Color.white.opacity(0.10),
                badge: count > 0 ? .notification(count) : nil
            )
        case .achievement(let count):
            achievementButton(action: action, count: count)
        case .cta:
            ctaButton(action: action)
        }
    }

    // MARK: - Style: standard / notification

    private func circleButton(
        action: MADHeaderAction,
        iconColor: Color,
        fill: Color,
        strokeColor: Color,
        badge: BadgeKind?
    ) -> some View {
        Button(action: action.action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(fill)
                            .overlay(Circle().strokeBorder(strokeColor, lineWidth: 1))
                    )

                if case .notification(let count) = badge {
                    Text("\(min(count, 99))")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                        .overlay(Capsule().strokeBorder(Color.black, lineWidth: 1.5))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Style: achievement (gold pill)

    /// Trophy / win count rendered as an inline gold pill: icon + number
    /// on a warm gradient. Reads as a flex, not an alert.
    private func achievementButton(action: MADHeaderAction, count: Int) -> some View {
        Button(action: action.action) {
            HStack(spacing: 5) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.yellow.opacity(0.18), Color.orange.opacity(0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.yellow.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Style: CTA (filled red circle)

    /// Prominent filled-red call-to-action. Stands out clearly as "the thing
    /// to tap if you want to create something new".
    private func ctaButton(action: MADHeaderAction) -> some View {
        Button(action: action.action) {
            Image(systemName: action.systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(MADTheme.Colors.madRed)
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.4), radius: 8, y: 3)
                )
        }
        .buttonStyle(.plain)
    }

    private enum BadgeKind {
        case notification(Int)
    }
}

/// Pill-style segmented control used inside tabs for sub-navigation. Replaces
/// the old underline-style `TabButton` used on Compete. Matches the Friends ↔
/// Leaderboard mode picker and the Requests sheet picker so all in-page tabs
/// across the app feel unified.
struct MADPillPicker<Tag: Hashable>: View {
    struct Option: Identifiable {
        let id: Tag
        let title: String
        let systemImage: String?
        let badgeCount: Int

        init(id: Tag, title: String, systemImage: String? = nil, badgeCount: Int = 0) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
            self.badgeCount = badgeCount
        }
    }

    @Binding var selection: Tag
    let options: [Option]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                pill(option)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    private func pill(_ option: Option) -> some View {
        let isSelected = selection == option.id
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                selection = option.id
            }
        } label: {
            HStack(spacing: 6) {
                if let icon = option.systemImage {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(option.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                if option.badgeCount > 0 {
                    Text("\(option.badgeCount)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.25) : MADTheme.Colors.madRed)
                        )
                }
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isSelected ? MADTheme.Colors.madRed : Color.clear)
                    .shadow(color: isSelected ? MADTheme.Colors.madRed.opacity(0.35) : .clear, radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
