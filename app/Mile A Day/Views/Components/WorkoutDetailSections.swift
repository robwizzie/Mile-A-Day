import SwiftUI

/// The building blocks of a workout's detail screen, defined ONCE and shared by
/// your own `WorkoutDetailView` and a friend's `FriendWorkoutDetailSheet`.
///
/// The two screens were assembled separately and drifted: a friend's run showed
/// no route/photo tags, a bare stat row with no header, and no timeline at all,
/// so the same workout read as a different thing depending on whose it was.
/// Composing both from these means they can't drift again.

/// The red-gradient header above each detail card ("Stats", "Timeline", …).
struct WorkoutDetailSectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MADTheme.Colors.redGradient)
            Text(title)
                .font(MADTheme.Typography.headline)
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

/// A "Route" / "Photo" pill in the hero — the detail-sized sibling of the row's
/// `WorkoutTagChip`.
struct WorkoutHeroTag: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// The detail's hero: how it was recorded, the activity type, the hero distance,
/// the date, and what the run carries.
///
/// Deliberately un-animated. The route probe and post fetch land a beat after
/// the screen opens, and animating the tags in made the whole card resize under
/// the reader — the same reflow `WorkoutRow` already learned to avoid ("a crisp
/// appearance reads cleaner"). The tags simply appear.
struct WorkoutHeroCard<Banner: View>: View {
    private let icon: String
    private let typeLabel: String
    private let color: Color
    private let distanceText: String
    private let dateText: String
    private let source: WorkoutSource
    private let hasRoute: Bool
    private let hasPhoto: Bool
    private let banner: Banner

    init(
        icon: String,
        typeLabel: String,
        color: Color,
        distanceText: String,
        dateText: String,
        source: WorkoutSource = .healthkit,
        hasRoute: Bool = false,
        hasPhoto: Bool = false,
        @ViewBuilder banner: () -> Banner
    ) {
        self.icon = icon
        self.typeLabel = typeLabel
        self.color = color
        self.distanceText = distanceText
        self.dateText = dateText
        self.source = source
        self.hasRoute = hasRoute
        self.hasPhoto = hasPhoto
        self.banner = banner()
    }

    var body: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            // How it was recorded, first — a manual entry says so before it
            // says anything else.
            ManualWorkoutBanner(source: source)

            // Caller-supplied warnings (e.g. the vehicle-speed notice on your
            // own runs), inside the card with the rest of the header.
            banner

            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(typeLabel)
                    .font(MADTheme.Typography.smallBold)
            }
            .foregroundColor(color)
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.xs + 2)
            .background(Capsule().fill(color.opacity(0.15)))

            Text(distanceText)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(dateText)
                .font(MADTheme.Typography.body)
                .foregroundColor(.secondary)

            if hasRoute || hasPhoto {
                HStack(spacing: MADTheme.Spacing.sm) {
                    if hasRoute {
                        WorkoutHeroTag(icon: "map.fill", label: "Route", color: color)
                    }
                    if hasPhoto {
                        WorkoutHeroTag(icon: "photo.fill", label: "Photo", color: .pink)
                    }
                }
                .padding(.top, MADTheme.Spacing.xs)
            }
        }
        .padding(MADTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .madLiquidGlass()
    }
}

extension WorkoutHeroCard where Banner == EmptyView {
    init(
        icon: String,
        typeLabel: String,
        color: Color,
        distanceText: String,
        dateText: String,
        source: WorkoutSource = .healthkit,
        hasRoute: Bool = false,
        hasPhoto: Bool = false
    ) {
        self.init(
            icon: icon,
            typeLabel: typeLabel,
            color: color,
            distanceText: distanceText,
            dateText: dateText,
            source: source,
            hasRoute: hasRoute,
            hasPhoto: hasPhoto,
            banner: { EmptyView() }
        )
    }
}

/// The run's headline numbers. Distance lives in the hero; everything else
/// lives here, once.
struct WorkoutStatsCard: View {
    let duration: String
    let pace: String
    /// Omitted entirely when absent — never rendered as a zero.
    var calories: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            WorkoutDetailSectionHeader(icon: "chart.bar.fill", title: "Stats")
            HStack(spacing: MADTheme.Spacing.sm) {
                DashboardStatBox(
                    title: "Duration",
                    value: duration,
                    icon: "clock.fill",
                    color: .orange
                )
                DashboardStatBox(
                    title: "Pace",
                    value: pace,
                    icon: "speedometer",
                    color: .green
                )
                if let calories {
                    DashboardStatBox(
                        title: "Calories",
                        value: "\(calories)",
                        icon: "flame.fill",
                        color: MADTheme.Colors.madRed
                    )
                }
            }
        }
    }
}

/// When the run started and ended.
struct WorkoutTimelineCard: View {
    let startText: String
    let endText: String

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            WorkoutDetailSectionHeader(icon: "clock.arrow.2.circlepath", title: "Timeline")
            DetailRow(icon: "play.fill", iconColor: .green, title: "Start", value: startText)
            DetailRow(icon: "stop.fill", iconColor: MADTheme.Colors.madRed, title: "End", value: endText)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }
}
