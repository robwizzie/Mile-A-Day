import SwiftUI

// MARK: - Create Competition Supporting Components

struct CompactTypeButton: View {
    let icon: String
    let label: String
    let iconColor: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? iconColor : .white.opacity(0.6))

                Text(label)
                    .font(MADTheme.Typography.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.md)
            .padding(.horizontal, MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .stroke(
                        isSelected ? iconColor.opacity(0.5) : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct FriendSelectRow: View {
    let friend: BackendUser
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MADTheme.Spacing.md) {
                // Friend avatar
                AvatarView(name: friend.displayName, imageURL: friend.profile_image_url, size: 50)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? MADTheme.Colors.primary : Color.white.opacity(0.2), lineWidth: 2)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayName)
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.white)

                    if let username = friend.username {
                        Text("@\(username)")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(MADTheme.Colors.primary)
                } else {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .stroke(
                                isSelected ? MADTheme.Colors.primary.opacity(0.5) : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Custom Text Field Style

struct MADTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundColor(.white)
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - Duration Preset Component

struct DurationPreset: View {
    let title: String
    let hours: Int
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? MADTheme.Colors.primary : .white.opacity(0.6))

                Text(title)
                    .font(MADTheme.Typography.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(isSelected ? MADTheme.Colors.primary.opacity(0.2) : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .stroke(
                        isSelected ? MADTheme.Colors.primary : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Interval Option Button

struct IntervalOptionButton: View {
    let interval: CompetitionInterval
    let isSelected: Bool
    let action: () -> Void

    var icon: String {
        switch interval {
        case .day:
            return "calendar.day.timeline.left"
        case .week:
            return "calendar.badge.clock"
        case .month:
            return "calendar"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? MADTheme.Colors.primary : .white.opacity(0.6))

                Text(interval.displayName)
                    .font(MADTheme.Typography.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(isSelected ? MADTheme.Colors.primary.opacity(0.2) : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .stroke(
                        isSelected ? MADTheme.Colors.primary : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
