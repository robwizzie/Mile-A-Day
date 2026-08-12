import SwiftUI

/// A friend who is walking or running RIGHT NOW, with how far they've got.
///
/// One row, used everywhere presence appears — the dashboard, the friends list,
/// the tracker's sheet — so a friend mid-walk looks the same wherever you meet
/// them. Presence used to be a name and a green dot; the thing anyone watching
/// actually wants is how it's going, which is why the ring and the distance are
/// the row's centre rather than decoration.
///
/// Progress is drawn against THEIR goal, not the viewer's. A friend on a
/// two-mile goal rendered against a one-mile bar reads as finished when they're
/// halfway.
///
/// Two actions, both one tap:
///   - **Hype** — always available. It's the cheap, generous one, and it lands
///     on their tracking screen mid-walk (LivePresenceService picks it up), so
///     it is genuinely real-time encouragement rather than a notification they
///     read afterwards.
///   - **Join** / **Ask to walk** — Join when they're in a room with space,
///     Ask when they're on their own. Hidden while the viewer is mid-workout,
///     because you cannot join a walk during a walk.
struct FriendOutLiveRow: View {
    let name: String
    let imageURL: String?
    let isRunning: Bool
    /// Nil when the server hasn't reported one yet (older build, or the very
    /// first heartbeat). The row degrades to presence-only rather than
    /// asserting a confident "0.00".
    let distanceMiles: Double?
    let goalMiles: Double
    let subtitle: String
    let canJoin: Bool
    let joinTitle: String
    /// Nil hides the action entirely — used while the viewer is mid-workout.
    let onJoin: (() -> Void)?
    let onHype: (() -> Void)?
    var hyped: Bool = false
    var hypeBusy: Bool = false
    var busy: Bool = false

    private var accent: Color {
        MADTheme.workoutColor(isRunning ? "running" : "walking")
    }

    private var progress: Double {
        guard let distanceMiles, goalMiles > 0 else { return 0 }
        return min(1, distanceMiles / goalMiles)
    }

    /// "0.62 of 1 mi" — the goal is stated so the ring is self-explaining.
    private var distanceText: String {
        guard let distanceMiles else { return isRunning ? "Running" : "Walking" }
        let goal = goalMiles == goalMiles.rounded()
            ? "\(Int(goalMiles))" : String(format: "%.1f", goalMiles)
        return String(format: "%.2f of %@ mi", distanceMiles, goal)
    }

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            AvatarWithRing(
                name: name,
                imageURL: imageURL,
                progress: progress,
                size: 46,
                ringWidth: 3,
                accent: accent
            )
            .overlay(alignment: .bottomTrailing) {
                // Live dot. It earns its place HERE, unlike on the buddy roster
                // where every face was mid-workout by definition — in a friends
                // list most people are not out, so "this one is, right now" is
                // the whole point of the row.
                Circle()
                    .fill(MADTheme.Colors.success)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(MADTheme.Colors.madBlack, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                    .lineLimit(1)

                Text(distanceText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)

                Text(subtitle)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: MADTheme.Spacing.xs)

            actions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(MADTheme.Colors.madWhite.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .strokeBorder(MADTheme.Colors.success.opacity(0.30), lineWidth: 1)
        )
        // Keyed on the distance so a friend's number animates as it lands
        // rather than snapping between polls.
        .animation(MADTheme.Animation.standard, value: distanceMiles)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if let onHype {
                Button {
                    guard !hyped, !hypeBusy else { return }
                    onHype()
                } label: {
                    Group {
                        if hypeBusy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(MADTheme.Colors.madWhite)
                        } else {
                            Image(systemName: hyped ? "hands.clap.fill" : "hands.clap")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(width: 38, height: 34)
                    .background(
                        Capsule().fill(
                            hyped
                                ? MADTheme.Colors.warning.opacity(0.30)
                                : MADTheme.Colors.madWhite.opacity(0.12))
                    )
                    .foregroundStyle(
                        hyped ? MADTheme.Colors.warning : MADTheme.Colors.madWhite)
                }
                .buttonStyle(.plain)
                .disabled(hyped || hypeBusy)
            }

            if let onJoin, canJoin {
                Button(action: onJoin) {
                    Group {
                        if busy {
                            ProgressView().tint(MADTheme.Colors.madWhite)
                        } else {
                            Text(joinTitle)
                                .font(MADTheme.Typography.smallBold)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Capsule().fill(accent))
                    .foregroundStyle(MADTheme.Colors.madWhite)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
        // Actions must never be squeezed by a long name — the name truncates
        // first, which is the right sacrifice.
        .fixedSize()
    }
}

/// How long they've been out, e.g. "out 12m". Shared so every surface phrases
/// it the same way.
enum FriendOutTime {
    static func elapsed(since iso: String?) -> String? {
        guard let iso, let start = BuddyDate.parse(iso) else { return nil }
        let minutes = Int(Date().timeIntervalSince(start) / 60)
        guard minutes >= 1 else { return "just started" }
        if minutes < 60 { return "out \(minutes)m" }
        return "out \(minutes / 60)h \(minutes % 60)m"
    }
}
