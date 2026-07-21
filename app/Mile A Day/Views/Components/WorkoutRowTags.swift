import SwiftUI

/// One metadata chip on a workout row — "Route", "Photo".
///
/// Fixed-size by construction: a row's chips must never be the thing that
/// gives when space runs short, or the label wraps mid-word inside its capsule.
struct WorkoutTagChip: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// The chips under a workout row's headline: how it was recorded, and what
/// tapping in will reveal. ONE definition shared by the dashboard's own
/// `WorkoutRow` and a friend's `FriendWorkoutRow`, so a workout reads
/// identically no matter whose it is.
///
/// They sit on their own line rather than beside the distance because the
/// badges can't shrink: a title line carrying verb + hero distance + badge,
/// competing with a trailing date column, ran out of room on narrow screens and
/// wrapped both the distance and the badge mid-word.
struct WorkoutRowTags: View {
    var source: WorkoutSource = .healthkit
    var hasRoute: Bool = false
    var hasPhoto: Bool = false
    /// Accent for the Route chip — the workout's own type color.
    var routeColor: Color

    private var isManualOrEdited: Bool { source == .manual || source == .edited }

    var body: some View {
        if isManualOrEdited || hasRoute || hasPhoto {
            HStack(spacing: 6) {
                ManualWorkoutBadge(source: source)
                if hasRoute {
                    WorkoutTagChip(icon: "map.fill", label: "Route", color: routeColor)
                }
                if hasPhoto {
                    WorkoutTagChip(icon: "photo.fill", label: "Photo", color: .pink)
                }
            }
            .padding(.top, 1)
        }
    }
}
