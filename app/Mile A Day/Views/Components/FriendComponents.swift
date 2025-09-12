import SwiftUI

// MARK: - User Profile Card Component
/// Reusable component for displaying user profile information
struct UserProfileCard: View {
    let user: BackendUser
    let showStats: Bool
    let showBadges: Bool
    let onTap: () -> Void
    let actionButton: AnyView?
    
    init(
        user: BackendUser,
        showStats: Bool = true,
        showBadges: Bool = true,
        onTap: @escaping () -> Void,
        actionButton: AnyView? = nil
    ) {
        self.user = user
        self.showStats = showStats
        self.showBadges = showBadges
        self.onTap = onTap
        self.actionButton = actionButton
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: MADTheme.Spacing.md) {
                // Profile Image
                ProfileImageView(user: user, size: 60)
                
                VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                    // Username and Name
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.username ?? "Unknown")
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(MADTheme.Colors.primaryText)
                        
                        if user.displayName != user.username {
                            Text(user.displayName)
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(MADTheme.Colors.secondaryText)
                        }
                    }
                    
                    // Bio
                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                // Action Button
                if let actionButton = actionButton {
                    actionButton
                }
            }
            .padding(MADTheme.Spacing.md)
            .madCard()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Profile Image View
/// Reusable profile image component with fallback
struct ProfileImageView: View {
    let user: BackendUser
    let size: CGFloat
    
    var body: some View {
        Group {
            if user.hasProfileImage, let imageURL = user.profile_image_url {
                AsyncImage(url: URL(string: imageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                        .frame(width: size, height: size)
                }
            } else {
                // Fallback to initials
                Text(user.initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: size, height: size)
                    .background(MADTheme.Colors.redGradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(MADTheme.Colors.madRed.opacity(0.3), lineWidth: 2)
        )
    }
}

// MARK: - Friend Action Button
/// Reusable button for friend actions
struct FriendActionButton: View {
    let title: String
    let style: FriendActionStyle
    let action: () -> Void
    let isLoading: Bool
    
    init(
        title: String,
        style: FriendActionStyle = .primary,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.action = action
        self.isLoading = isLoading
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: MADTheme.Spacing.xs) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: style.foregroundColor))
                } else {
                    Text(title)
                        .font(MADTheme.Typography.smallBold)
                }
            }
            .foregroundColor(style.foregroundColor)
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                    .fill(style.backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                            .stroke(style.borderColor, lineWidth: style.borderWidth)
                    )
            )
        }
        .disabled(isLoading)
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Friend Action Styles
enum FriendActionStyle {
    case primary
    case secondary
    case destructive
    case success
    
    var backgroundColor: Color {
        switch self {
        case .primary:
            return MADTheme.Colors.madRed.opacity(0.1)
        case .secondary:
            return Color.clear
        case .destructive:
            return Color.red.opacity(0.1)
        case .success:
            return Color.green.opacity(0.1)
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .primary:
            return MADTheme.Colors.madRed
        case .secondary:
            return MADTheme.Colors.secondaryText
        case .destructive:
            return .red
        case .success:
            return .green
        }
    }
    
    var borderColor: Color {
        switch self {
        case .primary:
            return MADTheme.Colors.madRed.opacity(0.3)
        case .secondary:
            return MADTheme.Colors.secondaryText.opacity(0.3)
        case .destructive:
            return .red.opacity(0.3)
        case .success:
            return .green.opacity(0.3)
        }
    }
    
    var borderWidth: CGFloat {
        switch self {
        case .primary, .destructive, .success:
            return 1
        case .secondary:
            return 0
        }
    }
}

// MARK: - Friend Stats View
/// Component for displaying user stats (when public)
struct FriendStatsView: View {
    let user: BackendUser
    let stats: UserStats?
    
    var body: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            HStack {
                Text("Stats")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(MADTheme.Colors.primaryText)
                Spacer()
            }
            
            if let stats = stats {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: MADTheme.Spacing.md) {
                    FriendStatCard(title: "Streak", value: "\(stats.streak)", icon: "flame.fill", color: .orange)
                    FriendStatCard(title: "Total Miles", value: String(format: "%.1f", stats.totalMiles), icon: "figure.run", color: MADTheme.Colors.madRed)
                    FriendStatCard(title: "Best Pace", value: formatPace(stats.fastestMilePace), icon: "timer", color: .blue)
                    FriendStatCard(title: "Best Day", value: String(format: "%.1f mi", stats.mostMilesInOneDay), icon: "calendar", color: .green)
                }
            } else {
                Text("Stats not available")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(MADTheme.Spacing.lg)
            }
        }
        .padding(MADTheme.Spacing.md)
        .madCard()
    }
    
    private func formatPace(_ pace: TimeInterval) -> String {
        if pace == 0 {
            return "N/A"
        }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

// MARK: - Friend Stat Card
struct FriendStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: MADTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(MADTheme.Typography.title3)
                .foregroundColor(MADTheme.Colors.primaryText)
            
            Text(title)
                .font(MADTheme.Typography.caption)
                .foregroundColor(MADTheme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                .fill(MADTheme.Colors.secondaryBackground)
        )
    }
}

// MARK: - Friend Badges View
/// Component for displaying user badges (when public)
struct FriendBadgesView: View {
    let badges: [Badge]
    
    var body: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            HStack {
                Text("Badges")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(MADTheme.Colors.primaryText)
                Spacer()
                Text("\(badges.count)")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.secondaryText)
            }
            
            if badges.isEmpty {
                Text("No badges yet")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(MADTheme.Spacing.lg)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: MADTheme.Spacing.md) {
                    ForEach(badges.prefix(6)) { badge in
                        BadgeView(badge: badge)
                    }
                }
                
                if badges.count > 6 {
                    Text("+ \(badges.count - 6) more")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                        .padding(.top, MADTheme.Spacing.sm)
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .madCard()
    }
}

// MARK: - Badge View
struct BadgeView: View {
    let badge: Badge
    
    var body: some View {
        VStack(spacing: MADTheme.Spacing.xs) {
            Image(systemName: "medal.fill")
                .font(.title2)
                .foregroundColor(badge.rarity.color)
            
            Text(badge.name)
                .font(MADTheme.Typography.caption)
                .foregroundColor(MADTheme.Colors.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                .fill(badge.rarity.color.opacity(0.1))
        )
    }
}

// MARK: - Empty State View
struct FriendEmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(
        title: String,
        message: String,
        systemImage: String = "person.2",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 64))
                .foregroundColor(MADTheme.Colors.madRed.opacity(0.6))
            
            VStack(spacing: MADTheme.Spacing.sm) {
                Text(title)
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(MADTheme.Colors.primaryText)
                
                Text(message)
                    .font(MADTheme.Typography.body)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .madPrimaryButton()
            }
        }
        .padding(MADTheme.Spacing.xl)
    }
}

// MARK: - Extensions
extension BackendUser {
    var initials: String {
        let components = displayName.components(separatedBy: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else {
            return String(displayName.prefix(2)).uppercased()
        }
    }
}

// MARK: - User Stats Model
struct UserStats: Codable {
    let streak: Int
    let totalMiles: Double
    let fastestMilePace: TimeInterval
    let mostMilesInOneDay: Double
}
