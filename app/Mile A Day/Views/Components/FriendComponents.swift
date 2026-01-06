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
        VStack(spacing: MADTheme.Spacing.md) {
            if let stats = stats {
                // Streak and Today's Goal in a row - wrapped in container with padding to match Performance section
                HStack(spacing: MADTheme.Spacing.md) {
                    // Streak Card (smaller, consistent with dashboard style)
                    streakCard(stats: stats)
                    
                    // Today's Goal Card (compact)
                    compactGoalCard(stats: stats)
                }
                .padding(MADTheme.Spacing.md)
                .background(MADTheme.Colors.primaryBackground)
                .cornerRadius(MADTheme.CornerRadius.large)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                // Performance Stats Section
                VStack(spacing: MADTheme.Spacing.md) {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 16))
                            .foregroundColor(MADTheme.Colors.madRed)
                        Text("Performance")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(MADTheme.Colors.primaryText)
                        Spacer()
                    }
                    
                    // Stats Grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: MADTheme.Spacing.md) {
                        FriendStatCard(
                            title: "Total Miles",
                            value: String(format: "%.1f", stats.totalMiles),
                            icon: "map.fill",
                            color: .blue,
                            subtitle: "mi"
                        )
                        FriendStatCard(
                            title: "Best Pace",
                            value: formatPace(stats.fastestMilePace),
                            icon: "timer",
                            color: MADTheme.Colors.madRed,
                            subtitle: "/mi"
                        )
                        FriendStatCard(
                            title: "Best Day",
                            value: String(format: "%.1f", stats.mostMilesInOneDay),
                            icon: "calendar",
                            color: .green,
                            subtitle: "mi"
                        )
                        FriendStatCard(
                            title: "Avg/Day",
                            value: String(format: "%.1f", stats.streak > 0 ? stats.totalMiles / Double(stats.streak) : 0),
                            icon: "chart.bar.fill",
                            color: .purple,
                            subtitle: "mi"
                        )
                    }
                }
                .padding(MADTheme.Spacing.md)
                .background(MADTheme.Colors.primaryBackground)
                .cornerRadius(MADTheme.CornerRadius.large)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            } else {
                loadingOrEmptyState
            }
        }
    }
    
    // MARK: - Streak Card (Dashboard-style)
    @ViewBuilder
    private func streakCard(stats: UserStats) -> some View {
        ZStack {
            // Dynamic gradient based on status (like dashboard)
            LinearGradient(
                gradient: Gradient(colors: stats.hasCompletedGoalToday 
                    ? [Color.green.opacity(0.3), Color.green.opacity(0.1)]
                    : [Color.orange.opacity(0.3), Color.orange.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(alignment: .leading, spacing: 8) {
                // "CURRENT STREAK" header
                Text("STREAK")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(stats.hasCompletedGoalToday ? .green : .orange)
                    .tracking(1.5)
                
                // Streak number with days
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(stats.streak)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(MADTheme.Colors.primaryText)
                    
                    Text("days")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MADTheme.Colors.secondaryText)
                }
                
                Spacer()
                
                // Fire icon at bottom
                HStack {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18))
                        .foregroundColor(stats.hasCompletedGoalToday ? .green : .orange)
                    Spacer()
                    if stats.hasCompletedGoalToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(MADTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .cornerRadius(MADTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .stroke(stats.hasCompletedGoalToday 
                    ? Color.green.opacity(0.3) 
                    : Color.orange.opacity(0.3), 
                    lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Compact Goal Card
    @ViewBuilder
    private func compactGoalCard(stats: UserStats) -> some View {
        ZStack {
            // Background
            MADTheme.Colors.secondaryBackground
            
            VStack(alignment: .leading, spacing: 8) {
                // Header
                Text("DAILY GOAL")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .tracking(1.5)
                
                // Goal value
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", stats.goalMiles))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(MADTheme.Colors.primaryText)
                    
                    Text("mi")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MADTheme.Colors.secondaryText)
                }
                
                Spacer()
                
                // Status
                HStack {
                    Image(systemName: stats.hasCompletedGoalToday ? "checkmark.circle.fill" : "target")
                        .font(.system(size: 18))
                        .foregroundColor(stats.hasCompletedGoalToday ? .green : MADTheme.Colors.madRed)
                    Spacer()
                }
            }
            .padding(MADTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .cornerRadius(MADTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .stroke(stats.hasCompletedGoalToday 
                    ? Color.green.opacity(0.2) 
                    : MADTheme.Colors.madRed.opacity(0.2), 
                    lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Loading/Empty State
    private var loadingOrEmptyState: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(MADTheme.Colors.madRed)
            
            Text("Loading stats...")
                .font(MADTheme.Typography.caption)
                .foregroundColor(MADTheme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.xl)
    }
    
    // MARK: - Helper Functions
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
    var subtitle: String? = nil
    
    var body: some View {
        ZStack {
            // Subtle gradient background like streak card
            LinearGradient(
                gradient: Gradient(colors: [
                    color.opacity(0.08),
                    color.opacity(0.03)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(alignment: .leading, spacing: 8) {
                // Header label
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
                    .tracking(1.5)
                
                // Value
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(MADTheme.Colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MADTheme.Colors.secondaryText)
                    }
                }
                
                Spacer()
                
                // Icon at bottom
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(color)
                    Spacer()
                }
            }
            .padding(MADTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .cornerRadius(MADTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
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
    let hasCompletedGoalToday: Bool
    let goalMiles: Double
}

// MARK: - Recent Workout Model (API Response)
struct RecentWorkout: Codable {
    let userId: String
    let workoutId: String
    let distance: Double
    let localDate: String
    let date: String
    let timezoneOffset: Int
    let workoutType: String
    let deviceEndDate: String
    let calories: Double
    let totalDuration: TimeInterval
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case workoutId = "workout_id"
        case distance
        case localDate = "local_date"
        case date
        case timezoneOffset = "timezone_offset"
        case workoutType = "workout_type"
        case deviceEndDate = "device_end_date"
        case calories
        case totalDuration = "total_duration"
    }
    
    /// Extracts just the date part (yyyy-MM-dd) from the local_date string
    var dateOnly: String {
        // local_date comes as ISO format like "2025-10-26T00:00:00.000Z"
        // Extract just the date part
        let components = localDate.components(separatedBy: "T")
        return components.first ?? localDate
    }
}

// MARK: - Streak Response Model
struct StreakResponse: Codable {
    let streak: Int
}
