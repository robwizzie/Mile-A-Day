import SwiftUI

// MARK: - Competition Type Card

struct CompetitionTypeCard: View {
    let type: CompetitionType
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                HStack {
                    Image(systemName: type.icon)
                        .font(.title)
                        .foregroundStyle(
                            LinearGradient(
                                colors: type.gradient.map { Color(hex: $0) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .background(
                            Circle()
                                .fill(Color(hex: type.gradient[0]).opacity(0.15))
                        )

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(MADTheme.Colors.primary)
                    }
                }

                Text(type.displayName)
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.white)

                Text(type.description)
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(
                            isSelected
                                ? AnyShapeStyle(MADTheme.Colors.primary)
                                : AnyShapeStyle(LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .shadow(
                color: isSelected ? MADTheme.Colors.primary.opacity(0.3) : .black.opacity(0.1),
                radius: isSelected ? 12 : 8,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Competition Card

struct CompetitionCard: View {
    let competition: Competition
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                // Header with icon and type
                HStack {
                    Image(systemName: competition.type.icon)
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: competition.type.gradient.map { Color(hex: $0) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color(hex: competition.type.gradient[0]).opacity(0.15))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(competition.competition_name)
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(.white)

                        Text(competition.type.displayName)
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    if competition.isOwner {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }

                // Goal info
                HStack(spacing: MADTheme.Spacing.sm) {
                    Label(
                        "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)",
                        systemImage: "target"
                    )
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    Label(
                        "\(competition.acceptedUsersCount) participant\(competition.acceptedUsersCount == 1 ? "" : "s")",
                        systemImage: "person.2.fill"
                    )
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.9))
                }

                // Dates
                if let startDate = competition.startDateFormatted,
                   let endDate = competition.endDateFormatted {
                    HStack(spacing: MADTheme.Spacing.xs) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

                        Text("\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Invite Card

struct InviteCard: View {
    let competition: Competition
    let onAccept: () -> Void
    let onDecline: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            // Header
            HStack {
                Image(systemName: competition.type.icon)
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: competition.type.gradient.map { Color(hex: $0) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color(hex: competition.type.gradient[0]).opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(competition.competition_name)
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.white)

                    Text("from \(competition.owner)")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()
            }

            // Type and goal
            VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                Text(competition.type.displayName)
                    .font(MADTheme.Typography.subheadline)
                    .foregroundColor(.white.opacity(0.9))

                Text(competition.type.description)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)

                HStack(spacing: MADTheme.Spacing.sm) {
                    Label(
                        "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)",
                        systemImage: "target"
                    )
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.9))
                }
            }

            // Action buttons
            HStack(spacing: MADTheme.Spacing.md) {
                Button(action: onDecline) {
                    Text("Decline")
                        .font(MADTheme.Typography.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(ScaleButtonStyle())

                Button(action: onAccept) {
                    Text("Accept")
                        .font(MADTheme.Typography.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(MADTheme.Colors.primaryGradient)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(MADTheme.Spacing.lg)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Activity Toggle

struct ActivityToggle: View {
    let activity: CompetitionActivity
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: activity.icon)
                    .font(.caption)

                Text(activity.displayName)
                    .font(MADTheme.Typography.callout)
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.pill)
                    .fill(isSelected ? MADTheme.Colors.primaryGradient : LinearGradient(colors: [Color.white.opacity(0.1)], startPoint: .leading, endPoint: .trailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.pill)
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Tab Button

struct CompetitionTabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: MADTheme.Spacing.xs) {
                HStack(spacing: MADTheme.Spacing.xs) {
                    Text(title)
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(isSelected ? MADTheme.Colors.madRed : MADTheme.Colors.secondaryText)

                    if count > 0 {
                        Text("\(count)")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, MADTheme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(MADTheme.Colors.madRed)
                            )
                    }
                }

                Rectangle()
                    .fill(isSelected ? MADTheme.Colors.madRed : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Custom Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

